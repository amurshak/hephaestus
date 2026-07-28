#!/usr/bin/env bash
# helpers.sh — Lightweight test framework for hephaestus shell script integration tests
#
# Provides: assertion functions, fixture management (temp git repos), and test tracking.
# Sourced by each test_*.sh file.

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

# ── Counters ─────────────────────────────────────────────────────────────────
TESTS_PASSED=0
TESTS_FAILED=0

# The real hephaestus repo root (one level up from tests/)
HEPHAESTUS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The developer's real HOME, restored by teardown_fixture.
REAL_HOME="$HOME"

# ── Assertions ───────────────────────────────────────────────────────────────

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "  ${GREEN}✓${NC} $1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "  ${RED}✗${NC} $1"
  [ -z "${2:-}" ] || echo -e "    ${RED}→ $2${NC}"
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then pass "$desc"
  else fail "$desc" "expected '$expected', got '$actual'"; fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [ -e "$path" ]; then pass "$desc"
  else fail "$desc" "file not found: $path"; fi
}

assert_file_not_exists() {
  local desc="$1" path="$2"
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then pass "$desc"
  else fail "$desc" "file still exists: $path"; fi
}

assert_dir_exists() {
  local desc="$1" path="$2"
  if [ -d "$path" ]; then pass "$desc"
  else fail "$desc" "directory not found: $path"; fi
}

assert_symlink() {
  local desc="$1" path="$2"
  if [ -L "$path" ]; then pass "$desc"
  else fail "$desc" "not a symlink: $path"; fi
}

assert_not_symlink() {
  local desc="$1" path="$2"
  if [ -e "$path" ] && [ ! -L "$path" ]; then pass "$desc"
  else fail "$desc" "is a symlink or missing: $path"; fi
}

assert_symlink_target_contains() {
  local desc="$1" path="$2" pattern="$3"
  if [ -L "$path" ]; then
    local target
    target=$(readlink "$path")
    if [[ "$target" == *"$pattern"* ]]; then pass "$desc"
    else fail "$desc" "target '$target' doesn't contain '$pattern'"; fi
  else
    fail "$desc" "not a symlink: $path"
  fi
}

assert_symlink_valid() {
  local desc="$1" path="$2"
  if [ -L "$path" ] && [ -e "$path" ]; then pass "$desc"
  else fail "$desc" "broken or missing symlink: $path"; fi
}

assert_exit_code() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" -eq "$actual" ]; then pass "$desc"
  else fail "$desc" "expected exit $expected, got $actual"; fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then pass "$desc"
  else fail "$desc" "output doesn't contain '$needle'"; fi
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if ! echo "$haystack" | grep -qF -- "$needle"; then pass "$desc"
  else fail "$desc" "output unexpectedly contains '$needle'"; fi
}

# ── Fixture management ───────────────────────────────────────────────────────
# Each test gets isolated temp repos:
#   FIXTURE_DIR  — root temp directory
#   REMOTE_REPO  — bare git repo acting as "GitHub" for hephaestus
#   SOURCE_REPO  — clone of REMOTE_REPO (where install.sh lives, has origin set)

setup_fixture() {
  # Clean up any previous fixture (defensive — tests should call teardown explicitly)
  teardown_fixture 2>/dev/null || true

  FIXTURE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/heph-test-XXXXXX")

  # Isolate git from the developer's real config. protocol.file.allow is needed
  # to add a local-path submodule (git >= 2.38.1), which the migration test builds.
  export GIT_CONFIG_GLOBAL="$FIXTURE_DIR/gitconfig"
  git config -f "$GIT_CONFIG_GLOBAL" protocol.file.allow always

  # Fixture remote (acts as origin). Built explicitly rather than bare-cloned
  # so it works from detached-HEAD checkouts too (e.g. CI pull_request events,
  # where a bare clone would contain zero branches).
  git init --bare --quiet "$FIXTURE_DIR/remote.git"
  git -C "$HEPHAESTUS_ROOT" push --quiet "$FIXTURE_DIR/remote.git" HEAD:refs/heads/master 2>/dev/null
  git -C "$FIXTURE_DIR/remote.git" symbolic-ref HEAD refs/heads/master

  # Working clone (acts as hephaestus source — its origin points to remote.git)
  git clone --quiet "$FIXTURE_DIR/remote.git" "$FIXTURE_DIR/source" 2>/dev/null

  # Sync uncommitted working tree changes into the fixture so tests always
  # run against the current code, not just the last committed version.
  # Gitignored paths are excluded: a developer checkout can hold ~60MB of build
  # artifacts (.opencode/node_modules) that would be copied once per fixture.
  # The list comes from git, not an rsync `--filter=':- .gitignore'` — rsync
  # cannot read git's negation syntax and would drop all of .hermes/, whose
  # .gitignore is `*` plus `!skills/**`.
  git -C "$HEPHAESTUS_ROOT" ls-files --others --ignored --exclude-standard \
    --directory 2>/dev/null | sed 's|^|/|' > "$FIXTURE_DIR/rsync-excludes"
  rsync -a --exclude='.git' --exclude-from="$FIXTURE_DIR/rsync-excludes" \
    "$HEPHAESTUS_ROOT/" "$FIXTURE_DIR/source/"
  git -C "$FIXTURE_DIR/source" -c user.email="test@test.com" -c user.name="Test" \
    add -A 2>/dev/null
  git -C "$FIXTURE_DIR/source" -c user.email="test@test.com" -c user.name="Test" \
    diff --cached --quiet 2>/dev/null || \
    git -C "$FIXTURE_DIR/source" -c user.email="test@test.com" -c user.name="Test" \
      commit -m "sync working tree" --quiet 2>/dev/null
  git -C "$FIXTURE_DIR/source" push --quiet 2>/dev/null || true

  REMOTE_REPO="$FIXTURE_DIR/remote.git"
  SOURCE_REPO="$FIXTURE_DIR/source"
}

