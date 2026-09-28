#!/usr/bin/env bash
# evals/run.sh — paired baseline: the native harness vs. hephaestus, on the same tasks.
#
#   evals/run.sh validate [task...]    Unbilled. Each acceptance check must reject the
#                                      task's base and accept its reference fix.
#   evals/run.sh run --budget-usd N [--run-cap-usd N] [--repeats N] [--seed N] [--arms native,full] [task...]
#                                      Billed. Live headless runs, one fresh sandbox each.
#   evals/run.sh report <results.tsv>  Per-arm and per-task summary.
#
# Protocol: evals/protocol.md. Arms, metrics, and the acceptance standard are fixed
# there before any result is read.
#
# Environment:
#   HEPH_EVAL_PIN      hephaestus revision the full arm installs (default: HEAD)
#   HEPH_EVAL_MODEL    model passed to the harness (default: claude-opus-5-5)
#   HEPH_EVAL_TIMEOUT  seconds per run before its process group is killed (default: 3600)
#   HEPH_EVAL_OUT      results directory (default: $XDG_STATE_HOME/hephaestus/evals — outside
#                      the repo, so no run can read another's archived solution)
#   HEPH_EVAL_CMD      replaces the harness command; tests point it at a stub. Word-split
#                      on purpose, so it may carry arguments.

set -uo pipefail

EVAL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$EVAL_DIR/.." && pwd)
MODEL=${HEPH_EVAL_MODEL:-claude-opus-5-5}
TIMEOUT=${HEPH_EVAL_TIMEOUT:-3600}
OUT=${HEPH_EVAL_OUT:-${XDG_STATE_HOME:-$HOME/.local/state}/hephaestus/evals}
COLUMNS_TSV="task	arm	repeat	accepted	regression	committed	contaminated	cost_usd	duration_s	turns	exit	timed_out	model	harness_version	pin	base"

# The repo's own generated adapters: stripped from every sandbox so the native arm
# is native and the full arm sees only the pinned install.
ADAPTER_DIRS=".claude/commands .claude/agents .opencode .agents .codex .hermes .cursor"
# What a user-level install needs — and nothing that reveals a task's fix.
PIN_PATHS=".claude .opencode .agents .codex .hermes .cursor .ai templates install.sh update.sh uninstall.sh loop.sh VERSION scripts/models.sh"
# Identical for both arms: no web access, since the fixes are public.
DISALLOWED_TOOLS="WebFetch WebSearch"
# The one stop instruction both arms receive, so they end at the same endpoint.
STOP="Stop once the fix is verified and committed on a new local branch: do not push, open a pull request, or switch back to the base branch."

die() { echo "evals: $*" >&2; exit 1; }

