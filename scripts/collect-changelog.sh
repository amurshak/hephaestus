#!/usr/bin/env bash
# collect-changelog.sh — Assemble changelog fragments into CHANGELOG.md
#
# Usage:
#   scripts/collect-changelog.sh <version>   Fold fragments into a released section
#   scripts/collect-changelog.sh --preview   Print what would be folded, change nothing
#   scripts/collect-changelog.sh --check     Exit 1 if any fragment is malformed
#
# Fragments live in changelog.d/ as `<id>.<category>.md`, one per PR, so parallel
# branches never touch the same file. Categories: added, changed, fixed, removed.
# Fragment content is the entry body without the leading "- ".
#
# Bash 3.2 compatible: no associative arrays, no mapfile.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAGMENT_DIR="$REPO_ROOT/changelog.d"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"

# Keep-a-Changelog ordering. Fragment categories must match one of these.
CATEGORIES="added changed fixed removed"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

die() { echo -e "${RED}error:${NC} $1" >&2; exit 1; }

label_for() {
  case "$1" in
    added)   echo "Added" ;;
    changed) echo "Changed" ;;
    fixed)   echo "Fixed" ;;
    removed) echo "Removed" ;;
    *)       return 1 ;;
  esac
}

# ── Validate fragment filenames ──────────────────────────────────────────────
# Returns 1 if any fragment is malformed. Prints every problem, not just the first.
validate_fragments() {
  local ok=0 f base category
  for f in "$FRAGMENT_DIR"/*.md; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ "$base" = "README.md" ] && continue

    category="$(echo "$base" | sed -n 's/^.*\.\([a-z]*\)\.md$/\1/p')"
    if [ -z "$category" ]; then
      echo -e "${RED}✗${NC} $base — expected <id>.<category>.md" >&2
      ok=1
      continue
    fi
    if ! label_for "$category" >/dev/null; then
      echo -e "${RED}✗${NC} $base — unknown category '$category' (want: $CATEGORIES)" >&2
      ok=1
      continue
    fi
    if [ ! -s "$f" ]; then
      echo -e "${RED}✗${NC} $base — empty fragment" >&2
      ok=1
    fi
  done
  return $ok
}

# ── Render fragments as markdown sections ────────────────────────────────────
# Emits "### Added\n- entry\n" blocks in CATEGORIES order, skipping empty ones.
# LEGACY_BODY (optional) is a file of hand-written `## Unreleased` markdown; its
# entries merge under the same category headers rather than repeating them.
render_fragments() {
  local legacy="${1:-}"
  local category label f base found body legacy_entries
  for category in $CATEGORIES; do
    label="$(label_for "$category")"
    found=0

    for f in "$FRAGMENT_DIR"/*."$category".md; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"
      [ "$base" = "README.md" ] && continue
      if [ "$found" -eq 0 ]; then
        printf '### %s\n' "$label"
        found=1
      fi
      # Strip trailing blank lines, prefix the first line with "- ".
      body="$(sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$f")"
      printf -- '- %s\n' "$body"
    done

    # Fold any legacy entries under this same heading — never a second header.
    if [ -n "$legacy" ] && [ -s "$legacy" ]; then
      legacy_entries="$(section_entries "$label" "$legacy")"
      if [ -n "$legacy_entries" ]; then
        [ "$found" -eq 0 ] && printf '### %s\n' "$label" && found=1
        printf '%s\n' "$legacy_entries"
      fi
    fi

    [ "$found" -eq 1 ] && printf '\n'
  done

  # Preserve legacy content under headings outside CATEGORIES (e.g. "Deprecated")
  # rather than silently dropping it.
  if [ -n "$legacy" ] && [ -s "$legacy" ]; then
    unknown_sections "$legacy"
  fi
}

# Entries under a given "### <Label>" heading, up to the next heading.
section_entries() {
  local label="$1" file="$2"
  awk -v want="### $label" '
    $0 == want            { inside = 1; next }
    /^###? /  && inside   { inside = 0 }
    inside && NF          { print }
  ' "$file"
}

# Legacy sections whose heading is not one of CATEGORIES, reproduced verbatim.
unknown_sections() {
  local file="$1" known=""
  local category
  for category in $CATEGORIES; do
    known="$known### $(label_for "$category")|"
  done
  awk -v known="$known" '
    /^### / {
      inside = (index(known, $0 "|") == 0)
      if (inside) { print ""; print }
      next
    }
    /^## / { inside = 0 }
    inside && NF { print }
  ' "$file"
}

count_fragments() {
  local n=0 f base
  for f in "$FRAGMENT_DIR"/*.md; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ "$base" = "README.md" ] && continue
    n=$((n + 1))
  done
  echo "$n"
}

# ── Entry point ──────────────────────────────────────────────────────────────
[ -d "$FRAGMENT_DIR" ] || die "no changelog.d/ directory at $FRAGMENT_DIR"
[ -f "$CHANGELOG" ]    || die "no CHANGELOG.md at $CHANGELOG"

MODE="release"
VERSION=""
case "${1:-}" in
  --check)   MODE="check" ;;
  --preview) MODE="preview" ;;
  "")        die "usage: collect-changelog.sh <version> | --preview | --check" ;;
  -*)        die "unknown flag: $1" ;;
  *)         VERSION="$1" ;;
esac

if ! validate_fragments; then
  die "malformed fragments — fix the names above"
fi

if [ "$MODE" = "check" ]; then
  echo -e "${GREEN}✓${NC} $(count_fragments) changelog fragment(s) valid"
  exit 0
fi

FRAGMENT_COUNT="$(count_fragments)"

if [ "$MODE" = "preview" ]; then
  if [ "$FRAGMENT_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}no fragments in changelog.d/${NC}"
    exit 0
  fi
  render_fragments
  exit 0
fi

# ── Release mode ─────────────────────────────────────────────────────────────
# Fold fragments AND any hand-written `## Unreleased` body into `## <version>`.
# Carrying the Unreleased body matters during the transition: PRs authored before
# fragments existed still wrote there, and dropping it would lose release notes.

grep -q '^## Unreleased' "$CHANGELOG" || die "CHANGELOG.md has no '## Unreleased' section"

DATE="$(date +%Y-%m-%d)"
TMP="$(mktemp)"
UNRELEASED_BODY="$(mktemp)"
trap 'rm -f "$TMP" "$UNRELEASED_BODY"' EXIT

# Existing Unreleased body: everything between "## Unreleased" and the next "## ".
awk '
  /^## Unreleased/ { inside = 1; next }
  /^## / && inside { inside = 0 }
  inside          { print }
' "$CHANGELOG" > "$UNRELEASED_BODY"

# -s is not enough: an Unreleased section holding only blank lines has nonzero
# size but nothing to publish.
if [ "$FRAGMENT_COUNT" -eq 0 ] && ! grep -q '[^[:space:]]' "$UNRELEASED_BODY"; then
  die "nothing to release — no fragments and no Unreleased content"
fi

# Rebuild: header, empty Unreleased, then the new version section.
awk -v version="$VERSION" -v date="$DATE" '
  /^## Unreleased/ {
    print "## Unreleased"
    print ""
    print "## " version " — " date
    printed = 1
    inside = 1
    next
  }
  /^## / && inside { inside = 0 }
  inside { next }
  { print }
' "$CHANGELOG" > "$TMP"

# Splice the collected body in under the new version heading.
BODY="$(mktemp)"
trap 'rm -f "$TMP" "$UNRELEASED_BODY" "$BODY"' EXIT
# Hand-written Unreleased entries merge into the fragment sections by category,
# so a legacy "### Added" never produces a second header. Normalize spacing:
# collapse runs of blank lines to one and trim the ends, so the spliced section
# doesn't collide with the heading that follows it.
render_fragments "$UNRELEASED_BODY" \
  | awk '
      NF == 0 { blanks++; next }
      { if (printed && blanks) print ""; blanks = 0; print; printed = 1 }
    ' > "$BODY"

awk -v bodyfile="$BODY" -v version="$VERSION" '
  {
    print
    if ($0 ~ "^## " version " — ") {
      print ""
      while ((getline line < bodyfile) > 0) print line
      close(bodyfile)
      print ""
    }
  }
' "$TMP" > "$CHANGELOG"

# Fragments are consumed — remove them (git rm when tracked, plain rm otherwise).
for f in "$FRAGMENT_DIR"/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  [ "$base" = "README.md" ] && continue
  if git -C "$REPO_ROOT" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    git -C "$REPO_ROOT" rm --quiet "$f"
  else
    rm -f "$f"
  fi
done

echo -e "${GREEN}✓${NC} released $VERSION — folded $FRAGMENT_COUNT fragment(s) into CHANGELOG.md"