# Reproduce a pre-2.2 install in $1: a `.hephaestus` submodule with every
# adapter symlinked through it, plus a project-owned orient. Used to test
# `install.sh --migrate`.
create_legacy_install() {
  local dir="$1" git_as=(-c user.email=test@test.com -c user.name=Test)
  # Migration only inspects the submodule's registration, never its contents,
  # so point it at a one-commit repo instead of re-cloning all of hephaestus.
  local stub="$FIXTURE_DIR/legacy-submodule.git"
  if [ ! -d "$stub" ]; then
    git init --quiet "$stub.work"
    git -C "$stub.work" "${git_as[@]}" commit --allow-empty -m "stub" --quiet
    git clone --quiet --bare "$stub.work" "$stub" 2>/dev/null
  fi
  git -C "$dir" "${git_as[@]}" submodule add --quiet "$stub" .hephaestus 2>/dev/null
  mkdir -p "$dir"/.claude/{agents,commands} "$dir"/.opencode/{agents,commands} \
           "$dir"/.agents/skills "$dir"/.codex/agents
  ln -s ../../.hephaestus/.claude/agents/coder.md      "$dir/.claude/agents/coder.md"
  ln -s ../../.hephaestus/.claude/commands/ship.md     "$dir/.claude/commands/ship.md"
  ln -s ../../.hephaestus/.opencode/agents/coder.md    "$dir/.opencode/agents/coder.md"
  ln -s ../../.hephaestus/.opencode/commands/ship.md   "$dir/.opencode/commands/ship.md"
  ln -s ../../.hephaestus/.agents/skills/ship          "$dir/.agents/skills/ship"
  ln -s ../../.hephaestus/.codex/agents/coder.toml     "$dir/.codex/agents/coder.toml"
  mkdir -p "$dir"/.hermes/skills/hephaestus "$dir"/.hermes/agents
  ln -s ../../../.hephaestus/.hermes/skills/hephaestus/ship "$dir/.hermes/skills/hephaestus/ship"
  ln -s ../../.hephaestus/.hermes/agents/coder.md           "$dir/.hermes/agents/coder.md"
  echo "MY CUSTOM ORIENT" > "$dir/.claude/commands/orient.md"
  git -C "$dir" "${git_as[@]}" add -A 2>/dev/null
  git -C "$dir" "${git_as[@]}" commit -m "legacy hephaestus install" --quiet 2>/dev/null
}

# Redirect every harness config dir into the fixture so a user-level install
# under test can never touch the developer's real ~/.claude, ~/.codex, ~/.cursor,
# or ~/.config/opencode. Call after setup_fixture; teardown_fixture restores HOME.
sandbox_home() {
  SANDBOX_HOME="$FIXTURE_DIR/home"
  mkdir -p "$SANDBOX_HOME"
  export HOME="$SANDBOX_HOME"
  unset CLAUDE_CONFIG_DIR XDG_CONFIG_HOME CODEX_HOME HERMES_HOME CURSOR_HOME XDG_STATE_HOME
  CLAUDE_DIR="$SANDBOX_HOME/.claude"
  OPENCODE_DIR="$SANDBOX_HOME/.config/opencode"
  CODEX_DIR="$SANDBOX_HOME/.codex"
  HERMES_DIR="$SANDBOX_HOME/.hermes"
  CURSOR_DIR="$SANDBOX_HOME/.cursor"
  USER_MANIFEST="$SANDBOX_HOME/.local/state/hephaestus/manifest"
}

# Create a fresh, empty target git repo. Returns its path.
create_target() {
  local name="${1:-target}"
  local dir="$FIXTURE_DIR/$name"
  mkdir -p "$dir"
  git -C "$dir" init --quiet
  git -C "$dir" -c user.email="test@test.com" -c user.name="Test" \
    commit --allow-empty -m "initial" --quiet
  echo "$dir"
}

teardown_fixture() {
  export HOME="$REAL_HOME"
  if [ -n "${FIXTURE_DIR:-}" ] && [ -d "$FIXTURE_DIR" ]; then
    rm -rf "$FIXTURE_DIR"
  fi
  unset FIXTURE_DIR REMOTE_REPO SOURCE_REPO GIT_CONFIG_GLOBAL \
        SANDBOX_HOME CLAUDE_DIR OPENCODE_DIR CODEX_DIR HERMES_DIR CURSOR_DIR \
        USER_MANIFEST 2>/dev/null || true
}

# ── Test lifecycle ───────────────────────────────────────────────────────────

begin_test() {
  echo ""
  echo -e "${BOLD}• $1${NC}"
}

print_summary() {
  local total=$((TESTS_PASSED + TESTS_FAILED))
  echo ""
  echo "───────────────────────────────────────"
  if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}$total assertions passed${NC}"
  else
    echo -e "${RED}$TESTS_FAILED of $total assertions failed${NC}"
  fi
  return $(( TESTS_FAILED > 0 ? 1 : 0 ))
}
