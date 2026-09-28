#!/usr/bin/env bash
# evals/run.sh — paired baseline: the native harness vs. hephaestus, on the same tasks.
#
#   evals/run.sh validate [task...]    Unbilled. Each acceptance check must reject the
#                                      task's base and accept its reference fix.
#   evals/run.sh run --budget-usd N [--repeats N] [--seed N] [--arms native,full] [task...]
#                                      Billed. Live headless runs, one fresh sandbox each.
#   evals/run.sh report <results.tsv>  Per-arm and per-task summary.
#
# Protocol: evals/protocol.md. Arms, metrics, and the acceptance standard are fixed
# there before any result is read.
#
# Environment:
#   HEPH_EVAL_PIN      hephaestus revision the full arm installs (default: HEAD)
#   HEPH_EVAL_MODEL    model passed to the harness (default: claude-opus-5-5)
#   HEPH_EVAL_TIMEOUT  seconds per run before it is killed (default: 3600)
#   HEPH_EVAL_OUT      results directory (default: evals/results)
#   HEPH_EVAL_CMD      replaces the harness command; tests point it at a stub

set -uo pipefail

EVAL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$EVAL_DIR/.." && pwd)
MODEL=${HEPH_EVAL_MODEL:-claude-opus-5-5}
TIMEOUT=${HEPH_EVAL_TIMEOUT:-3600}
OUT=${HEPH_EVAL_OUT:-$EVAL_DIR/results}
COLUMNS_TSV="task	arm	repeat	accepted	regression	committed	cost_usd	duration_s	turns	exit	timed_out	model	harness_version	pin	base"

# The harness's own generated adapters: stripped from every sandbox so the native
# arm is native and the full arm sees only the pinned install.
ADAPTER_DIRS=".claude/commands .claude/agents .opencode .agents .codex .hermes .cursor"
# What a user-level install needs — and nothing that reveals a task's fix.
PIN_PATHS=".claude .opencode .agents .codex .hermes .cursor .ai templates install.sh update.sh uninstall.sh loop.sh VERSION scripts/models.sh"

die() { echo "evals: $*" >&2; exit 1; }

