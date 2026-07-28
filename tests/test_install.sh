#!/usr/bin/env bash
# test_install.sh — Integration tests for install.sh (user, project, vendor modes)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

trap teardown_fixture EXIT

AGENTS="coder explorer researcher reviewer tester"
COMMANDS="autopilot create-issue critique finish refactor research ship start-issue test-issue update-docs update-hephaestus worktrees"
TOTAL_ADAPTERS=68   # 12 commands + 5 agents, across Claude, OpenCode, Codex, and Hermes

# ── User-level install ───────────────────────────────────────────────────────

begin_test "user install symlinks adapters into the harness config dirs"
setup_fixture
sandbox_home
output=$(bash "$SOURCE_REPO/install.sh" 2>&1)

for agent in $AGENTS; do
  assert_symlink_valid "Claude $agent.md linked"   "$CLAUDE_DIR/agents/$agent.md"
  assert_symlink_valid "OpenCode $agent.md linked" "$OPENCODE_DIR/agents/$agent.md"
  assert_symlink_valid "Codex $agent.toml linked"  "$CODEX_DIR/agents/$agent.toml"
  assert_symlink_valid "Hermes $agent.md linked"   "$HERMES_DIR/agents/$agent.md"
done
for cmd in $COMMANDS; do
  assert_symlink_valid "Claude $cmd.md linked"   "$CLAUDE_DIR/commands/$cmd.md"
  assert_symlink_valid "OpenCode $cmd.md linked" "$OPENCODE_DIR/commands/$cmd.md"
  assert_symlink_valid "Codex skill $cmd linked" "$CODEX_DIR/skills/$cmd"
  assert_symlink_valid "Hermes skill $cmd linked" "$HERMES_DIR/skills/hephaestus/$cmd"
done

# Symlinks are absolute paths into the clone — they must resolve from anywhere,
# including a git worktree, which is what the submodule layout could not do.
target=$(readlink "$CLAUDE_DIR/commands/ship.md")
assert_eq "symlink is absolute into the clone" \
  "$(cd "$SOURCE_REPO" && pwd)/.claude/commands/ship.md" "$target"

# orient is project-owned and must never be installed at user level
assert_file_not_exists "orient.md not installed"       "$CLAUDE_DIR/commands/orient.md"
assert_file_not_exists "OpenCode orient.md not installed" "$OPENCODE_DIR/commands/orient.md"
assert_file_not_exists "Codex orient skill not installed" "$CODEX_DIR/skills/orient"
assert_file_not_exists "Hermes orient skill not installed" "$HERMES_DIR/skills/hephaestus/orient"

assert_file_exists "manifest written"      "$USER_MANIFEST"
assert_eq "manifest records every adapter" "$TOTAL_ADAPTERS" "$(grep -cv '^#' "$USER_MANIFEST")"
assert_contains "reports adapters installed" "$output" "$TOTAL_ADAPTERS hephaestus adapters installed"
assert_contains "reports deps satisfied"     "$output" "all command dependencies satisfied"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "user install is idempotent — re-run updates its own files"
setup_fixture
sandbox_home
bash "$SOURCE_REPO/install.sh" >/dev/null 2>&1
output=$(bash "$SOURCE_REPO/install.sh" 2>&1)
rc=$?

assert_exit_code "exits 0" 0 "$rc"
assert_eq "every adapter refreshed" "$TOTAL_ADAPTERS" "$(echo "$output" | grep -c '\[update\]')"
assert_not_contains "nothing reported stale" "$output" "[stale]"
assert_eq "manifest unchanged in size" "$TOTAL_ADAPTERS" "$(grep -cv '^#' "$USER_MANIFEST")"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "pre-existing files are never overwritten without --force"
setup_fixture
sandbox_home
mkdir -p "$CLAUDE_DIR/commands"
echo "MY OWN SHIP" > "$CLAUDE_DIR/commands/ship.md"
output=$(bash "$SOURCE_REPO/install.sh" 2>&1)

assert_contains "reports the skip"  "$output" "not installed by hephaestus"
assert_eq "content preserved" "MY OWN SHIP" "$(cat "$CLAUDE_DIR/commands/ship.md")"
assert_not_contains "not recorded as ours" "$(grep -v '^#' "$USER_MANIFEST")" "$CLAUDE_DIR/commands/ship.md"

output=$(bash "$SOURCE_REPO/install.sh" --force 2>&1)
assert_contains "force replaces it" "$output" "[replace] ship.md"
assert_symlink_valid "now a managed symlink" "$CLAUDE_DIR/commands/ship.md"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "adapters dropped upstream are reported, then removed by --clean"
setup_fixture
sandbox_home
bash "$SOURCE_REPO/install.sh" >/dev/null 2>&1

