#!/usr/bin/env bash
# test_update.sh — Integration tests for update.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

trap teardown_fixture EXIT

# Publish a new hephaestus version to the fixture remote, so the clone under
# test has something to pull. Runs against a second clone to leave SOURCE_REPO
# behind the remote.
publish_upstream_change() {
  local work="$FIXTURE_DIR/upstream"
  git clone --quiet "$REMOTE_REPO" "$work" 2>/dev/null
  echo "9.9.9" > "$work/VERSION"
  git -C "$work" -c user.email="test@test.com" -c user.name="Test" add VERSION
  git -C "$work" -c user.email="test@test.com" -c user.name="Test" commit -m "bump version" --quiet
  git -C "$work" push --quiet 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────

begin_test "update pulls upstream and refreshes the user-level install"
setup_fixture
sandbox_home
bash "$SOURCE_REPO/install.sh" >/dev/null 2>&1
publish_upstream_change

output=$(bash "$SOURCE_REPO/update.sh" 2>&1)
rc=$?

assert_exit_code "exits 0"                0 "$rc"
assert_contains  "names the clone"        "$output" "Updating hephaestus at"
assert_contains  "shows version transition" "$output" "9.9.9"
assert_contains  "lists the new commits"  "$output" "bump version"
assert_eq        "clone pulled"           "9.9.9" "$(cat "$SOURCE_REPO/VERSION")"
assert_symlink_valid "adapters still linked" "$CLAUDE_DIR/commands/ship.md"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "update reports already up to date"
setup_fixture
sandbox_home
bash "$SOURCE_REPO/install.sh" >/dev/null 2>&1

output=$(bash "$SOURCE_REPO/update.sh" 2>&1)
rc=$?

assert_exit_code "exits 0"            0 "$rc"
assert_contains  "already up to date" "$output" "Already up to date"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "update removes adapters dropped upstream"
setup_fixture
sandbox_home
bash "$SOURCE_REPO/install.sh" >/dev/null 2>&1

echo "$CLAUDE_DIR/commands/retired.md" >> "$USER_MANIFEST"
touch "$CLAUDE_DIR/commands/retired.md"

output=$(bash "$SOURCE_REPO/update.sh" 2>&1)

assert_file_not_exists "stale adapter cleaned by update" "$CLAUDE_DIR/commands/retired.md"
assert_contains        "reports the cleanup"             "$output" "[cleaned]"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "update --vendor refreshes a project's committed copies"
setup_fixture
sandbox_home
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" --vendor "$TARGET" >/dev/null 2>&1
publish_upstream_change

output=$(bash "$SOURCE_REPO/update.sh" --vendor "$TARGET" 2>&1)
rc=$?

assert_exit_code "exits 0"                  0 "$rc"
assert_contains  "shows version transition" "$output" "9.9.9"
assert_contains  "manifest records the new version" "$(cat "$TARGET/.heph-manifest")" "# version: 9.9.9"
assert_contains  "prints a commit hint"     "$output" "git -C $TARGET add .heph-manifest"
assert_not_symlink "copies are still real files" "$TARGET/.claude/commands/ship.md"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "update --vendor without a path exits 1"
setup_fixture
sandbox_home
bash "$SOURCE_REPO/update.sh" --vendor >/dev/null 2>&1
assert_exit_code "exits 1" 1 $?

bash "$SOURCE_REPO/update.sh" --invalid >/dev/null 2>&1
assert_exit_code "unknown flag exits 1" 1 $?
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

print_summary
