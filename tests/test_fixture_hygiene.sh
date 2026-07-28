#!/usr/bin/env bash
# test_fixture_hygiene.sh — Verify what setup_fixture copies into a fixture.
#
# setup_fixture rsyncs the working tree so tests run against uncommitted code.
# That copy runs once per fixture, so what it includes decides suite runtime,
# and what it omits decides whether the suite tests real code at all. Each
# assertion below pins one of those and rules out a plausible wrong fix:
#
#   ignored artifact absent   — the bug (#146): a 61MB .opencode/node_modules
#                               copied per fixture, ~800MB for test_install.sh
#   untracked file present    — rules out copying from `git ls-files` alone,
#                               which would silently test committed code only
#   tracked-file edit present — rules out `--filter=':- .gitignore'`, which
#                               reads .hermes/.gitignore (`*` plus `!skills/**`)
#                               as a bare `*` and stops syncing edits to that
#                               tree. Asserting mere *presence* of a .hermes
#                               file would be vacuous: SOURCE_REPO is a clone
#                               that already holds every tracked file, and the
#                               rsync has no --delete.
#
# The fixture this needs is built here rather than assumed: .opencode/.gitignore
# is itself gitignored, so it exists only on a checkout where OpenCode has run
# and is absent on CI.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

OPENCODE_IGNORE="$HEPHAESTUS_ROOT/.opencode/.gitignore"
NODE_MODULES="$HEPHAESTUS_ROOT/.opencode/node_modules"
IGNORED_MARKER="$NODE_MODULES/.heph-fixture-marker"
UNTRACKED_MARKER="$HEPHAESTUS_ROOT/.heph-fixture-marker"
# Tracked, and sitting under a .gitignore that ignores everything by default.
TRACKED_FILE="$HEPHAESTUS_ROOT/.hermes/agents/coder.md"
TRACKED_BACKUP=""

# Everything below plants state in the real checkout; undo it however we exit.
cleanup() {
  rm -f "$IGNORED_MARKER" "$UNTRACKED_MARKER"
  if [ -n "$TRACKED_BACKUP" ] && [ -f "$TRACKED_BACKUP" ]; then
    cp "$TRACKED_BACKUP" "$TRACKED_FILE"
    rm -f "$TRACKED_BACKUP"
  fi
  [ -n "${CREATED_OPENCODE_IGNORE:-}" ] && rm -f "$OPENCODE_IGNORE"
  [ -n "${CREATED_NODE_MODULES:-}" ] && rmdir "$NODE_MODULES" 2>/dev/null
  teardown_fixture 2>/dev/null || true
  return 0
}
trap cleanup EXIT

if [ ! -e "$OPENCODE_IGNORE" ]; then
  printf 'node_modules\n.gitignore\n' > "$OPENCODE_IGNORE"
  CREATED_OPENCODE_IGNORE=1
fi
if [ ! -d "$NODE_MODULES" ]; then
  mkdir -p "$NODE_MODULES"
  CREATED_NODE_MODULES=1
fi
touch "$IGNORED_MARKER" "$UNTRACKED_MARKER"

# Assign TRACKED_BACKUP only once the copy succeeds: mktemp creates the file, so
# a failed cp would leave cleanup() restoring zero bytes over a tracked file.
tmp=$(mktemp "${TMPDIR:-/tmp}/heph-tracked-XXXXXX")
cp "$TRACKED_FILE" "$tmp" || {
  rm -f "$tmp"
  echo "cannot back up $TRACKED_FILE" >&2
  exit 1
}
TRACKED_BACKUP="$tmp"
printf '\n<!-- heph-fixture-marker -->\n' >> "$TRACKED_FILE"

begin_test "setup_fixture copy respects gitignore"

# Guard the premise: git must agree about what is and isn't ignored.
git -C "$HEPHAESTUS_ROOT" check-ignore -q "$IGNORED_MARKER"
assert_exit_code "ignored marker is gitignored" 0 $?
git -C "$HEPHAESTUS_ROOT" check-ignore -q "$UNTRACKED_MARKER"
assert_exit_code "untracked marker is not gitignored" 1 $?

setup_fixture

assert_file_not_exists "gitignored artifact is not copied" \
  "$SOURCE_REPO/.opencode/node_modules/.heph-fixture-marker"

found=$(find "$SOURCE_REPO" -name node_modules -not -path '*/.git/*' | wc -l | tr -d ' ')
assert_eq "no node_modules directory anywhere in the fixture" "0" "$found"

assert_file_exists "untracked working-tree file is copied" \
  "$SOURCE_REPO/.heph-fixture-marker"

assert_contains "uncommitted edit under an ignore-all .gitignore is copied" \
  "$(cat "$SOURCE_REPO/.hermes/agents/coder.md" 2>/dev/null)" \
  "heph-fixture-marker"

# rsync drops the last character of an unterminated final line, which turns the
# last pattern into a different one — under-excluding the artifact it names, or
# excluding a tracked file that the truncated pattern happens to match.
# assert_file_exists first: `tail` on a missing path yields empty stdout, which
# would compare equal to "" and pass, leaving the property silently unguarded.
assert_file_exists "exclude list is written" "$FIXTURE_DIR/rsync-excludes"
assert_eq "exclude list's last line is newline-terminated" \
  "" "$(tail -c 1 "$FIXTURE_DIR/rsync-excludes")"

teardown_fixture

print_summary