# Simulate an adapter that existed in the previous version and is now gone
echo "$CLAUDE_DIR/commands/retired.md" >> "$USER_MANIFEST"
touch "$CLAUDE_DIR/commands/retired.md"

output=$(bash "$SOURCE_REPO/install.sh" 2>&1)
assert_contains  "reports stale"        "$output" "[stale]"
assert_contains  "suggests --clean"     "$output" "--clean"
assert_file_exists "not removed yet"    "$CLAUDE_DIR/commands/retired.md"

# The record must survive a report-only run, or --clean could never find it
output=$(bash "$SOURCE_REPO/install.sh" 2>&1)
assert_contains  "still reported on the next run" "$output" "[stale]"

output=$(bash "$SOURCE_REPO/install.sh" --clean 2>&1)
assert_contains        "reports cleaned"  "$output" "[cleaned]"
assert_file_not_exists "stale file gone"  "$CLAUDE_DIR/commands/retired.md"
assert_eq "manifest back to the shipped set" "$TOTAL_ADAPTERS" "$(grep -cv '^#' "$USER_MANIFEST")"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "user mode rejects a target path"
setup_fixture
sandbox_home
TARGET=$(create_target)
output=$(bash "$SOURCE_REPO/install.sh" "$TARGET" 2>&1)
rc=$?

assert_exit_code "exits 1"            1 "$rc"
assert_contains  "points at --project" "$output" "--project"
assert_contains  "points at --vendor"  "$output" "--vendor"
teardown_fixture

# ── Project scaffold ─────────────────────────────────────────────────────────

begin_test "project mode scaffolds project-owned files only"
setup_fixture
sandbox_home
TARGET=$(create_target)
output=$(bash "$SOURCE_REPO/install.sh" --project "$TARGET" 2>&1)

assert_file_exists "orient.md scaffolded"          "$TARGET/.claude/commands/orient.md"
assert_not_symlink "orient.md is a real file"      "$TARGET/.claude/commands/orient.md"
assert_file_exists "OpenCode orient.md scaffolded" "$TARGET/.opencode/commands/orient.md"
assert_file_exists "Codex orient skill scaffolded" "$TARGET/.agents/skills/orient/SKILL.md"
assert_contains    "Codex orient has frontmatter"  "$(cat "$TARGET/.agents/skills/orient/SKILL.md")" "name: orient"
assert_file_exists "Hermes orient skill scaffolded" "$TARGET/.hermes/skills/hephaestus/orient/SKILL.md"
assert_contains    "Hermes orient has category"     "$(cat "$TARGET/.hermes/skills/hephaestus/orient/SKILL.md")" "category: hephaestus"
assert_file_exists "Hermes .gitignore scaffolded"   "$TARGET/.hermes/.gitignore"
assert_file_exists "AGENTS.md scaffolded"          "$TARGET/AGENTS.md"
assert_file_exists "opencode.json scaffolded"      "$TARGET/opencode.json"
assert_contains    "opencode.json loads AGENTS.md" "$(cat "$TARGET/opencode.json")" "AGENTS.md"
assert_contains    "opencode.json loads CLAUDE.md" "$(cat "$TARGET/opencode.json")" "CLAUDE.md"

# The shared set belongs at user level — project mode must not copy it in
assert_file_not_exists "no command adapters copied" "$TARGET/.claude/commands/ship.md"
assert_file_not_exists "no agent adapters copied"   "$TARGET/.claude/agents/coder.md"
assert_file_not_exists "no manifest written"        "$TARGET/.heph-manifest"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "project scaffolds are never overwritten on re-run"
setup_fixture
sandbox_home
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" --project "$TARGET" >/dev/null 2>&1
echo "MY CUSTOM ORIENT" > "$TARGET/.claude/commands/orient.md"
echo "MY CUSTOM AGENTS" > "$TARGET/AGENTS.md"
output=$(bash "$SOURCE_REPO/install.sh" --project "$TARGET" 2>&1)

assert_eq "orient.md preserved"  "MY CUSTOM ORIENT" "$(cat "$TARGET/.claude/commands/orient.md")"
assert_eq "AGENTS.md preserved"  "MY CUSTOM AGENTS" "$(cat "$TARGET/AGENTS.md")"
assert_contains "reports the skip" "$output" "[skip] orient.md (already exists)"
teardown_fixture

# ── Vendored install ─────────────────────────────────────────────────────────

begin_test "vendor mode copies adapters into the repo and records a manifest"
setup_fixture
sandbox_home
TARGET=$(create_target)
output=$(bash "$SOURCE_REPO/install.sh" --vendor "$TARGET" 2>&1)

for agent in $AGENTS; do
  assert_not_symlink "Claude $agent.md is a real file" "$TARGET/.claude/agents/$agent.md"
  assert_not_symlink "Codex $agent.toml is a real file" "$TARGET/.codex/agents/$agent.toml"
