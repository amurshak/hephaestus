#!/usr/bin/env bash
# test_changelog_fragments.sh — Verify changelog fragment collection.
#
# Fragments exist so parallel branches never edit a shared anchor in CHANGELOG.md.
# These tests cover filename validation, category ordering, the release fold, and
# the transition guarantee that hand-written `## Unreleased` content is merged by
# category rather than duplicated as a second heading.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/heph-changelog-XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

# Build an isolated repo root: the script resolves paths from its own location.
make_repo() {
  local dest="$1" unreleased="${2:-}"
  rm -rf "$dest"
  mkdir -p "$dest/scripts" "$dest/changelog.d"
  cp "$HEPHAESTUS_ROOT/scripts/collect-changelog.sh" "$dest/scripts/"
  printf '# changelog.d/\n\nFragment docs, never a changelog entry.\n' > "$dest/changelog.d/README.md"
  {
    printf '# Changelog\n\n## Unreleased\n'
    [ -n "$unreleased" ] && printf '\n%s\n' "$unreleased"
    printf '\n## 2.1.0 — 2026-07-28\n\n### Added\n- Older stuff.\n'
  } > "$dest/CHANGELOG.md"
}

frag() { printf '%s\n' "$3" > "$1/changelog.d/$2"; }

# ─────────────────────────────────────────────────────────────────────────────
begin_test "--check validates fragment filenames"

R="$FIXTURE/check"
make_repo "$R"
frag "$R" "129.fixed.md" '**Spawn CLI** (#129): a fix.'
frag "$R" "107.added.md" '**Cursor generator** (#107): a feature.'
out=$("$R/scripts/collect-changelog.sh" --check 2>&1); rc=$?
assert_exit_code "valid fragments pass --check" 0 "$rc"
assert_contains "reports fragment count" "$out" "2 changelog fragment"

touch "$R/changelog.d/bogus.md"
out=$("$R/scripts/collect-changelog.sh" --check 2>&1); rc=$?
assert_exit_code "missing category rejected" 1 "$rc"
assert_contains "names the offending file" "$out" "bogus.md"
rm "$R/changelog.d/bogus.md"

frag "$R" "nope.wrongcat.md" 'x'
out=$("$R/scripts/collect-changelog.sh" --check 2>&1); rc=$?
assert_exit_code "unknown category rejected" 1 "$rc"
assert_contains "lists valid categories" "$out" "added changed fixed removed"
rm "$R/changelog.d/nope.wrongcat.md"

: > "$R/changelog.d/empty.added.md"
out=$("$R/scripts/collect-changelog.sh" --check 2>&1); rc=$?
assert_exit_code "empty fragment rejected" 1 "$rc"
assert_contains "flags emptiness" "$out" "empty fragment"
rm "$R/changelog.d/empty.added.md"

# ─────────────────────────────────────────────────────────────────────────────
begin_test "--preview renders without mutating"

R="$FIXTURE/preview"
make_repo "$R"
frag "$R" "129.fixed.md" '**Spawn CLI** (#129): a fix.'
frag "$R" "107.added.md" '**Cursor generator** (#107): a feature.'
before=$(cat "$R/CHANGELOG.md")
out=$("$R/scripts/collect-changelog.sh" --preview 2>&1); rc=$?
assert_exit_code "preview exits 0" 0 "$rc"
assert_contains "renders Added section" "$out" "### Added"
assert_contains "renders Fixed section" "$out" "### Fixed"
assert_contains "prefixes entries with a dash" "$out" "- **Cursor generator**"
assert_eq "CHANGELOG.md untouched" "$before" "$(cat "$R/CHANGELOG.md")"
assert_file_exists "fragment retained" "$R/changelog.d/129.fixed.md"

# Added must precede Fixed regardless of filename order.
added_line=$(printf '%s\n' "$out" | grep -n '^### Added' | cut -d: -f1)
fixed_line=$(printf '%s\n' "$out" | grep -n '^### Fixed' | cut -d: -f1)
if [ "$added_line" -lt "$fixed_line" ]; then
  pass "categories render in Keep-a-Changelog order"