task_list() {
  if [ $# -gt 0 ]; then printf '%s\n' "$@"; else ls "$EVAL_DIR/tasks"; fi
}

load_task() {
  local f="$EVAL_DIR/tasks/$1/task.env"
  [ -f "$f" ] || die "no such task: $1"
  ISSUE="" BASE="" FIX="" REGRESSION=""
  # shellcheck disable=SC1090
  . "$f"
  [ -n "$ISSUE" ] && [ -n "$BASE" ] && [ -n "$FIX" ] && [ -n "$REGRESSION" ] || die "$f: ISSUE, BASE, FIX, REGRESSION required"
}

git_q() { git -c user.name=eval -c user.email=eval@example.invalid "$@"; }

# sandbox <task> <dir>: the repo at BASE with no history past it, a local origin,
# an isolated HOME, and a gh that serves only the task's issue.
sandbox() {
  local task=$1 sb=$2 d
  mkdir -p "$sb/repo" "$sb/bin" "$sb/home"
  git -C "$ROOT" archive "$BASE" | tar -x -C "$sb/repo" || die "cannot export $BASE"
  for d in $ADAPTER_DIRS; do rm -rf "${sb:?}/repo/$d"; done
  git_q -C "$sb/repo" init -q
  git_q -C "$sb/repo" add -A
  git_q -C "$sb/repo" commit -qm "base"
  git init -q --bare "$sb/origin.git"
  git -C "$sb/repo" remote add origin "$sb/origin.git"
  git -C "$sb/repo" push -q origin HEAD 2>/dev/null
  cp "$EVAL_DIR/tasks/$task/issue.md" "$sb/issue.md"
  cat > "$sb/bin/gh" <<SHIM
#!/usr/bin/env bash
# Evaluation gh: serves issue #$ISSUE and refuses everything else — no network.
printf '%s\n' "gh \$*" >> "$sb/gh.log"
[ "\${1:-} \${2:-}" = "issue view" ] || { echo "gh: disabled during evaluation" >&2; exit 1; }
title=\$(head -1 "$sb/issue.md" | sed 's/^# //'); body=\$(tail -n +3 "$sb/issue.md")
json=0 q=""
while [ \$# -gt 0 ]; do case "\$1" in --json) json=1; shift ;; -q|--jq) q=\$2; shift ;; esac; shift; done
[ "\$json" = 1 ] || { printf '%s\n\n%s\n' "\$title" "\$body"; exit 0; }
doc=\$(jq -n --arg t "\$title" --arg b "\$body" '{number: $ISSUE, title: \$t, body: \$b, state: "OPEN", labels: [], comments: []}')
if [ -n "\$q" ]; then jq -r "\$q" <<<"\$doc"; else printf '%s\n' "\$doc"; fi
SHIM
  chmod +x "$sb/bin/gh"
}

# accept <task> <sb>: the acceptance standard, independent of anything the agent
# reports. Prints "accepted regression": each 0 or 1, regression "na" for a task
# whose base tests pin behavior its reference fix legitimately changes.
accept() {
  local task=$1 sb=$2 a=0 r=0 check="$2/check"
  rm -rf "$check"; cp -R "$sb/repo" "$check"
  bash "$EVAL_DIR/tasks/$task/accept.sh" "$check" > "$sb/accept.log" 2>&1 && a=1
  # Regression: the base revision's own tests, restored so edits to them cannot pass.
  if [ "$REGRESSION" = none ]; then
    r=na
  else
    rm -rf "$check/tests"
    git -C "$ROOT" archive "$BASE" tests | tar -x -C "$check"
    bash "$check/$REGRESSION" > "$sb/regression.log" 2>&1 && r=1
  fi
  echo "$a $r"
}

cmd_validate() {
  local task sb verdict fails=0
  for task in $(task_list "$@"); do
    load_task "$task"
    sb=$(mktemp -d "${TMPDIR:-/tmp}/heph-eval-XXXXXX")
    sandbox "$task" "$sb"
    verdict=$(accept "$task" "$sb")
    if [ "${verdict% *}" = 1 ]; then echo "✗ $task: acceptance passes on the unfixed base"; fails=$((fails + 1)); fi
    git -C "$ROOT" diff "$BASE" "$FIX" -- . ':!tests' ':!changelog.d' ':!CHANGELOG.md' ':!CLAUDE.md' \
      | git -C "$sb/repo" apply || die "$task: reference fix does not apply"
    verdict=$(accept "$task" "$sb")
    if [ "$verdict" = "1 1" ] || [ "$verdict" = "1 na" ]; then echo "✓ $task"; else echo "✗ $task: reference fix scored '$verdict' (accepted regression)"; fails=$((fails + 1)); fi
    rm -rf "$sb"
  done
  [ "$fails" -eq 0 ]
}

# Run one prompt headless; print "cost duration turns exit timed_out" from the harness's JSON.
invoke() {
  local sb=$1 prompt=$2 json rc timed_out=0 start end
  start=$(date +%s)
  (
    cd "$sb/repo" || exit 1
    export HOME="$sb/home" XDG_STATE_HOME="$sb/state" XDG_CONFIG_HOME="$sb/config" PATH="$sb/bin:$PATH"
    if [ -n "${HEPH_EVAL_CMD:-}" ]; then
      exec perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" $HEPH_EVAL_CMD "$prompt"
    fi
    exec perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" \
      claude -p "$prompt" --output-format json --model "$MODEL" --dangerously-skip-permissions
  ) > "$sb/harness.json" 2> "$sb/harness.err"
  rc=$?; end=$(date +%s)
  [ "$rc" = 142 ] && timed_out=1   # SIGALRM
  json=$(cat "$sb/harness.json")
  num() { sed -n "s/.*\"$1\": *\([0-9.eE+-]*\).*/\1/p" <<<"$json" | head -1; }
  printf '%s %s %s %s %s\n' "$(num total_cost_usd || true)" "$((end - start))" "$(num num_turns || true)" "$rc" "$timed_out"
}

cmd_run() {
  local budget="" repeats=3 seed="" arms="native,full" tasks=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --budget-usd) budget=$2; shift 2 ;;
      --repeats) repeats=$2; shift 2 ;;
      --seed) seed=$2; shift 2 ;;
      --arms) arms=$2; shift 2 ;;
      -*) die "unknown flag: $1" ;;
      *) tasks+=("$1"); shift ;;
    esac
  done
  [ -n "$budget" ] || die "run is billed: --budget-usd is required"
  command -v jq >/dev/null || die "jq is required (the gh shim uses it)"
  if [ -z "${HEPH_EVAL_CMD:-}" ]; then
    command -v claude >/dev/null || die "claude not on PATH"
    [ -n "${ANTHROPIC_API_KEY:-}" ] || die "ANTHROPIC_API_KEY is required: the isolated HOME has no stored login"
  fi
  seed=${seed:-$(date +%s)}
  local pin; pin=$(git -C "$ROOT" rev-parse "${HEPH_EVAL_PIN:-HEAD}") || die "bad HEPH_EVAL_PIN"
  local hv="stub"; [ -n "${HEPH_EVAL_CMD:-}" ] || hv=$(claude --version 2>/dev/null | head -1)
  mkdir -p "$OUT"
  local results="$OUT/results-$(date +%Y%m%d-%H%M%S)-$seed.tsv"
  printf '%s\n' "$COLUMNS_TSV" > "$results"
  echo "# seed=$seed pin=$pin model=$MODEL harness=$hv budget_usd=$budget" > "$results.meta"

  # Every (task, arm, repeat), shuffled by seed so order effects do not favor an arm.
  local plan task arm i
  plan=$(for task in $(task_list "${tasks[@]+"${tasks[@]}"}"); do
    for arm in ${arms//,/ }; do
      case "$arm" in native|full) ;; *) die "unknown arm: $arm" ;; esac
      for i in $(seq 1 "$repeats"); do printf '%s %s %s\n' "$task" "$arm" "$i"; done
    done
  done | awk -v s="$seed" 'BEGIN { srand(s) } { print rand() "\t" $0 }' | sort -n | cut -f2-)

  local spent=0 sb stats cost dur turns rc to verdict committed prompt
  while read -r task arm i; do
    [ -n "$task" ] || continue
    if awk -v s="$spent" -v b="$budget" 'BEGIN { exit !(s >= b) }'; then
      echo "budget reached (\$$spent of \$$budget) — stopping; remaining runs not executed"; break
    fi
    load_task "$task"
    sb=$(mktemp -d "${TMPDIR:-/tmp}/heph-eval-XXXXXX")
    sandbox "$task" "$sb"
    if [ "$arm" = full ]; then
      mkdir -p "$sb/heph"
      # shellcheck disable=SC2086
      git -C "$ROOT" archive "$pin" -- $PIN_PATHS | tar -x -C "$sb/heph"
      (cd "$sb/heph" && HOME="$sb/home" XDG_STATE_HOME="$sb/state" XDG_CONFIG_HOME="$sb/config" ./install.sh >/dev/null 2>&1) \
        || die "full arm: install failed in $sb"
      prompt="/start-issue $ISSUE"
    else
      prompt="Resolve GitHub issue #$ISSUE in this repository (read it with \`gh issue view $ISSUE\`). Work autonomously without asking questions, verify your fix, and finish with it committed on a new branch. Do not push or open a pull request."
    fi
    read -r cost dur turns rc to <<<"$(invoke "$sb" "$prompt")"
    cost=${cost:-0}
    verdict=$(accept "$task" "$sb")
    committed=0; [ -z "$(git -C "$sb/repo" status --porcelain)" ] && [ "$(git -C "$sb/repo" rev-list --count HEAD)" -gt 1 ] && committed=1
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$task" "$arm" "$i" "${verdict% *}" "${verdict#* }" "$committed" "$cost" "$dur" "${turns:-}" "$rc" "$to" \
      "$MODEL" "$hv" "$pin" "$BASE" >> "$results"
    spent=$(awk -v s="$spent" -v c="$cost" 'BEGIN { print s + c }')
    mkdir -p "$OUT/runs"; mv "$sb" "$OUT/runs/$task-$arm-$i-$seed"
    echo "$task/$arm/$i: accepted=${verdict% *} regression=${verdict#* } cost=\$$cost ${dur}s (spent \$$spent)"
  done <<<"$plan"
  echo "results: $results"
}

