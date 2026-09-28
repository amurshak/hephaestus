#!/usr/bin/env bash
# Verification evidence is bound to the revision it checked (#224).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

evidence_section() {
  awk '/^## Evidence records$/ { found=1; next } found && /^#/ { exit } found { print }' "$1"
}
contract=$(evidence_section "$HEPHAESTUS_ROOT/.ai/workflows/ship.md")
ship=$(cat "$HEPHAESTUS_ROOT/.ai/workflows/ship.md")
testing=$(cat "$HEPHAESTUS_ROOT/.ai/workflows/test-issue.md")
starting=$(cat "$HEPHAESTUS_ROOT/.ai/workflows/start-issue.md")

begin_test "producers and consumers share one evidence contract"
assert_contains "contract is present" "$contract" 'Each check yields one record'
for path in workflows/test-issue workflows/start-issue agents/tester; do
  assert_eq "$path contract agrees" "$contract" "$(evidence_section "$HEPHAESTUS_ROOT/.ai/$path.md")"
done

begin_test "records carry scope, method, outcome, revision, and environment"
assert_contains "record fields" "$contract" 'check, scope, command or method, outcome, and revision — HEAD OID and clean or dirty tree'
assert_contains "environment assumptions" "$contract" 'plus any environment it depends on (tool versions, services, credentials)'
assert_contains "five distinct outcomes" "$contract" 'passed, failed, blocked (could not run), not run, or not applicable'
assert_contains "only passed satisfies" "$contract" 'and only passed satisfies one'

begin_test "an unchanged result is reused, not rerun"
assert_contains "covering record is reused" "$contract" 'Reuse a covering record, including one handed over by another command'
assert_contains "ship reuses instead of rerunning" "$ship" 'reuse a covering record instead of rerunning'
assert_contains "start-issue hands records to ship" "$starting" '`/test-issue` evidence records for `/ship` to reuse'
assert_contains "test-issue reuses too" "$testing" 'Reuse a covering evidence record'

begin_test "edits after review or gates invalidate what they touch"
assert_contains "later commits invalidate" "$ship" 'Any commit after a gate or critique ran — a fix, a doc edit, a rebase — invalidates the records it touches'
assert_contains "affected gates repeat" "$ship" 'repeat affected critique and test gates before pushing'
assert_contains "unsure means rerun" "$contract" 'rerun when unsure what a check reads'

begin_test "docs are finished before the gates, and doc changes rerun doc gates"
docs_line=$(grep -n '^### 2. Update docs' "$HEPHAESTUS_ROOT/.ai/workflows/ship.md" | cut -d: -f1)
critique_line=$(grep -n '^### 3. Pre-push critique gate' "$HEPHAESTUS_ROOT/.ai/workflows/ship.md" | cut -d: -f1)
gates_line=$(grep -n '^### 4. Run quality gates' "$HEPHAESTUS_ROOT/.ai/workflows/ship.md" | cut -d: -f1)
assert_eq "docs precede critique" "1" "$([ -n "$docs_line" ] && [ -n "$critique_line" ] && [ "$docs_line" -lt "$critique_line" ] && echo 1 || echo 0)"
assert_eq "critique precedes gates" "1" "$([ -n "$critique_line" ] && [ -n "$gates_line" ] && [ "$critique_line" -lt "$gates_line" ] && echo 1 || echo 0)"
assert_contains "doc checks read the docs" "$contract" 'for doc checks — the docs'

begin_test "required, optional, and undefined gates are distinguished"
assert_contains "required gates defined" "$contract" "Required gates are the critique plus the project's Development Commands"
assert_contains "undefined gate is not applicable" "$contract" 'a gate the project does not define is not applicable'
assert_contains "dirty-tree record limited" "$contract" 'A dirty-tree record covers only if its dirty paths are outside what the check reads'
assert_contains "fixes revisit docs" "$ship" 'update docs the fix makes inaccurate'

begin_test "environment changes invalidate"
assert_contains "environment is a read input" "$contract" 'code, dependencies, configuration, environment'

begin_test "blocked and optional checks are never claimed as passed"
assert_contains "not-run is never passed" "$contract" 'never report a check that did not run as passed'
assert_contains "optional check listed as not run" "$ship" 'an optional check not executed is listed as not run, never passed'
assert_contains "blocked gate drafts" "$ship" 'If a gate could not run (blocked)'

begin_test "generic claims are replaced by evidence"
assert_not_contains "no generic no-regressions claim" "$ship" 'No regressions'
assert_not_contains "no bare critique PASS checkbox" "$ship" '- [x] Code critique: PASS'
assert_contains "evidence table in PR body" "$ship" '| Check | Command or method | Outcome | Revision |'
assert_contains "rows bound to delivered HEAD" "$ship" 'every required row passed at the delivered HEAD or through a covering record the row names'

begin_test "ordinary commands run through tools"
assert_not_contains "test-issue no longer always delegates" "$testing" 'Always delegate to subagent(s)'
assert_contains "test-issue runs gates directly" "$testing" 'Run gate commands directly with tools, keeping exit status'
assert_contains "ship runs gates directly" "$ship" 'Run each gate command directly with tools'
assert_contains "tester reserved for interpretation" "$ship" 'only for long or ambiguous output or an independent acceptance check'
hermes_ship=$(cat "$HEPHAESTUS_ROOT/.hermes/skills/hephaestus/ship/SKILL.md")
assert_contains "hermes delegates only delegating steps" "$hermes_ship" 'Where a step below delegates to a role'
assert_not_contains "hermes does not force every named role" "$hermes_ship" 'Where a step below names a role'
for wf in autopilot refactor; do
  assert_contains "$wf summarizes docs-first ship" "$(cat "$HEPHAESTUS_ROOT/.ai/workflows/$wf.md")" 'It updates docs, runs the pre-push critique and quality gates'
done

print_summary
