#!/usr/bin/env bash
# evals/run.sh — the baseline harness's unbilled guarantees (#242). No model is called:
# live runs go through a stub harness.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

RUN="$HEPHAESTUS_ROOT/evals/run.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/heph-evaltest-XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# validate runs each task's regression suite twice, so the default suite checks one task;
# HEPH_TEST_EVAL_ALL=1 validates every task (do it when adding or changing one).
begin_test "acceptance checks reject their base and accept their reference fix"
if [ "${HEPH_TEST_EVAL_ALL:-0}" = 1 ]; then vtasks=$(ls "$HEPHAESTUS_ROOT/evals/tasks"); else vtasks=changelog-conflict-markers; fi
# shellcheck disable=SC2086
out=$("$RUN" validate $vtasks 2>&1); rc=$?
assert_exit_code "validate passes" 0 "$rc"
for t in $vtasks; do assert_contains "$t validated" "$out" "✓ $t"; done

begin_test "a stale REGRESSION_DROP is refused before anything is billed"
# A throwaway clone, so the fixture task never appears in the checkout under test.
git clone -q --shared --no-checkout "$HEPHAESTUS_ROOT" "$WORK/r"
mkdir -p "$WORK/r/evals/tasks/stale"
cp "$RUN" "$WORK/r/evals/run.sh"
( . "$HEPHAESTUS_ROOT/evals/tasks/changelog-preview-legacy/task.env"
  printf 'ISSUE=%s\nBASE=%s\nFIX=%s\nREGRESSION=%s\nREGRESSION_DROP=%s\n' \
    "$ISSUE" "$BASE" "$FIX" "$REGRESSION" "'no such assertion anywhere'" ) > "$WORK/r/evals/tasks/stale/task.env"
out=$(HEPH_EVAL_CMD=/bin/true HEPH_EVAL_OUT="$WORK/stale" "$WORK/r/evals/run.sh" run --budget-usd 1 stale 2>&1); rc=$?
assert_exit_code "stale drop refuses" 1 "$rc"
assert_contains "names the drop" "$out" "REGRESSION_DROP must match exactly one line"
assert_file_not_exists "nothing was run" "$WORK/stale"

begin_test "live runs are opt-in and budgeted"
out=$("$RUN" run 2>&1); rc=$?
assert_exit_code "run without a budget refuses" 1 "$rc"
assert_contains "names the budget flag" "$out" "--budget-usd is required"
out=$(HEPH_EVAL_CMD=/bin/true "$RUN" run --budget-usd 1 --bogus 2>&1); rc=$?
assert_exit_code "unknown flag refuses" 1 "$rc"

begin_test "an invalid plan is refused before anything runs"
for bad in "--arms native,bogus" "--arms ," "no-such-task" "--repeats 0" "--budget-usd 1 --run-cap-usd x"; do
  # shellcheck disable=SC2086
  out=$(HEPH_EVAL_CMD=/bin/true HEPH_EVAL_OUT="$WORK/refused" "$RUN" run --budget-usd 1 $bad 2>&1); rc=$?
  assert_exit_code "'$bad' refuses" 1 "$rc"
done
assert_file_not_exists "no results or runs were created" "$WORK/refused"

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
assert_eq "contamination column recorded clean" "0" "$(tail -n +2 "$results" | head -1 | cut -f7)"
assert_file_exists "results table written" "$results"
assert_eq "budget stops after crossing it" "2" "$(tail -n +2 "$results" | wc -l | tr -d ' ')"
assert_contains "budget stop is reported" "$out" "budget reached"
row=$(tail -n +2 "$results" | head -1)
assert_eq "no-op fix is not accepted" "0" "$(cut -f4 <<<"$row")"
assert_eq "cost parsed from harness JSON" "0.4" "$(cut -f8 <<<"$row")"
assert_eq "turns parsed" "5" "$(cut -f10 <<<"$row")"
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