task_list() {
  if [ $# -gt 0 ]; then printf '%s\n' "$@"; else ls "$EVAL_DIR/tasks"; fi
}

load_task() {
  local f="$EVAL_DIR/tasks/$1/task.env"
  [ -f "$f" ] || die "no such task: $1"
  ISSUE="" BASE="" FIX="" REGRESSION="" REGRESSION_DROP=""
  # shellcheck disable=SC1090
  . "$f"
  [ -n "$ISSUE" ] && [ -n "$BASE" ] && [ -n "$FIX" ] && [ -n "$REGRESSION" ] || die "$f: ISSUE, BASE, FIX, REGRESSION required"
}

git_q() { git -c user.name=eval -c user.email=eval@example.invalid "$@"; }

# work_branches <repo>: local branches carrying commits past the base, newest first.
work_branches() {
  git -C "$1" for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads \
    | while read -r b; do [ "$(git -C "$1" rev-list --count "$b")" -gt 1 ] && echo "$b"; done
}

# sandbox <task> <dir>: the repo at BASE with no history past it, a local origin with
# origin/HEAD set, an isolated HOME, and a gh that serves only the task's issue.
sandbox() {
  local task=$1 sb=$2 d
  mkdir -p "$sb/repo" "$sb/bin" "$sb/home" "$sb/tmp"
  git -C "$ROOT" archive "$BASE" | tar -x -C "$sb/repo" || die "cannot export $BASE"
  for d in $ADAPTER_DIRS; do rm -rf "${sb:?}/repo/$d"; done
  git_q -C "$sb/repo" init -q
  git_q -C "$sb/repo" add -A
  git_q -C "$sb/repo" commit -qm "base"
  git init -q --bare "$sb/origin.git"
  git -C "$sb/repo" remote add origin "$sb/origin.git"
  git -C "$sb/repo" push -q origin HEAD 2>/dev/null
  git -C "$sb/repo" remote set-head origin -a >/dev/null 2>&1
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
# reports. Prints "accepted regression", each 0 or 1. Scores the endpoint — the newest
# branch carrying work — even if the agent left HEAD on a clean base.
accept() {
  local task=$1 sb=$2 a=0 r=0 check="$2/check" tip
  rm -rf "$check"; cp -R "$sb/repo" "$check"
  if [ "$(git -C "$check" rev-list --count HEAD)" = 1 ] && [ -z "$(git -C "$check" status --porcelain)" ]; then
    tip=$(work_branches "$check" | head -1)
    [ -n "$tip" ] && git -C "$check" checkout -q "$tip"
  fi
  bash "$EVAL_DIR/tasks/$task/accept.sh" "$check" > "$sb/accept.log" 2>&1 && a=1
  # Regression: the base revision's own tests, restored so edits to them cannot pass.
  rm -rf "$check/tests"
  git -C "$ROOT" archive "$BASE" tests | tar -x -C "$check"
  if [ -n "$REGRESSION_DROP" ]; then
    grep -vF -- "$REGRESSION_DROP" "$check/$REGRESSION" > "$check/$REGRESSION.kept" && mv "$check/$REGRESSION.kept" "$check/$REGRESSION"
  fi
  bash "$check/$REGRESSION" > "$sb/regression.log" 2>&1 && r=1
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
    if [ "$verdict" = "1 1" ]; then echo "✓ $task"; else echo "✗ $task: reference fix scored '$verdict' (accepted regression)"; fails=$((fails + 1)); fi
    rm -rf "$sb"
  done
  [ "$fails" -eq 0 ]
}

# Run one prompt headless in a clean environment. Prints tab-separated
# "cost duration turns exit timed_out"; a field the harness did not report is "na".
invoke() {
  local sb=$1 prompt=$2 cap=$3 rc timed_out=0 start end cost turns
  local -a cmd
  if [ -n "${HEPH_EVAL_CMD:-}" ]; then
    # shellcheck disable=SC2206
    cmd=($HEPH_EVAL_CMD "$prompt")
  else
    # shellcheck disable=SC2086
    cmd=(claude -p "$prompt" --output-format json --model "$MODEL" --max-budget-usd "$cap"
         --disallowedTools $DISALLOWED_TOOLS --dangerously-skip-permissions)
  fi
  start=$(date +%s)
  # env -i: nothing from the operator's shell (tokens, HEPH_EVAL_*) reaches the agent.
  # The watchdog kills the whole process group, so no test or build outlives a timeout.
  (cd "$sb/repo" && env -i PATH="$sb/bin:$PATH" HOME="$sb/home" TMPDIR="$sb/tmp" LANG="${LANG:-C.UTF-8}" \
      TERM=dumb XDG_STATE_HOME="$sb/state" XDG_CONFIG_HOME="$sb/config" ${ANTHROPIC_API_KEY:+ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"} \
      perl -e '$t = shift; $pid = fork; if (!$pid) { setpgrp(0, 0); exec @ARGV; exit 127 }
               $SIG{ALRM} = sub { kill "TERM", -$pid; sleep 5; kill "KILL", -$pid; exit 142 };
               alarm $t; waitpid($pid, 0); exit(($? & 127) ? 128 + ($? & 127) : $? >> 8)' "$TIMEOUT" "${cmd[@]}") \
    > "$sb/harness.json" 2> "$sb/harness.err"
  rc=$?; end=$(date +%s)
  [ "$rc" = 142 ] && timed_out=1
  cost=$(sed -n 's/.*"total_cost_usd": *\([0-9.eE+-]*\).*/\1/p' "$sb/harness.json" | head -1)
  turns=$(sed -n 's/.*"num_turns": *\([0-9]*\).*/\1/p' "$sb/harness.json" | head -1)
  printf '%s\t%s\t%s\t%s\t%s\n' "${cost:-na}" "$((end - start))" "${turns:-na}" "$rc" "$timed_out"
}

# contaminated <sb>: 1 if the agent's transcript touched the evaluation checkout or
# the public repository — a run that may have seen the answer.
contaminated() {
  grep -rqsF -e "$ROOT" -e "github.com/amurshak/hephaestus" "$1/home/.claude/projects" "$1/harness.json" && echo 1 || echo 0
}

min() { awk -v a="$1" -v b="$2" 'BEGIN { print (a < b ? a : b) }'; }

cmd_run() {
  local budget="" cap="" repeats=3 seed="" arms="native,full" tasks=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --budget-usd) budget=${2:-}; shift 2 ;;
      --run-cap-usd) cap=${2:-}; shift 2 ;;
      --repeats) repeats=${2:-}; shift 2 ;;
      --seed) seed=${2:-}; shift 2 ;;
      --arms) arms=${2:-}; shift 2 ;;
      -*) die "unknown flag: $1" ;;
      *) tasks+=("$1"); shift ;;
    esac
  done
  # Validate the whole plan before anything is billed.
  [ -n "$budget" ] || die "run is billed: --budget-usd is required"
  local n; for n in "$budget" ${cap:+"$cap"}; do [[ "$n" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "not a dollar amount: $n"; done
  [[ "$repeats" =~ ^[1-9][0-9]*$ ]] || die "--repeats must be a positive integer"
  cap=${cap:-$budget}
  local arm task
  for arm in ${arms//,/ }; do case "$arm" in native|full) ;; *) die "unknown arm: $arm" ;; esac; done
  for task in $(task_list "${tasks[@]+"${tasks[@]}"}"); do load_task "$task"; done
  command -v jq >/dev/null || die "jq is required (the gh shim uses it)"
  if [ -z "${HEPH_EVAL_CMD:-}" ]; then
    command -v claude >/dev/null || die "claude not on PATH"
    [ -n "${ANTHROPIC_API_KEY:-}" ] || die "ANTHROPIC_API_KEY is required: the isolated HOME has no stored login"
  fi
  seed=${seed:-$(date +%s)}
  local pin; pin=$(git -C "$ROOT" rev-parse "${HEPH_EVAL_PIN:-HEAD}") || die "bad HEPH_EVAL_PIN"
  local hv="stub"; [ -n "${HEPH_EVAL_CMD:-}" ] || hv=$(claude --version 2>/dev/null | head -1)
  local stamp; stamp=$(date +%Y%m%d-%H%M%S)
  mkdir -p "$OUT/runs"
  local results="$OUT/results-$stamp-$seed.tsv"
  printf '%s\n' "$COLUMNS_TSV" > "$results"
  echo "# seed=$seed pin=$pin model=$MODEL harness=$hv budget_usd=$budget run_cap_usd=$cap" > "$results.meta"

  # Every (task, arm, repeat), shuffled by seed so order effects do not favor an arm.
  local plan i
  plan=$(for task in $(task_list "${tasks[@]+"${tasks[@]}"}"); do
    for arm in ${arms//,/ }; do
      for i in $(seq 1 "$repeats"); do printf '%s %s %s\n' "$task" "$arm" "$i"; done
    done
  done | awk -v s="$seed" 'BEGIN { srand(s) } { print rand() "\t" $0 }' | sort -n | cut -f2-)
  [ -n "$plan" ] || die "empty plan"

  local spent=0 sb cost dur turns rc to verdict committed contam prompt remaining held charge
  while read -r task arm i; do
    remaining=$(awk -v s="$spent" -v b="$budget" 'BEGIN { r = b - s; print (r > 0 ? r : 0) }')
    if awk -v r="$remaining" 'BEGIN { exit !(r <= 0) }'; then
      echo "budget reached (\$$spent of \$$budget) — stopping; remaining runs not executed"; break
    fi
    load_task "$task"
    sb=$(mktemp -d "${TMPDIR:-/tmp}/heph-eval-XXXXXX")
    sandbox "$task" "$sb"
    prompt="Resolve GitHub issue #$ISSUE in this repository (read it with \`gh issue view $ISSUE\`). Work autonomously without asking questions. $STOP"
    if [ "$arm" = full ]; then
      prompt="/start-issue $ISSUE — $STOP"
      mkdir -p "$sb/heph"
      # shellcheck disable=SC2086
      if ! { git -C "$ROOT" archive "$pin" -- $PIN_PATHS | tar -x -C "$sb/heph" \
             && (cd "$sb/heph" && env -i PATH="$PATH" HOME="$sb/home" XDG_STATE_HOME="$sb/state" XDG_CONFIG_HOME="$sb/config" ./install.sh >"$sb/install.log" 2>&1); }; then
        printf '%s\t%s\t%s\t0\t0\t0\t0\t0\t0\tna\tinstall_failed\t0\t%s\t%s\t%s\t%s\n' "$task" "$arm" "$i" "$MODEL" "$hv" "$pin" "$BASE" >> "$results"
        mv "$sb" "$OUT/runs/$task-$arm-$i-$stamp-$seed"; echo "$task/$arm/$i: install failed"; continue
      fi
    fi
    held=$(min "$remaining" "$cap")
    IFS=$'\t' read -r cost dur turns rc to <<<"$(invoke "$sb" "$prompt" "$held")"
    verdict=$(accept "$task" "$sb")
    committed=0; [ -z "$(git -C "$sb/repo" status --porcelain)" ] && [ -n "$(work_branches "$sb/repo")" ] && committed=1
    contam=$(contaminated "$sb")
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$task" "$arm" "$i" "${verdict% *}" "${verdict#* }" "$committed" "$contam" "$cost" "$dur" "$turns" "$rc" "$to" \
      "$MODEL" "$hv" "$pin" "$BASE" >> "$results"
    # An unreported cost is charged at the cap the harness was held to — never as zero.
    charge=$cost; [ "$cost" = na ] && charge=$held
    spent=$(awk -v s="$spent" -v c="$charge" 'BEGIN { print s + c }')
    mv "$sb" "$OUT/runs/$task-$arm-$i-$stamp-$seed"
    echo "$task/$arm/$i: accepted=${verdict% *} regression=${verdict#* } cost=\$$cost ${dur}s timed_out=$to (spent \$$spent)"
  done <<<"$plan"
  echo "results: $results"
}

cmd_report() {
  local f=${1:-}; [ -f "$f" ] || die "usage: report <results.tsv>"
  awk -F'\t' '
    function wilson(k, n,   p, z, c, h) {  # 95% Wilson interval
      if (n == 0) return "-"; z = 1.96; p = k / n
      c = (p + z*z/(2*n)) / (1 + z*z/n); h = z * sqrt(p*(1-p)/n + z*z/(4*n*n)) / (1 + z*z/n)
      return sprintf("%.0f-%.0f%%", 100*(c-h), 100*(c+h))
    }
    NR == 1 { next }
    { ok = ($4 == 1 && $5 == 1); a = $2; t = $1
      n[a]++; acc[a] += ok; com[a] += $6; con[a] += $7; to[a] += ($12 == 1); fail[a] += ($12 == "install_failed")
      if ($8 != "na") { cost[a] += $8; costed[a]++; if (ok) okcost[a] += $8 } else nacost[a]++
      dur[a] += $9; tn[t, a]++; ta[t, a] += ok; tasks[t] = 1 }
    END {
      na = 0; for (a in n) arms[++na] = a
      for (i = 1; i <= na; i++) for (j = i + 1; j <= na; j++) if (arms[j] < arms[i]) { x = arms[i]; arms[i] = arms[j]; arms[j] = x }
      printf "%-7s %4s %9s %9s %9s %11s %7s %8s %9s %6s\n", "arm", "runs", "accepted", "95% CI", "cost/run", "cost/accept", "mean_s", "timeouts", "committed", "contam"
      for (i = 1; i <= na; i++) { a = arms[i]
        printf "%-7s %4d %8.0f%% %9s %9s %11s %7.0f %8d %8.0f%% %6d\n", a, n[a], 100*acc[a]/n[a], wilson(acc[a], n[a]),
          costed[a] ? sprintf("%.2f", cost[a]/costed[a]) : "na", acc[a] ? sprintf("%.2f", okcost[a]/acc[a]) : "na",
          dur[a]/n[a], to[a], 100*com[a]/n[a], con[a]
        if (nacost[a] || fail[a]) printf "        (%d run(s) reported no cost; %d install failure(s))\n", nacost[a], fail[a] }
      nt = 0; for (t in tasks) tl[++nt] = t
      for (i = 1; i <= nt; i++) for (j = i + 1; j <= nt; j++) if (tl[j] < tl[i]) { x = tl[i]; tl[i] = tl[j]; tl[j] = x }
      printf "\nper task: accepted/runs by arm; * = discordant (arms disagree on majority acceptance)\n"
      for (i = 1; i <= nt; i++) { t = tl[i]; line = sprintf("  %-30s", t); d = ""; first = -1
        for (j = 1; j <= na; j++) { a = arms[j]; k = (t SUBSEP a)
          line = line sprintf("  %s %d/%d", a, ta[k], tn[k])
          m = (tn[k] && ta[k] * 2 > tn[k]); if (first < 0) first = m; else if (m != first) d = " *" }
        print line d }
      print "\nPilot scale: any arm difference is provisional (evals/protocol.md, Decision rule)."
    }' "$f"
}

case "${1:-}" in
  validate) shift; cmd_validate "$@" ;;
  run) shift; cmd_run "$@" ;;
  report) shift; cmd_report "$@" ;;
  *) die "usage: evals/run.sh validate [task...] | run --budget-usd N [...] | report <results.tsv>" ;;
esac