else
  fail "categories render in Keep-a-Changelog order" "Added at $added_line, Fixed at $fixed_line"
fi

# ─────────────────────────────────────────────────────────────────────────────
begin_test "release folds fragments and consumes them"

R="$FIXTURE/release"
make_repo "$R"
frag "$R" "129.fixed.md" '**Spawn CLI** (#129): a fix.'
frag "$R" "107.added.md" '**Cursor generator** (#107): a feature.'
out=$("$R/scripts/collect-changelog.sh" 2.2.0 2>&1); rc=$?
body=$(cat "$R/CHANGELOG.md")
assert_exit_code "release exits 0" 0 "$rc"
assert_contains "writes dated version heading" "$body" "## 2.2.0 — "
assert_contains "keeps an empty Unreleased" "$body" "## Unreleased"
assert_contains "includes the fragment entry" "$body" "- **Cursor generator** (#107): a feature."
assert_contains "preserves prior releases" "$body" "## 2.1.0"
assert_file_not_exists "fragment consumed" "$R/changelog.d/129.fixed.md"
assert_file_exists "changelog.d/README.md survives the fold" "$R/changelog.d/README.md"
assert_not_contains "README is not treated as an entry" "$body" "Fragment docs, never a changelog entry."

# ─────────────────────────────────────────────────────────────────────────────
begin_test "release merges legacy Unreleased content by category"