cmd_report() {
  local f=${1:-}; [ -f "$f" ] || die "usage: report <results.tsv>"
  awk -F'\t' '
    NR == 1 { next }
    { ok = ($4 == 1 && ($5 == 1 || $5 == "na"))
      k = $2; n[k]++; acc[k] += $4; reg[k] += ok; cost[k] += $7; dur[k] += $8; to[k] += $11
      t = $1 FS $2; tn[t]++; ta[t] += ok; tasks[$1] = 1 }
    END {
      printf "%-8s %5s %9s %9s %10s %9s %8s\n", "arm", "runs", "accepted", "+regress", "mean_cost", "mean_s", "timeouts"
      for (k in n) printf "%-8s %5d %8.0f%% %8.0f%% %10.2f %9.0f %8d\n", k, n[k], 100*acc[k]/n[k], 100*reg[k]/n[k], cost[k]/n[k], dur[k]/n[k], to[k]
      printf "\nper task (accepted with regression passing / runs):\n"
      for (t in tasks) {
        line = sprintf("  %-32s", t)
        for (k in n) { key = t FS k; line = line sprintf("  %s %d/%d", k, ta[key], tn[key]) }
        print line
      }
    }' "$f"
}

case "${1:-}" in
  validate) shift; cmd_validate "$@" ;;
  run) shift; cmd_run "$@" ;;
  report) shift; cmd_report "$@" ;;
  *) die "usage: evals/run.sh validate [task...] | run --budget-usd N [...] | report <results.tsv>" ;;
esac
