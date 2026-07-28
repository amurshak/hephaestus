#!/usr/bin/env bash
# test_fixture_hygiene.sh — Verify what setup_fixture copies into a fixture.
#
# setup_fixture rsyncs the working tree so tests run against uncommitted code.
# That copy runs once per fixture, so what it includes decides suite runtime,
# and what it omits decides whether the suite tests real code at all. Each
# assertion below pins one of those and rules out a plausible wrong fix:
#
#   ignored artifacts absent  — the bug (#146): a 61MB .opencode/node_modules
#                               copied per fixture, ~800MB for test_install.sh
#   .hermes/ present          — rules out `--filter=':- .gitignore'`, which
#                               reads .hermes/.gitignore (`*` plus `!skills/**`)
#                               as a bare `*` and drops the whole tree
#   untracked file present    — rules out copying from `git ls-files` alone,
#                               which would silently test committed code only

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Markers planted in the real checkout, removed however this script exits.
IGNORED_MARKER="$HEPHAESTUS_ROOT/.opencode/node_modules/.heph-fixture-marker"
UNTRACKED_MARKER="$HEPHAESTUS_ROOT/.heph-fixture-marker"

cleanup() {
  rm -f "$IGNORED_MARKER" "$UNTRACKED_MARKER"
  # Only remove node_modules/ if this script created it.
  [ -n "${CREATED_NODE_MODULES:-}" ] && rmdir "$HEPHAESTUS_ROOT/.opencode/node_modules" 2>/dev/null
  teardown_fixture 2>/dev/null || true
}
trap cleanup EXIT

if [ ! -d "$HEPHAESTUS_ROOT/.opencode/node_modules" ]; then
  mkdir -p "$HEPHAESTUS_ROOT/.opencode/node_modules"
  CREATED_NODE_MODULES=1
fi
touch "$IGNORED_MARKER" "$UNTRACKED_MARKER"

begin_test "setup_fixture copy respects gitignore"

# Guard the premise: git must actually consider these ignored / not ignored.
git -C "$HEPHAESTUS_ROOT" check-ignore -q "$IGNORED_MARKER"
assert_exit_code "ignored marker is gitignored" 0 $?
git -C "$HEPHAESTUS_ROOT" check-ignore -q "$UNTRACKED_MARKER"
assert_exit_code "untracked marker is not gitignored" 1 $?

setup_fixture

assert_file_not_exists "gitignored artifact is not copied" \
  "$SOURCE_REPO/.opencode/node_modules/.heph-fixture-marker"
assert_file_exists "untracked working-tree file is copied" \
  "$SOURCE_REPO/.heph-fixture-marker"
assert_file_exists "tracked file under an ignore-all .gitignore is copied" \
  "$SOURCE_REPO/.hermes/skills/hephaestus/ship/SKILL.md"
assert_file_exists "tracked .hermes/.gitignore itself is copied" \
  "$SOURCE_REPO/.hermes/.gitignore"

found=$(find "$SOURCE_REPO" -name node_modules -not -path '*/.git/*' | wc -l | tr -d ' ')
assert_eq "no node_modules directory anywhere in the fixture" "0" "$found"

teardown_fixture

print_summary
