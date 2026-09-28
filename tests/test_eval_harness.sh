#!/usr/bin/env bash
# evals/run.sh — the baseline harness's unbilled guarantees (#242). No model is called:
# live runs go through a stub harness.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

RUN="$HEPHAESTUS_ROOT/evals/run.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/heph-evaltest-XXXXXX")
trap 'rm -rf "$WORK"' EXIT

begin_test "every acceptance check rejects its base and accepts its reference fix"
out=$("$RUN" validate 2>&1); rc=$?
assert_exit_code "validate passes" 0 "$rc"
for t in "$HEPHAESTUS_ROOT"/evals/tasks/*/; do
  assert_contains "$(basename "$t") validated" "$out" "✓ $(basename "$t")"
done

begin_test "live runs are opt-in and budgeted"
out=$("$RUN" run 2>&1); rc=$?
assert_exit_code "run without a budget refuses" 1 "$rc"
assert_contains "names the budget flag" "$out" "--budget-usd is required"
out=$(HEPH_EVAL_CMD=/bin/true "$RUN" run --budget-usd 1 --bogus 2>&1); rc=$?
assert_exit_code "unknown flag refuses" 1 "$rc"

if ! command -v jq >/dev/null; then
  pass "stub run skipped: jq not installed"
  print_summary; exit $?
fi

begin_test "a stub run records every field and stops at the budget"
cat > "$WORK/harness" <<'STUB'
#!/usr/bin/env bash
gh issue view 1 --json title -q .title > "$HOME/seen-title"
gh pr create --title x >/dev/null 2>&1 && touch "$HOME/pr-allowed"
git rev-list --count HEAD > "$HOME/history-depth"
ls -d .claude/commands 2>/dev/null > "$HOME/adapters-seen"
printf '{"type":"result","total_cost_usd": 0.4,"num_turns": 5}\n'
STUB
chmod +x "$WORK/harness"
out=$(HEPH_EVAL_CMD="$WORK/harness" HEPH_EVAL_OUT="$WORK/out" "$RUN" run --budget-usd 0.5 --repeats 2 --seed 3 \
  --arms native,full changelog-conflict-markers 2>&1); rc=$?
assert_exit_code "stub run completes" 0 "$rc"
results=$(ls "$WORK"/out/results-*-3.tsv 2>/dev/null | head -1)
assert_file_exists "results table written" "$results"
assert_eq "budget stops after crossing it" "2" "$(tail -n +2 "$results" | wc -l | tr -d ' ')"
assert_contains "budget stop is reported" "$out" "budget reached"
row=$(tail -n +2 "$results" | head -1)
assert_eq "no-op fix is not accepted" "0" "$(cut -f4 <<<"$row")"
assert_eq "cost parsed from harness JSON" "0.4" "$(cut -f7 <<<"$row")"
assert_eq "turns parsed" "5" "$(cut -f9 <<<"$row")"
assert_contains "seed and pin recorded" "$(cat "$results.meta")" "seed=3 pin="
run_dir=$(ls -d "$WORK"/out/runs/*-3 | head -1)
assert_contains "gh shim serves the task issue" "$(cat "$run_dir/home/seen-title")" "conflict markers"
assert_file_not_exists "gh shim refuses everything else" "$run_dir/home/pr-allowed"
assert_eq "sandbox has no history past the base" "1" "$(cat "$run_dir/home/history-depth")"
assert_eq "sandbox carries no harness adapters" "" "$(cat "$run_dir/home/adapters-seen")"

begin_test "the full arm's pinned install withholds the code under test"
full_dir=$(ls -d "$WORK"/out/runs/*-full-*-3 2>/dev/null | head -1)
if [ -n "$full_dir" ]; then
  # Archived runs are moved, so the install's absolute symlinks no longer resolve.
  assert_eq "commands installed into the isolated HOME" "1" "$([ -L "$full_dir/home/.claude/commands/start-issue.md" ] && echo 1 || echo 0)"
  assert_file_not_exists "no collect-changelog in the pin" "$full_dir/heph/scripts/collect-changelog.sh"
  assert_file_not_exists "no changelog in the pin" "$full_dir/heph/CHANGELOG.md"
  assert_file_not_exists "no tasks in the pin" "$full_dir/heph/evals"
else
  pass "full arm ordered after the budget stop at this seed"
fi

begin_test "report summarizes per arm and per task"
out=$("$RUN" report "$results" 2>&1); rc=$?
assert_exit_code "report succeeds" 0 "$rc"
assert_contains "per-task line" "$out" "changelog-conflict-markers"

print_summary
