#!/usr/bin/env bash
# test_uninstall.sh — Integration tests for uninstall.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

trap teardown_fixture EXIT

# ─────────────────────────────────────────────────────────────────────────────

begin_test "clean uninstall removes symlinks and submodule"
setup_fixture
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1

output=$(bash "$SOURCE_REPO/uninstall.sh" "$TARGET" 2>&1)
rc=$?

assert_exit_code "exits 0" 0 "$rc"

# Symlinks should be removed
assert_file_not_exists "coder.md removed"     "$TARGET/.claude/agents/coder.md"
assert_file_not_exists "reviewer.md removed"  "$TARGET/.claude/agents/reviewer.md"
assert_file_not_exists "autopilot.md removed" "$TARGET/.claude/commands/autopilot.md"
assert_file_not_exists "ship.md removed"      "$TARGET/.claude/commands/ship.md"
assert_file_not_exists "OpenCode coder.md removed"     "$TARGET/.opencode/agents/coder.md"
assert_file_not_exists "OpenCode autopilot.md removed" "$TARGET/.opencode/commands/autopilot.md"

# .hephaestus submodule should be removed
assert_file_not_exists ".hephaestus removed" "$TARGET/.hephaestus"

assert_contains "output mentions removed" "$output" "[removed]"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "uninstall preserves project-specific files"
setup_fixture
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1

# orient.md was scaffolded — it should survive uninstall
echo "my orient" > "$TARGET/.claude/commands/orient.md"
echo "my opencode orient" > "$TARGET/.opencode/commands/orient.md"
# Create a project-specific CLAUDE.md
echo "# Project" > "$TARGET/CLAUDE.md"

bash "$SOURCE_REPO/uninstall.sh" "$TARGET" >/dev/null 2>&1

assert_file_exists "orient.md preserved" "$TARGET/.claude/commands/orient.md"
content=$(cat "$TARGET/.claude/commands/orient.md")
assert_eq "orient.md content intact" "my orient" "$content"
assert_file_exists "OpenCode orient.md preserved" "$TARGET/.opencode/commands/orient.md"
opencode_content=$(cat "$TARGET/.opencode/commands/orient.md")
assert_eq "OpenCode orient.md content intact" "my opencode orient" "$opencode_content"
assert_file_exists "CLAUDE.md preserved" "$TARGET/CLAUDE.md"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "idempotent uninstall (second run succeeds)"
setup_fixture
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1
bash "$SOURCE_REPO/uninstall.sh" "$TARGET" >/dev/null 2>&1

# Second uninstall — should succeed with no errors
output=$(bash "$SOURCE_REPO/uninstall.sh" "$TARGET" 2>&1)
rc=$?

assert_exit_code "exits 0"                      0 "$rc"
assert_contains  "no symlinks found"             "$output" "no hephaestus symlinks found"
assert_contains  "no submodule found"            "$output" "no .hephaestus submodule found"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "uninstall only removes hephaestus symlinks"
setup_fixture
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1

# Create a non-hephaestus symlink in agents dir
echo "local agent" > "$TARGET/.claude/agents/local-agent.md"

bash "$SOURCE_REPO/uninstall.sh" "$TARGET" >/dev/null 2>&1

assert_file_exists "local agent preserved" "$TARGET/.claude/agents/local-agent.md"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "non-existent target exits 1"
setup_fixture
bash "$SOURCE_REPO/uninstall.sh" "/tmp/nonexistent-heph-test-path" >/dev/null 2>&1
rc=$?

assert_exit_code "exits 1" 1 "$rc"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "non-git target exits 1"
setup_fixture
plain_dir="$FIXTURE_DIR/not-a-repo"
mkdir -p "$plain_dir"
bash "$SOURCE_REPO/uninstall.sh" "$plain_dir" >/dev/null 2>&1
rc=$?

assert_exit_code "exits 1" 1 "$rc"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "full lifecycle: install → uninstall → reinstall"
setup_fixture
TARGET=$(create_target)

# Install
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1
assert_symlink "after install: coder.md linked" "$TARGET/.claude/agents/coder.md"
assert_symlink "after install: OpenCode coder.md linked" "$TARGET/.opencode/agents/coder.md"

# Uninstall
bash "$SOURCE_REPO/uninstall.sh" "$TARGET" >/dev/null 2>&1
assert_file_not_exists "after uninstall: coder.md gone" "$TARGET/.claude/agents/coder.md"
assert_file_not_exists "after uninstall: OpenCode coder.md gone" "$TARGET/.opencode/agents/coder.md"

# Reinstall
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1
assert_symlink       "after reinstall: coder.md linked again" "$TARGET/.claude/agents/coder.md"
assert_symlink_valid "after reinstall: coder.md resolves"     "$TARGET/.claude/agents/coder.md"
assert_symlink       "after reinstall: OpenCode coder.md linked again" "$TARGET/.opencode/agents/coder.md"
assert_symlink_valid "after reinstall: OpenCode coder.md resolves"     "$TARGET/.opencode/agents/coder.md"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

print_summary
