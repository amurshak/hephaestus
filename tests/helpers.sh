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

  # Allow file:// transport for local submodule operations (git >= 2.38.1 restricts this)
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
  rsync -a --exclude='.git' "$HEPHAESTUS_ROOT/" "$FIXTURE_DIR/source/"
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
  if [ -n "${FIXTURE_DIR:-}" ] && [ -d "$FIXTURE_DIR" ]; then
    rm -rf "$FIXTURE_DIR"
  fi
  unset FIXTURE_DIR REMOTE_REPO SOURCE_REPO GIT_CONFIG_GLOBAL 2>/dev/null || true
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
