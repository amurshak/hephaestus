#!/usr/bin/env bash
# test_opencode_adapters.sh — Verify OpenCode adapters stay in sync with canonical sources.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

begin_test "OpenCode adapters match workflows and Claude agents"

if output=$(bash "$HEPHAESTUS_ROOT/scripts/sync-opencode-adapters.sh" --check 2>&1); then
  pass "sync-opencode-adapters.sh --check exits 0"
else
  fail "sync-opencode-adapters.sh --check exits non-zero" "$output"
fi

begin_test "OpenCode adapter check detects command drift"

FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/heph-opencode-XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

cp -R "$HEPHAESTUS_ROOT/.ai" "$FIXTURE/.ai"
cp -R "$HEPHAESTUS_ROOT/.claude" "$FIXTURE/.claude"
cp -R "$HEPHAESTUS_ROOT/.opencode" "$FIXTURE/.opencode"
mkdir -p "$FIXTURE/scripts"
cp "$HEPHAESTUS_ROOT/scripts/sync-opencode-adapters.sh" "$FIXTURE/scripts/sync-opencode-adapters.sh"

sed -i.bak 's/Run the full autonomous pipeline/Run the drifted autonomous pipeline/' \
  "$FIXTURE/.opencode/commands/autopilot.md"
rm -f "$FIXTURE/.opencode/commands/autopilot.md.bak"

if drift_output=$(bash "$FIXTURE/scripts/sync-opencode-adapters.sh" --check 2>&1); then
  fail "OpenCode adapter check should detect command drift" "exited 0, output: $drift_output"
else
  if echo "$drift_output" | grep -q "OpenCode adapter drift for /autopilot"; then
    pass "OpenCode adapter check reports /autopilot drift"
  else
    fail "OpenCode adapter check failed without naming /autopilot" "$drift_output"
  fi
fi

begin_test "OpenCode adapter check detects stale adapters after source deletion"

FIXTURE2=$(mktemp -d "${TMPDIR:-/tmp}/heph-opencode-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2"' EXIT

cp -R "$HEPHAESTUS_ROOT/.ai" "$FIXTURE2/.ai"
cp -R "$HEPHAESTUS_ROOT/.claude" "$FIXTURE2/.claude"
cp -R "$HEPHAESTUS_ROOT/.opencode" "$FIXTURE2/.opencode"
mkdir -p "$FIXTURE2/scripts"
cp "$HEPHAESTUS_ROOT/scripts/sync-opencode-adapters.sh" "$FIXTURE2/scripts/sync-opencode-adapters.sh"

rm "$FIXTURE2/.ai/workflows/research.md"
rm "$FIXTURE2/.claude/agents/tester.md"

if stale_output=$(bash "$FIXTURE2/scripts/sync-opencode-adapters.sh" --check 2>&1); then
  fail "OpenCode check should detect orphaned adapters" "exited 0, output: $stale_output"
else
  assert_contains "check names stale command adapter" "$stale_output" ".opencode/commands/research.md"
  assert_contains "check names stale agent adapter" "$stale_output" ".opencode/agents/tester.md"
fi

sync_output=$(bash "$FIXTURE2/scripts/sync-opencode-adapters.sh" 2>&1)
assert_contains "sync reports stale adapter removal" "$sync_output" "removed stale OpenCode adapter"
assert_file_not_exists "sync removes orphaned command adapter" "$FIXTURE2/.opencode/commands/research.md"
assert_file_not_exists "sync removes orphaned agent adapter" "$FIXTURE2/.opencode/agents/tester.md"

sed -i.bak '/^name:/d' "$FIXTURE2/.claude/agents/coder.md"
bash "$FIXTURE2/scripts/sync-opencode-adapters.sh" >/dev/null 2>&1
assert_exit_code "sync fails on unparseable source" 1 "$?"
assert_file_exists "sync keeps adapter of unparseable source" "$FIXTURE2/.opencode/agents/coder.md"

begin_test "OpenCode agent adapters enforce edit permissions"

coder="$HEPHAESTUS_ROOT/.opencode/agents/coder.md"
reviewer="$HEPHAESTUS_ROOT/.opencode/agents/reviewer.md"
researcher="$HEPHAESTUS_ROOT/.opencode/agents/researcher.md"

assert_contains "coder can edit" "$(cat "$coder")" "  edit: allow"
assert_contains "coder description warns orchestrator about isolation" "$(grep '^description:' "$coder")" "NOTE: OpenCode has no worktree isolation"
assert_contains "coder body warns about missing worktree isolation" "$(cat "$coder")" "> **No worktree isolation.**"
assert_not_contains "reviewer has no isolation warning" "$(cat "$reviewer")" "No worktree isolation"
assert_contains "reviewer cannot edit" "$(cat "$reviewer")" "  edit: deny"
assert_contains "researcher cannot run bash" "$(cat "$researcher")" "  bash: deny"
assert_contains "researcher can websearch" "$(cat "$researcher")" "  websearch: allow"

begin_test "opencode.json loads repo instructions"

opencode_json=$(cat "$HEPHAESTUS_ROOT/opencode.json")
assert_contains "schema declared" "$opencode_json" '"$schema": "https://opencode.ai/config.json"'
assert_contains "CLAUDE.md included" "$opencode_json" '"CLAUDE.md"'
assert_contains "AGENTS.md included" "$opencode_json" '"AGENTS.md"'

print_summary