begin_test "the run plan never reaches a harness's stdin, so every planned run executes"
cat > "$WORK/reader" <<'STUB'
#!/usr/bin/env bash
cat > "$HOME/stdin-seen"
git config user.email > "$HOME/identity"
printf '{"total_cost_usd": 0.01,"num_turns": 1}\n'
STUB
chmod +x "$WORK/reader"
out=$(HEPH_EVAL_CMD="$WORK/reader" HEPH_EVAL_OUT="$WORK/reader-out" "$RUN" run --budget-usd 5 --repeats 3 --seed 9 \
  --arms native changelog-conflict-markers 2>&1); rc=$?
assert_exit_code "stdin-reading run completes" 0 "$rc"
assert_eq "all three planned runs executed" "3" "$(tail -n +2 "$(ls "$WORK"/reader-out/results-*-9.tsv | head -1)" | wc -l | tr -d ' ')"
for seen in "$WORK"/reader-out/runs/*/home/stdin-seen; do
  assert_eq "harness stdin is empty ($(basename "$(dirname "$(dirname "$seen")")"))" "" "$(cat "$seen")"
done
assert_eq "sandbox commits use the eval identity" "eval@example.invalid" "$(cat "$(ls "$WORK"/reader-out/runs/*/home/identity | head -1)")"

begin_test "a budget stop lists the runs it did not execute"
out=$(HEPH_EVAL_CMD="$WORK/reader" HEPH_EVAL_OUT="$WORK/stop-out" "$RUN" run --budget-usd 0.01 --repeats 3 --seed 4 \
  --arms native changelog-conflict-markers 2>&1)
assert_contains "names the stop" "$out" "not executed:"
assert_eq "two runs listed as not executed" "2" "$(grep -c '^  changelog-conflict-markers native' <<<"$out")"

begin_test "a timed-out run keeps its columns, counts as a timeout, and is charged its cap"
printf '#!/usr/bin/env bash\nsleep 30\n' > "$WORK/slow"; chmod +x "$WORK/slow"
out=$(HEPH_EVAL_TIMEOUT=2 HEPH_EVAL_CMD="$WORK/slow" HEPH_EVAL_OUT="$WORK/slow-out" "$RUN" run --budget-usd 1 --run-cap-usd 0.3 \
  --repeats 1 --seed 5 --arms native changelog-conflict-markers 2>&1); rc=$?
assert_exit_code "timeout run completes" 0 "$rc"
slow=$(tail -n +2 "$(ls "$WORK"/slow-out/results-*-5.tsv | head -1)")
assert_eq "unknown cost is na, not shifted" "na" "$(cut -f8 <<<"$slow")"
assert_eq "turns unknown" "na" "$(cut -f10 <<<"$slow")"
assert_eq "exit is SIGALRM" "142" "$(cut -f11 <<<"$slow")"
assert_eq "timed_out flagged" "1" "$(cut -f12 <<<"$slow")"
assert_contains "charged the per-run cap" "$out" "spent \$0.3"
slow_report=$("$RUN" report "$(ls "$WORK"/slow-out/results-*-5.tsv | head -1)")
assert_contains "report counts the timeout and missing cost" "$slow_report" "1 run(s) reported no cost"

begin_test "report counts install failures and excludes their cost"
synthetic="$WORK/synthetic.tsv"
head -1 "$results" > "$synthetic"
printf 'changelog-arg-order\tfull\t1\t0\t0\t0\t0\tna\t0\tna\tinstall_failed\t0\tm\th\tp\tb\n' >> "$synthetic"
printf 'changelog-arg-order\tfull\t2\t1\t1\t1\t0\t2.00\t60\t9\t0\t0\tm\th\tp\tb\n' >> "$synthetic"
syn=$("$RUN" report "$synthetic")
assert_contains "install failure counted" "$syn" "1 install failure(s)"
assert_contains "cost/run averages only reported costs" "$syn" "2.00"

begin_test "report summarizes per arm and per task"
out=$("$RUN" report "$results" 2>&1); rc=$?
assert_exit_code "report succeeds" 0 "$rc"
assert_contains "per-task line" "$out" "changelog-conflict-markers"

print_summary
