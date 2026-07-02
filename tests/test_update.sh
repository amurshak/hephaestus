#!/usr/bin/env bash
# test_update.sh — Integration tests for update.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

trap teardown_fixture EXIT

# ─────────────────────────────────────────────────────────────────────────────

begin_test "update pulls new changes from remote"
setup_fixture
TARGET=$(create_target)

# Install into target (submodule points to our local bare remote)
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1

# Make a new commit in the source and push to bare remote
echo "new-content" > "$SOURCE_REPO/VERSION"
git -C "$SOURCE_REPO" -c user.email="test@test.com" -c user.name="Test" \
  add VERSION
git -C "$SOURCE_REPO" -c user.email="test@test.com" -c user.name="Test" \
  commit -m "bump version" --quiet
git -C "$SOURCE_REPO" push --quiet 2>/dev/null

# Run update from the target project root
output=$(cd "$TARGET" && bash .hephaestus/update.sh 2>&1)
rc=$?

assert_exit_code "exits 0"          0 "$rc"
assert_contains  "shows version"    "$output" "Updating .hephaestus"

# Verify the new content is in the submodule
new_version=$(cat "$TARGET/.hephaestus/VERSION")
assert_eq "VERSION updated" "new-content" "$new_version"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "update reports already up to date"
setup_fixture
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1

output=$(cd "$TARGET" && bash .hephaestus/update.sh 2>&1)
rc=$?

assert_exit_code "exits 0"               0 "$rc"
assert_contains  "already up to date"    "$output" "Already up to date"
assert_contains  "commit hint includes OpenCode" "$output" "git add .hephaestus .claude .opencode"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "update fails without submodule"
setup_fixture
TARGET=$(create_target)

# Don't install — just run update directly (subshell to avoid cwd pollution)
(cd "$TARGET" && bash "$SOURCE_REPO/update.sh" >/dev/null 2>&1)
rc=$?

assert_exit_code "exits 1" 1 "$rc"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "update repairs stale symlinks via --clean"
setup_fixture
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1

# Create a stale symlink
ln -s "../../.hephaestus/.claude/agents/gone.md" "$TARGET/.claude/agents/gone.md"
ln -s "../../.hephaestus/.opencode/agent/gone.md" "$TARGET/.opencode/agent/gone.md"

output=$(cd "$TARGET" && bash .hephaestus/update.sh 2>&1)

assert_file_not_exists "stale symlink cleaned by update" "$TARGET/.claude/agents/gone.md"
assert_file_not_exists "stale OpenCode symlink cleaned by update" "$TARGET/.opencode/agent/gone.md"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

print_summary
