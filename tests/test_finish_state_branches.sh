#!/usr/bin/env bash
# test_finish_state_branches.sh — Verify /finish partial-success state handling.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

finish_decision() {
  local state="$1" merged_at="$2" merge_state="$3" auto_merge="$4"

  if [ "$state" = "MERGED" ] && [ "$merged_at" != "null" ]; then
    echo "proceed"
  elif [ "$state" = "OPEN" ] && [ "$merge_state" = "CLEAN" ] && [ "$auto_merge" != "null" ]; then
    echo "auto-merge pending"
  elif [ "$state" = "OPEN" ] && [ "$auto_merge" = "null" ]; then
    echo "manual merge needed"
  elif [ "$state" = "CLOSED" ] && [ "$merged_at" = "null" ]; then
    echo "abort closed without merge"
  else
    echo "manual merge needed"
  fi
}

finish_md=$(cat "$HEPHAESTUS_ROOT/.claude/commands/finish.md")

begin_test "/finish branches deterministic PR states"
assert_eq "merged PR proceeds" \
  "proceed" \
  "$(finish_decision "MERGED" "2026-04-28T00:00:00Z" "UNKNOWN" "null")"
assert_eq "open clean PR with auto-merge waits" \
  "auto-merge pending" \
  "$(finish_decision "OPEN" "null" "CLEAN" "requested")"
assert_eq "open PR without auto-merge needs manual merge" \
  "manual merge needed" \
  "$(finish_decision "OPEN" "null" "BLOCKED" "null")"
assert_eq "closed unmerged PR aborts finish" \
  "abort closed without merge" \
  "$(finish_decision "CLOSED" "null" "UNKNOWN" "null")"

begin_test "finish.md loads the complete PR state payload"
assert_contains "reads state" "$finish_md" "state,mergedAt,mergeStateStatus,autoMergeRequest"
assert_contains "reads branch identity" "$finish_md" "headRefName,headRefOid,baseRefOid"
assert_contains "reads closing issue references" "$finish_md" "closingIssuesReferences"

begin_test "finish.md documents partial cleanup boundaries"
assert_contains "auto-merge pending log" "$finish_md" "auto-merge pending for PR #N"
assert_contains "manual merge needed log" "$finish_md" "manual merge needed for PR #N"
assert_contains "closed-unmerged abort log" "$finish_md" "PR #N closed without merge"
assert_contains "pending states do not close issue" "$finish_md" "do not close the issue"
assert_contains "pending states preserve PR branch" "$finish_md" "do not delete or sweep this PR's branch"

begin_test "finish.md documents idempotent issue close"
assert_contains "uses PR closing issue over argument" "$finish_md" "using PR closing issue #M instead of requested #N"
assert_contains "checks issue state before closing" "$finish_md" "gh issue view <resolved-issue>"
assert_contains "already-closed issue is clean no-op" "$finish_md" "issue #N already closed by PR #M"

begin_test "finish.md handles branch head changes"
assert_contains "re-reads headRefName before deletion" "$finish_md" "re-read the same PR field immediately before deletion"
assert_contains "logs changed head branch" "$finish_md" "head branch changed during finish"
assert_contains "open PR excluded from sweep" "$finish_md" 'exclude the current PR'\''s `headRefName` from `stale`'

print_summary
