#!/usr/bin/env bash
# test_install.sh — Integration tests for install.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Ensure cleanup on exit
trap teardown_fixture EXIT

# ─────────────────────────────────────────────────────────────────────────────

begin_test "fresh install into a clean repo"
setup_fixture
TARGET=$(create_target)
output=$(bash "$SOURCE_REPO/install.sh" "$TARGET" 2>&1)

assert_dir_exists   ".hephaestus submodule created"  "$TARGET/.hephaestus"
assert_dir_exists   ".claude/agents/ created"        "$TARGET/.claude/agents"
assert_dir_exists   ".claude/commands/ created"      "$TARGET/.claude/commands"
assert_dir_exists   ".opencode/agents/ created"       "$TARGET/.opencode/agents"
assert_dir_exists   ".opencode/commands/ created"    "$TARGET/.opencode/commands"

# All 5 agents should be symlinked
for agent in coder explorer researcher reviewer tester; do
  assert_symlink       "$agent.md is a symlink"                    "$TARGET/.claude/agents/$agent.md"
  assert_symlink_valid "$agent.md symlink resolves"                "$TARGET/.claude/agents/$agent.md"
  assert_symlink_target_contains "$agent.md points to .hephaestus" "$TARGET/.claude/agents/$agent.md" ".hephaestus/"
done

# Commands (except orient.md) should be symlinked
for cmd in autopilot create-issue critique finish refactor research ship start-issue test-issue update-docs update-hephaestus; do
  assert_symlink       "$cmd.md is a symlink"                    "$TARGET/.claude/commands/$cmd.md"
  assert_symlink_valid "$cmd.md symlink resolves"                "$TARGET/.claude/commands/$cmd.md"
  assert_symlink_target_contains "$cmd.md points to .hephaestus" "$TARGET/.claude/commands/$cmd.md" ".hephaestus/"
done

# OpenCode adapters should also be symlinked
for agent in coder explorer researcher reviewer tester; do
  assert_symlink       "OpenCode $agent.md is a symlink"                    "$TARGET/.opencode/agents/$agent.md"
  assert_symlink_valid "OpenCode $agent.md symlink resolves"                "$TARGET/.opencode/agents/$agent.md"
  assert_symlink_target_contains "OpenCode $agent.md points to .hephaestus" "$TARGET/.opencode/agents/$agent.md" ".hephaestus/"
done
for cmd in autopilot create-issue critique finish refactor research ship start-issue test-issue update-docs update-hephaestus; do
  assert_symlink       "OpenCode $cmd.md is a symlink"                    "$TARGET/.opencode/commands/$cmd.md"
  assert_symlink_valid "OpenCode $cmd.md symlink resolves"                "$TARGET/.opencode/commands/$cmd.md"
  assert_symlink_target_contains "OpenCode $cmd.md points to .hephaestus" "$TARGET/.opencode/commands/$cmd.md" ".hephaestus/"
done

# orient.md should be scaffolded as a regular file, not a symlink
assert_file_exists  "orient.md exists"         "$TARGET/.claude/commands/orient.md"
assert_not_symlink  "orient.md is not symlink" "$TARGET/.claude/commands/orient.md"
assert_file_exists  "OpenCode orient.md exists"         "$TARGET/.opencode/commands/orient.md"
assert_not_symlink  "OpenCode orient.md is not symlink" "$TARGET/.opencode/commands/orient.md"

# AGENTS.md should be scaffolded as a regular file, not a symlink
assert_file_exists  "AGENTS.md exists"         "$TARGET/AGENTS.md"
assert_not_symlink  "AGENTS.md is not symlink" "$TARGET/AGENTS.md"

assert_contains "output mentions health check" "$output" "Health check:"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "idempotent re-install (second run skips everything)"
setup_fixture
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1
output=$(bash "$SOURCE_REPO/install.sh" "$TARGET" 2>&1)

assert_contains "submodule skipped"      "$output" "[skip] .hephaestus submodule already registered"
assert_contains "agents skipped"         "$output" "[skip]"
assert_contains "orient.md skipped"      "$output" "[skip] orient.md (already exists)"
assert_contains "AGENTS.md skipped"      "$output" "[skip] AGENTS.md (already exists)"
assert_exit_code "exits 0" 0 $?
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "audit mode makes no filesystem changes"
setup_fixture
TARGET=$(create_target)
output=$(bash "$SOURCE_REPO/install.sh" --audit "$TARGET" 2>&1)
rc=$?

assert_exit_code         "exits 0"                    0 "$rc"
assert_contains          "output says audit"          "$output" "Audit"
assert_contains          "no changes made"            "$output" "No changes were made"
assert_file_not_exists   "no .hephaestus created"     "$TARGET/.hephaestus"
assert_file_not_exists   "no .claude dir created"     "$TARGET/.claude"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "force mode replaces existing files"
setup_fixture
TARGET=$(create_target)
mkdir -p "$TARGET/.claude/agents"
echo "custom content" > "$TARGET/.claude/agents/coder.md"

bash "$SOURCE_REPO/install.sh" --force "$TARGET" >/dev/null 2>&1

assert_symlink "coder.md replaced with symlink" "$TARGET/.claude/agents/coder.md"
assert_symlink_target_contains "points to .hephaestus" "$TARGET/.claude/agents/coder.md" ".hephaestus/"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "clean mode removes stale symlinks"
setup_fixture
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1

# Create a stale symlink (points to a .hephaestus/ path that doesn't exist)
ln -s "../../.hephaestus/.claude/agents/deleted-agent.md" "$TARGET/.claude/agents/deleted-agent.md"

output=$(bash "$SOURCE_REPO/install.sh" --clean "$TARGET" 2>&1)