R="$FIXTURE/legacy"
make_repo "$R" '### Added
- **Legacy entry** (#100): written before fragments existed.

### Deprecated
- **Old thing** (#101): a category outside the known set.'
frag "$R" "107.added.md" '**Cursor generator** (#107): a feature.'
frag "$R" "129.fixed.md" '**Spawn CLI** (#129): a fix.'
"$R/scripts/collect-changelog.sh" 2.2.0 >/dev/null 2>&1
section=$(awk '/^## 2.2.0/,/^## 2.1.0/' "$R/CHANGELOG.md")

added_headers=$(printf '%s\n' "$section" | grep -c '^### Added')
assert_eq "legacy Added merges into one heading" "1" "$added_headers"
assert_contains "fragment entry present" "$section" "- **Cursor generator** (#107)"
assert_contains "legacy entry present" "$section" "- **Legacy entry** (#100)"
assert_contains "unknown legacy category preserved" "$section" "### Deprecated"
assert_contains "unknown legacy entry preserved" "$section" "- **Old thing** (#101)"

# No blank-line collapse between the section and the next release heading.
if printf '%s\n' "$(cat "$R/CHANGELOG.md")" | grep -qE '^- .*$' && \
   ! grep -qE '^### .*[^ ]$' /dev/null; then :; fi
blanks_before_next=$(awk '/^## 2.1.0/ { print prev } { prev = $0 }' "$R/CHANGELOG.md")
assert_eq "blank line separates sections" "" "$blanks_before_next"

# ─────────────────────────────────────────────────────────────────────────────
begin_test "release preserves multi-line fragment bodies"

R="$FIXTURE/multiline"
make_repo "$R"
printf '**Wrapped entry** (#42): first line of prose\n  continued on a second line.\n' \
  > "$R/changelog.d/42.changed.md"
"$R/scripts/collect-changelog.sh" 2.3.0 >/dev/null 2>&1
body=$(cat "$R/CHANGELOG.md")
assert_contains "first line prefixed" "$body" "- **Wrapped entry** (#42): first line of prose"
assert_contains "continuation retained" "$body" "continued on a second line."

# ─────────────────────────────────────────────────────────────────────────────
begin_test "release refuses when there is nothing to release"

R="$FIXTURE/empty"
make_repo "$R"
out=$("$R/scripts/collect-changelog.sh" 2.4.0 2>&1); rc=$?
assert_exit_code "exits 1 with no fragments and empty Unreleased" 1 "$rc"
assert_contains "explains why" "$out" "nothing to release"

# ─────────────────────────────────────────────────────────────────────────────
begin_test "release requires an Unreleased section"

R="$FIXTURE/no-unreleased"
make_repo "$R"
printf '# Changelog\n\n## 2.1.0 — 2026-07-28\n\n### Added\n- Older stuff.\n' > "$R/CHANGELOG.md"
frag "$R" "107.added.md" '**Cursor generator** (#107): a feature.'
out=$("$R/scripts/collect-changelog.sh" 2.5.0 2>&1); rc=$?
assert_exit_code "exits 1 without Unreleased" 1 "$rc"
assert_contains "names the missing section" "$out" "Unreleased"

# ─────────────────────────────────────────────────────────────────────────────
begin_test "flags are position-independent and never fall through to release"

# Regression: a `case` on $1 alone ignored every later argument, so
# `<version> --preview` silently ran a real release and deleted the fragments.
count_frags() { ls "$1/changelog.d"/*.md 2>/dev/null | grep -vc 'README.md$'; }

for form in "2.9.0 --preview" "--preview 2.9.0" "--preview" "--check" "2.9.0 --check"; do
  R="$FIXTURE/args-$(printf '%s' "$form" | tr -cd '[:alnum:]')"
  make_repo "$R"
  frag "$R" "107.added.md" '**Cursor generator** (#107): a feature.'
  frag "$R" "129.fixed.md" '**Spawn CLI** (#129): a fix.'
  before=$(cat "$R/CHANGELOG.md")
  # shellcheck disable=SC2086
  out=$("$R/scripts/collect-changelog.sh" $form 2>&1); rc=$?
  assert_exit_code "'$form' exits 0" 0 "$rc"
  assert_eq "'$form' leaves CHANGELOG.md untouched" "$before" "$(cat "$R/CHANGELOG.md")"
  assert_eq "'$form' consumes no fragments" "2" "$(count_frags "$R")"
  assert_not_contains "'$form' does not claim a release" "$out" "released"
done

# The version reaches preview output, so previewing a release is a real rehearsal.
R="$FIXTURE/args-heading"
make_repo "$R"
frag "$R" "107.added.md" '**Cursor generator** (#107): a feature.'
out=$("$R/scripts/collect-changelog.sh" 2.9.0 --preview 2>&1)
assert_contains "preview renders the version heading" "$out" "## 2.9.0 — "

# An unrecognized flag must never reach the destructive default.
for bad in "2.9.0 --dry-run" "--dry-run" "2.9.0 -n" "2.9.0 extra"; do
  R="$FIXTURE/bad-$(printf '%s' "$bad" | tr -cd '[:alnum:]')"
  make_repo "$R"
  frag "$R" "107.added.md" '**Cursor generator** (#107): a feature.'
  before=$(cat "$R/CHANGELOG.md")
  # shellcheck disable=SC2086
  out=$("$R/scripts/collect-changelog.sh" $bad 2>&1); rc=$?
  assert_exit_code "'$bad' exits 1" 1 "$rc"
  assert_eq "'$bad' leaves CHANGELOG.md untouched" "$before" "$(cat "$R/CHANGELOG.md")"
  assert_eq "'$bad' consumes no fragments" "1" "$(count_frags "$R")"
done

R="$FIXTURE/args-noargs"
make_repo "$R"
out=$("$R/scripts/collect-changelog.sh" 2>&1); rc=$?
assert_exit_code "no arguments exits 1" 1 "$rc"
assert_contains "no arguments prints usage" "$out" "usage:"

# ─────────────────────────────────────────────────────────────────────────────
begin_test "release consumes a tracked fragment with unstaged modifications"

# Regression (#205): `git rm` refuses a locally-modified file, the script never
# checked, so the fragment survived the fold and re-folded next release — while
# the run still printed the success line.
# gpgsign off: with a global `commit.gpgsign = true` and no gpg, the baseline
# commit would fail silently and the fixture would test staged, not committed.
git_t() { git -C "$1" -c user.email="test@test.com" -c user.name="Test" -c commit.gpgsign=false "${@:2}"; }

R="$FIXTURE/modified"
make_repo "$R"
frag "$R" "107.added.md" '**Cursor generator** (#107): a feature.'
frag "$R" "205.changed.md" '**Worktree cap** (#205): original wording.'
git_t "$R" init --quiet
git_t "$R" add -A
git_t "$R" commit -m "baseline" --quiet
frag "$R" "205.changed.md" '**Worktree cap** (#205): reconciled wording.'
out=$("$R/scripts/collect-changelog.sh" 2.2.0 2>&1); rc=$?
body=$(cat "$R/CHANGELOG.md")
assert_exit_code "release exits 0" 0 "$rc"
assert_contains "publishes the on-disk (modified) content" "$body" "- **Worktree cap** (#205): reconciled wording."
assert_not_contains "committed wording is not what publishes" "$body" "original wording"
assert_file_not_exists "modified fragment consumed" "$R/changelog.d/205.changed.md"
leftovers=$(ls "$R/changelog.d")
assert_eq "changelog.d/ holds only README.md" "README.md" "$leftovers"
assert_contains "reports the clean fold" "$out" "released 2.2.0"

# ─────────────────────────────────────────────────────────────────────────────
begin_test "release refuses to claim success over a leftover fragment"

# When removal genuinely fails (here: an unwritable changelog.d/), the content
# is still folded, so the run must exit nonzero and name the leftover count
# instead of printing the success line. The fixture is a git repo with the
# fragment committed, so this exercises the `git rm -f` branch — the one #205
# is about. chmod is a no-op for root and for filesystems that don't enforce
# directory permissions, so probe the precondition instead of inferring it.
R="$FIXTURE/leftover"
make_repo "$R"
frag "$R" "107.added.md" '**Cursor generator** (#107): a feature.'
git_t "$R" init --quiet
git_t "$R" add -A
git_t "$R" commit -m "baseline" --quiet
touch "$R/changelog.d/.probe"
chmod 555 "$R/changelog.d"
if rm "$R/changelog.d/.probe" 2>/dev/null; then
  chmod 755 "$R/changelog.d"
  pass "skipped: filesystem does not enforce directory permissions"
else
  out=$("$R/scripts/collect-changelog.sh" 2.2.0 2>&1); rc=$?
  chmod 755 "$R/changelog.d"
  assert_exit_code "release exits 1" 1 "$rc"
  assert_contains "names the leftover" "$out" "1 survived in changelog.d/"
  assert_not_contains "does not claim a clean fold" "$out" "✓"
  assert_file_exists "fragment still on disk" "$R/changelog.d/107.added.md"
fi

# ─────────────────────────────────────────────────────────────────────────────
begin_test "release refuses a version CHANGELOG.md already has"

# The splice injects the body at every matching heading, so re-releasing a
# version (the instinctive retry after the leftover guard fires) would
# duplicate the section and triple the entries.
R="$FIXTURE/rerelease"
make_repo "$R"
frag "$R" "107.added.md" '**Cursor generator** (#107): a feature.'
before=$(cat "$R/CHANGELOG.md")
out=$("$R/scripts/collect-changelog.sh" 2.1.0 2>&1); rc=$?
assert_exit_code "re-release exits 1" 1 "$rc"
assert_contains "names the existing section" "$out" "already has a ## 2.1.0 section"
assert_eq "CHANGELOG.md untouched" "$before" "$(cat "$R/CHANGELOG.md")"
assert_file_exists "fragment retained" "$R/changelog.d/107.added.md"

# ─────────────────────────────────────────────────────────────────────────────
begin_test "repo's own fragments are valid"

out=$("$HEPHAESTUS_ROOT/scripts/collect-changelog.sh" --check 2>&1); rc=$?
assert_exit_code "changelog.d/ passes --check" 0 "$rc"

print_summary
