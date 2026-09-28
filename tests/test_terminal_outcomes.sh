#!/usr/bin/env bash
# Unmet requirements and exhausted gates end in a terminal outcome, never a
# normal PR or merge (#222). Pins the contract in each workflow that owns a path.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

read_ai() { cat "$HEPHAESTUS_ROOT/.ai/$1.md"; }
conventions=$(read_ai conventions)
start=$(read_ai workflows/start-issue)
testing=$(read_ai workflows/test-issue)
ship=$(read_ai workflows/ship)
autopilot=$(read_ai workflows/autopilot)
tester=$(read_ai agents/tester)

begin_test "skipped required criterion is incomplete, not ready"
assert_not_contains "no TODO skip for blocked tasks" "$start" 'skip it with a TODO comment and continue'
assert_contains "required criterion blocks as WIP" "$start" 'If a required criterion depends on it, stop and wind down `[WIP]`'
assert_contains "TODO never satisfies a requirement" "$start" 'A TODO never satisfies a required criterion'
assert_contains "RETHINK subset cannot drop a requirement" "$start" 'if a skipped part carries a required criterion, the outcome is `[WIP]`'
assert_contains "spec: required criteria never degrade" "$conventions" 'A required acceptance criterion or project gate never degrades'

begin_test "optional work may still be deferred"
assert_contains "optional task deferred to follow-up" "$start" 'no acceptance criterion requires it, defer it to a follow-up issue and continue'
assert_contains "criteria marked required unless optional" "$testing" 'required unless the issue marks it optional'

begin_test "persistent review failure ends in a draft, not a PR"
assert_contains "extra fix cycle falls to fundamental path" "$ship" 'if it still fails, take the fundamental path'
assert_contains "draft ends ship without merge" "$ship" 'A draft PR ends `/ship`'
assert_contains "draft never auto-merged" "$ship" 'a draft is never auto-merged'

begin_test "unavailable test infrastructure is BLOCKED, not PASS or FAIL"
assert_contains "tester reports BLOCKED" "$tester" 'BLOCKED when a check could not run'
assert_not_contains "tester never suggests skipping" "$tester" 'skip with note'
assert_contains "ship drafts on blocked gate" "$ship" '`[BLOCKED: <gate> unavailable]`'
assert_contains "start-issue treats BLOCKED as not a pass" "$start" 'A gate that could not run (BLOCKED) or an unverified criterion is not a pass'

begin_test "failed required gates cannot fall through"
assert_not_contains "lint no longer ships with a note" "$ship" 'note remaining issues in PR body'
assert_contains "lint failure drafts" "$ship" 'draft PR `[FAILING: lint]`'
assert_contains "build failure drafts" "$ship" 'draft PR `[FAILING: build]`'
assert_not_contains "no build path without an outcome" "$ship" 'hard stop — do not create a PR with a broken build'
assert_contains "unmet criterion loops back like a test failure" "$start" 'If tests fail or a required criterion is unmet'
assert_contains "evidence gate requires a pass" "$ship" 'actually run and passed in this session'
assert_contains "test-issue outcome needs every gate and criterion" "$testing" 'PASS only if every gate passed and every required criterion is met'
assert_contains "spec: rung 3 is terminal" "$conventions" 'Rung 3 is a terminal outcome, not a completion'

begin_test "autopilot follows the child's actual outcome"
assert_contains "only ready proceeds to ship" "$autopilot" 'Proceed to `/ship` only when `/start-issue` reports `ready`'
assert_contains "incomplete without a draft still winds down" "$autopilot" 'including incomplete work that has no draft PR yet'
assert_contains "draft from ship is not shipped" "$autopilot" 'the issue did not ship: run Phase 4 for cleanup, then wind down'
assert_contains "wind-down opens the missing draft" "$autopilot" 'Incomplete work with no PR yet gets a draft PR carrying its outcome prefix'
assert_not_contains "exhausted retries are not a soft stop" "$autopilot" 'exhausted retries (commit progress, file follow-up issue)'

begin_test "finish never treats a draft as awaiting merge"
finish=$(read_ai workflows/finish)
assert_contains "finish reads isDraft" "$finish" 'baseRefName,isDraft`'
assert_contains "draft logged as not shipped" "$finish" 'draft PR #N — not shipped'
assert_contains "draft gets no docs sync or shipped retrospective" "$finish" 'run `/update-docs`, or file a shipped retrospective. A draft is a wind-down outcome'
assert_contains "branch order is first match" "$finish" 'Branch from that payload (first match wins)'
assert_contains "draft still commits its fixes" "$ship" "skip step 4's docs record but commit task-owned changes"

begin_test "successful recovery still reaches ship"
assert_contains "start-issue reports ready to ship" "$start" 'Only `ready` goes to `/ship`'
assert_contains "gate retries remain" "$ship" 'Fix and re-run (max 2 cycles)'

print_summary