done
for cmd in $COMMANDS; do
  assert_not_symlink "Claude $cmd.md is a real file"   "$TARGET/.claude/commands/$cmd.md"
  assert_not_symlink "OpenCode $cmd.md is a real file" "$TARGET/.opencode/commands/$cmd.md"
  assert_file_exists "Codex skill $cmd copied"         "$TARGET/.agents/skills/$cmd/SKILL.md"
  assert_not_symlink "Codex skill $cmd is a real dir"  "$TARGET/.agents/skills/$cmd"
  assert_file_exists "Hermes skill $cmd copied"        "$TARGET/.hermes/skills/hephaestus/$cmd/SKILL.md"
done

assert_file_exists "manifest written"        "$TARGET/.heph-manifest"
assert_eq "manifest records every adapter"   "$TOTAL_ADAPTERS" "$(grep -cv '^#' "$TARGET/.heph-manifest")"
assert_contains "manifest paths are relative" "$(grep -v '^#' "$TARGET/.heph-manifest")" ".claude/commands/ship.md"
assert_contains "manifest records the version" "$(cat "$TARGET/.heph-manifest")" "# version:"

# Vendoring also scaffolds the project-owned files
assert_file_exists "orient.md scaffolded"  "$TARGET/.claude/commands/orient.md"
assert_file_exists "AGENTS.md scaffolded"  "$TARGET/AGENTS.md"
assert_contains "reports adapters installed" "$output" "$TOTAL_ADAPTERS hephaestus adapters installed"

# The user-level dirs must be untouched by a vendored install
assert_file_not_exists "no user-level install" "$USER_MANIFEST"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "vendor re-run refreshes its copies and cleans dropped adapters"
setup_fixture
sandbox_home
TARGET=$(create_target)
bash "$SOURCE_REPO/install.sh" --vendor "$TARGET" >/dev/null 2>&1
echo "MY CUSTOM ORIENT" > "$TARGET/.claude/commands/orient.md"

output=$(bash "$SOURCE_REPO/install.sh" --vendor "$TARGET" 2>&1)
assert_eq "every copy refreshed" "$TOTAL_ADAPTERS" "$(echo "$output" | grep -c '\[update\]')"
assert_eq "orient.md still preserved" "MY CUSTOM ORIENT" "$(cat "$TARGET/.claude/commands/orient.md")"

echo ".claude/commands/retired.md" >> "$TARGET/.heph-manifest"
touch "$TARGET/.claude/commands/retired.md"
output=$(bash "$SOURCE_REPO/install.sh" --vendor --clean "$TARGET" 2>&1)
assert_contains        "reports cleaned"  "$output" "[cleaned]"
assert_file_not_exists "stale copy gone"  "$TARGET/.claude/commands/retired.md"
teardown_fixture

# ── Migration from a pre-2.2 submodule install ───────────────────────────────

begin_test "--migrate removes the legacy submodule install, then scaffolds"
setup_fixture
sandbox_home
TARGET=$(create_target)
create_legacy_install "$TARGET"

assert_dir_exists "fixture has the submodule" "$TARGET/.hephaestus"
assert_symlink    "fixture has legacy links"  "$TARGET/.claude/commands/ship.md"

output=$(bash "$SOURCE_REPO/install.sh" --migrate "$TARGET" 2>&1)
rc=$?

assert_exit_code "exits 0" 0 "$rc"
assert_file_not_exists ".hephaestus removed"        "$TARGET/.hephaestus"
assert_file_not_exists "submodule git dir removed"  "$TARGET/.git/modules/.hephaestus"
assert_file_not_exists ".gitmodules removed"        "$TARGET/.gitmodules"
for link in .claude/agents/coder.md .claude/commands/ship.md .opencode/agents/coder.md \
            .opencode/commands/ship.md .agents/skills/ship .codex/agents/coder.toml \
            .hermes/skills/hephaestus/ship .hermes/agents/coder.md; do
  assert_file_not_exists "legacy link removed: $link" "$TARGET/$link"
done
assert_contains "reports the removals" "$output" "[removed] .hephaestus submodule"

# Project-owned files survive migration untouched
assert_eq "custom orient.md preserved" "MY CUSTOM ORIENT" "$(cat "$TARGET/.claude/commands/orient.md")"
# …and the rest of the project scaffold is filled in
assert_file_exists "AGENTS.md scaffolded"          "$TARGET/AGENTS.md"
assert_file_exists "Codex orient skill scaffolded" "$TARGET/.agents/skills/orient/SKILL.md"