assert_file_not_exists "stale symlink removed" "$TARGET/.claude/agents/deleted-agent.md"
assert_contains "output mentions cleaned" "$output" "[cleaned]"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "stale symlink detected without --clean"
setup_fixture
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1

ln -s "../../.hephaestus/.claude/agents/deleted-agent.md" "$TARGET/.claude/agents/deleted-agent.md"

output=$(bash "$SOURCE_REPO/install.sh" "$TARGET" 2>&1)

assert_symlink "stale symlink still present" "$TARGET/.claude/agents/deleted-agent.md"
assert_contains "output warns about stale" "$output" "[stale]"
assert_contains "suggests --clean" "$output" "--clean"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "flag conflict: --audit + --force"
setup_fixture
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" --audit --force "$TARGET" >/dev/null 2>&1
rc=$?

assert_exit_code "exits 1" 1 "$rc"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "flag conflict: --audit + --clean"
setup_fixture
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" --audit --clean "$TARGET" >/dev/null 2>&1
rc=$?

assert_exit_code "exits 1" 1 "$rc"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "unknown flag exits 1"
setup_fixture
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" --invalid "$TARGET" >/dev/null 2>&1
rc=$?

assert_exit_code "exits 1" 1 "$rc"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "non-existent target exits 1"
setup_fixture
bash "$SOURCE_REPO/install.sh" "/tmp/nonexistent-heph-test-path" >/dev/null 2>&1
rc=$?

assert_exit_code "exits 1" 1 "$rc"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "non-git target exits 1"
setup_fixture
plain_dir="$FIXTURE_DIR/not-a-repo"
mkdir -p "$plain_dir"
bash "$SOURCE_REPO/install.sh" "$plain_dir" >/dev/null 2>&1
rc=$?

assert_exit_code "exits 1" 1 "$rc"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "orient.md not overwritten on re-install"
setup_fixture
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1

# Write custom content to orient.md
echo "MY CUSTOM ORIENT" > "$TARGET/.claude/commands/orient.md"
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1

content=$(cat "$TARGET/.claude/commands/orient.md")
assert_eq "orient.md preserved" "MY CUSTOM ORIENT" "$content"

# AGENTS.md must also survive re-install untouched
echo "MY CUSTOM AGENTS" > "$TARGET/AGENTS.md"
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1
agents_content=$(cat "$TARGET/AGENTS.md")
assert_eq "AGENTS.md preserved" "MY CUSTOM AGENTS" "$agents_content"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "CLAUDE.md validation warns when missing dev commands"
setup_fixture
TARGET=$(create_target)
# Create CLAUDE.md without dev commands section
echo "# My Project" > "$TARGET/CLAUDE.md"

output=$(bash "$SOURCE_REPO/install.sh" "$TARGET" 2>&1)

assert_contains "warns about missing dev commands" "$output" "[warn]"
assert_contains "mentions development commands"    "$output" "development commands"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "CLAUDE.md validation passes with dev commands"
setup_fixture
TARGET=$(create_target)
cat > "$TARGET/CLAUDE.md" <<'EOF'
# My Project

## Development Commands

```bash
npm test
npm run lint
```
EOF

output=$(bash "$SOURCE_REPO/install.sh" "$TARGET" 2>&1)

assert_contains "dev commands found" "$output" "CLAUDE.md has development commands"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "no CLAUDE.md warns"
setup_fixture
TARGET=$(create_target)
output=$(bash "$SOURCE_REPO/install.sh" "$TARGET" 2>&1)

assert_contains "warns about missing CLAUDE.md" "$output" "No CLAUDE.md found"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "duplicate submodule at different path exits 1"
setup_fixture
TARGET=$(create_target)

# Manually register hephaestus at a different path in .gitmodules
remote_url=$(git -C "$SOURCE_REPO" remote get-url origin)
cat > "$TARGET/.gitmodules" <<EOF
[submodule "other-path"]
	path = other-path
	url = $remote_url
EOF
git -C "$TARGET" -c user.email="test@test.com" -c user.name="Test" \
  add .gitmodules 2>/dev/null
git -C "$TARGET" -c user.email="test@test.com" -c user.name="Test" \
  commit -m "add gitmodules" --quiet 2>/dev/null

bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1
rc=$?

assert_exit_code "exits 1 for duplicate" 1 "$rc"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "health check reports valid symlinks"
setup_fixture
TARGET=$(create_target)
output=$(bash "$SOURCE_REPO/install.sh" "$TARGET" 2>&1)

assert_contains "reports valid symlinks"          "$output" "symlinks valid"
assert_contains "reports orient.md present"       "$output" "orient.md present"
assert_contains "reports deps satisfied"          "$output" "all command dependencies satisfied"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "symlink relative paths are correct"
setup_fixture
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" "$TARGET" >/dev/null 2>&1

# Verify the exact relative path format
agent_target=$(readlink "$TARGET/.claude/agents/coder.md")
assert_eq "agent symlink path" "../../.hephaestus/.claude/agents/coder.md" "$agent_target"

cmd_target=$(readlink "$TARGET/.claude/commands/autopilot.md")
assert_eq "command symlink path" "../../.hephaestus/.claude/commands/autopilot.md" "$cmd_target"

opencode_agent_target=$(readlink "$TARGET/.opencode/agents/coder.md")
assert_eq "OpenCode agent symlink path" "../../.hephaestus/.opencode/agents/coder.md" "$opencode_agent_target"

opencode_cmd_target=$(readlink "$TARGET/.opencode/commands/autopilot.md")
assert_eq "OpenCode command symlink path" "../../.hephaestus/.opencode/commands/autopilot.md" "$opencode_cmd_target"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

print_summary
