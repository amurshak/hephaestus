#!/usr/bin/env bash
# test_uninstall.sh — Integration tests for uninstall.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

trap teardown_fixture EXIT

AGENTS="coder explorer researcher reviewer tester"

# ─────────────────────────────────────────────────────────────────────────────

begin_test "user uninstall removes every installed adapter"
setup_fixture
sandbox_home
bash "$SOURCE_REPO/install.sh" >/dev/null 2>&1

output=$(bash "$SOURCE_REPO/uninstall.sh" 2>&1)
rc=$?

assert_exit_code "exits 0" 0 "$rc"
for agent in $AGENTS; do
  assert_file_not_exists "Claude $agent.md removed"   "$CLAUDE_DIR/agents/$agent.md"
  assert_file_not_exists "OpenCode $agent.md removed" "$OPENCODE_DIR/agents/$agent.md"
  assert_file_not_exists "Codex $agent.toml removed"  "$CODEX_DIR/agents/$agent.toml"
  assert_file_not_exists "Hermes $agent.md removed"   "$HERMES_DIR/agents/$agent.md"
  assert_file_not_exists "Cursor $agent.md removed"   "$CURSOR_DIR/agents/$agent.md"
done
assert_file_not_exists "Claude ship.md removed"   "$CLAUDE_DIR/commands/ship.md"
assert_file_not_exists "OpenCode ship.md removed" "$OPENCODE_DIR/commands/ship.md"
assert_file_not_exists "Codex ship skill removed" "$CODEX_DIR/skills/ship"
assert_file_not_exists "Hermes ship skill removed" "$HERMES_DIR/skills/hephaestus/ship"
assert_file_not_exists "Cursor ship.md removed"   "$CURSOR_DIR/commands/ship.md"
assert_file_not_exists "Cursor rule removed"      "$CURSOR_DIR/rules/hephaestus.mdc"
assert_file_not_exists "manifest removed"         "$USER_MANIFEST"
assert_contains        "reports what it removed"  "$output" "Removed 86 file(s)"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "user uninstall leaves files hephaestus never installed"
setup_fixture
sandbox_home
bash "$SOURCE_REPO/install.sh" >/dev/null 2>&1
echo "my own command" > "$CLAUDE_DIR/commands/my-command.md"
echo "my own agent"   > "$CLAUDE_DIR/agents/my-agent.md"

bash "$SOURCE_REPO/uninstall.sh" >/dev/null 2>&1

assert_file_exists "personal command preserved" "$CLAUDE_DIR/commands/my-command.md"
assert_file_exists "personal agent preserved"   "$CLAUDE_DIR/agents/my-agent.md"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "vendor uninstall removes copies but keeps project-owned files"
setup_fixture
sandbox_home
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" --vendor "$TARGET" >/dev/null 2>&1
echo "local agent" > "$TARGET/.claude/agents/local-agent.md"
# .cursor/rules is a namespace we share with the project.
echo "team rule" > "$TARGET/.cursor/rules/team.mdc"

output=$(bash "$SOURCE_REPO/uninstall.sh" --vendor "$TARGET" 2>&1)
rc=$?

assert_exit_code "exits 0" 0 "$rc"
assert_file_not_exists "ship.md copy removed"      "$TARGET/.claude/commands/ship.md"
assert_file_not_exists "coder.md copy removed"     "$TARGET/.claude/agents/coder.md"
assert_file_not_exists "Codex ship skill removed"  "$TARGET/.agents/skills/ship"
assert_file_not_exists "Codex coder.toml removed"  "$TARGET/.codex/agents/coder.toml"
assert_file_not_exists "Hermes ship skill removed" "$TARGET/.hermes/skills/hephaestus/ship"
assert_file_not_exists "Cursor ship.md removed"   "$TARGET/.cursor/commands/ship.md"
assert_file_not_exists "Cursor rule removed"      "$TARGET/.cursor/rules/hephaestus.mdc"
assert_file_not_exists "manifest removed"          "$TARGET/.heph-manifest"

assert_file_exists "orient.md preserved"           "$TARGET/.claude/commands/orient.md"
assert_file_exists "Codex orient skill preserved"  "$TARGET/.agents/skills/orient/SKILL.md"
assert_file_exists "Hermes orient skill preserved" "$TARGET/.hermes/skills/hephaestus/orient/SKILL.md"
assert_file_exists "Hermes .gitignore preserved"   "$TARGET/.hermes/.gitignore"
assert_file_exists "Cursor orient.md preserved"   "$TARGET/.cursor/commands/orient.md"
# .cursor/rules is shared with the project's own rules — never ours to remove.
assert_file_exists "project's own Cursor rule preserved" "$TARGET/.cursor/rules/team.mdc"
assert_file_exists "AGENTS.md preserved"           "$TARGET/AGENTS.md"
assert_file_exists "opencode.json preserved"       "$TARGET/opencode.json"
assert_file_exists "local agent preserved"         "$TARGET/.claude/agents/local-agent.md"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "uninstall with nothing installed is a no-op"
setup_fixture
sandbox_home
TARGET=$(create_target)

output=$(bash "$SOURCE_REPO/uninstall.sh" 2>&1)
assert_exit_code "user mode exits 0"      0 $?
assert_contains  "says nothing is installed" "$output" "No hephaestus install found"

output=$(bash "$SOURCE_REPO/uninstall.sh" --vendor "$TARGET" 2>&1)
assert_exit_code "vendor mode exits 0"    0 $?
assert_contains  "says nothing is vendored" "$output" "No hephaestus install found"

bash "$SOURCE_REPO/uninstall.sh" --invalid >/dev/null 2>&1
assert_exit_code "unknown flag exits 1" 1 $?
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "full lifecycle: install → uninstall → reinstall"
setup_fixture
sandbox_home
bash "$SOURCE_REPO/install.sh" >/dev/null 2>&1
assert_symlink_valid "after install: coder.md linked" "$CLAUDE_DIR/agents/coder.md"

bash "$SOURCE_REPO/uninstall.sh" >/dev/null 2>&1
assert_file_not_exists "after uninstall: coder.md gone" "$CLAUDE_DIR/agents/coder.md"

output=$(bash "$SOURCE_REPO/install.sh" 2>&1)
assert_symlink_valid "after reinstall: coder.md linked again" "$CLAUDE_DIR/agents/coder.md"
assert_symlink_valid "after reinstall: Codex ship skill linked" "$CODEX_DIR/skills/ship"
assert_symlink_valid "after reinstall: Hermes ship skill linked" "$HERMES_DIR/skills/hephaestus/ship"
assert_contains "reinstall reports a fresh install" "$output" "[install] coder.md"
assert_file_exists "manifest rebuilt" "$USER_MANIFEST"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

print_summary