# Migration is per-repo, so it implies --project: no adapters land in the repo
assert_file_not_exists "no adapters copied in" "$TARGET/.claude/commands/ship.md"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "--migrate is idempotent and audits without touching anything"
setup_fixture
sandbox_home
TARGET=$(create_target)
create_legacy_install "$TARGET"

output=$(bash "$SOURCE_REPO/install.sh" --migrate --audit "$TARGET" 2>&1)
assert_contains  "audit lists the legacy links" "$output" "legacy link"
assert_contains  "audit names the submodule"    "$output" "will be deinitialized and removed"
assert_dir_exists "audit removed nothing"       "$TARGET/.hephaestus"
assert_symlink    "audit kept the links"        "$TARGET/.claude/commands/ship.md"

bash "$SOURCE_REPO/install.sh" --migrate "$TARGET" >/dev/null 2>&1
output=$(bash "$SOURCE_REPO/install.sh" --migrate "$TARGET" 2>&1)
assert_exit_code "second run exits 0" 0 $?
assert_contains  "reports nothing to migrate" "$output" "nothing to migrate"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "--migrate --vendor lands committed copies in the migrated repo"
setup_fixture
sandbox_home
TARGET=$(create_target)
create_legacy_install "$TARGET"

bash "$SOURCE_REPO/install.sh" --migrate --vendor "$TARGET" >/dev/null 2>&1

assert_file_not_exists ".hephaestus removed"   "$TARGET/.hephaestus"
assert_not_symlink "ship.md is now a real file" "$TARGET/.claude/commands/ship.md"
assert_file_exists "manifest written"           "$TARGET/.heph-manifest"
assert_eq "manifest records every adapter" "$TOTAL_ADAPTERS" "$(grep -cv '^#' "$TARGET/.heph-manifest")"
assert_eq "custom orient.md preserved" "MY CUSTOM ORIENT" "$(cat "$TARGET/.claude/commands/orient.md")"
teardown_fixture

# ── Validation and flags ─────────────────────────────────────────────────────

begin_test "audit mode makes no filesystem changes"
setup_fixture
sandbox_home
TARGET=$(create_target)
output=$(bash "$SOURCE_REPO/install.sh" --audit 2>&1)
rc=$?

assert_exit_code       "exits 0"            0 "$rc"
assert_contains        "output says audit"  "$output" "Audit"
assert_contains        "no changes made"    "$output" "No changes were made"
assert_file_not_exists "no ~/.claude dir"   "$CLAUDE_DIR"
assert_file_not_exists "no manifest"        "$USER_MANIFEST"

bash "$SOURCE_REPO/install.sh" --vendor --audit "$TARGET" >/dev/null 2>&1
assert_file_not_exists "vendor audit copies nothing" "$TARGET/.claude/commands/ship.md"
assert_file_not_exists "vendor audit writes no manifest" "$TARGET/.heph-manifest"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "CLAUDE.md development commands validation"
setup_fixture
sandbox_home
TARGET=$(create_target)

output=$(bash "$SOURCE_REPO/install.sh" --project "$TARGET" 2>&1)
assert_contains "warns when CLAUDE.md is absent" "$output" "No CLAUDE.md found"

echo "# My Project" > "$TARGET/CLAUDE.md"
output=$(bash "$SOURCE_REPO/install.sh" --project "$TARGET" 2>&1)
assert_contains "warns when dev commands are missing" "$output" "[warn]"
assert_contains "names what is missing"               "$output" "development commands"

cat > "$TARGET/CLAUDE.md" <<'EOF'
# My Project

## Development Commands

```bash
npm test
npm run lint
```
EOF
output=$(bash "$SOURCE_REPO/install.sh" --project "$TARGET" 2>&1)
assert_contains "passes when present" "$output" "CLAUDE.md has development commands"
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

begin_test "invalid invocations exit 1"
setup_fixture
sandbox_home
TARGET=$(create_target)

bash "$SOURCE_REPO/install.sh" --audit --force >/dev/null 2>&1
assert_exit_code "--audit + --force" 1 $?

bash "$SOURCE_REPO/install.sh" --audit --clean >/dev/null 2>&1
assert_exit_code "--audit + --clean" 1 $?

bash "$SOURCE_REPO/install.sh" --invalid >/dev/null 2>&1
assert_exit_code "unknown flag" 1 $?

bash "$SOURCE_REPO/install.sh" --project "/tmp/nonexistent-heph-test-path" >/dev/null 2>&1
assert_exit_code "non-existent target" 1 $?

plain_dir="$FIXTURE_DIR/not-a-repo"
mkdir -p "$plain_dir"
bash "$SOURCE_REPO/install.sh" --project "$plain_dir" >/dev/null 2>&1
assert_exit_code "non-git target" 1 $?
teardown_fixture

# ─────────────────────────────────────────────────────────────────────────────

print_summary
