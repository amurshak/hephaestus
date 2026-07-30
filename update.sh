#!/usr/bin/env bash
# update.sh — Pull the latest hephaestus and refresh the install
#
# Usage:
#   ./update.sh                   Pull, then refresh the user-level install
#   ./update.sh --vendor <path>   Pull, then refresh a project's vendored copy
#
# Run from anywhere — paths resolve against this clone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE=user
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vendor) MODE=vendor; shift ;;
    -*) echo "Error: unknown flag '$1'"; echo "Usage: ./update.sh [--vendor <path>]"; exit 1 ;;
    *) TARGET="$1"; shift ;;
  esac
done

if [ "$MODE" = vendor ] && [ -z "$TARGET" ]; then
  echo "Error: --vendor requires a project path."
  exit 1
fi

OLD_VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown")
OLD_HEAD=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "")

echo "Updating hephaestus at $SCRIPT_DIR (current: $OLD_VERSION)..."
git -C "$SCRIPT_DIR" pull --ff-only
echo ""

NEW_VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown")
NEW_HEAD=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "")

if [ -n "$OLD_HEAD" ] && [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
  echo "Changes:"
  git -C "$SCRIPT_DIR" log --oneline "$OLD_HEAD..$NEW_HEAD" 2>/dev/null || echo "  (could not read log)"
  echo ""
else
  echo "Already up to date."
  echo ""
fi

if [ "$MODE" = vendor ]; then
  bash "$SCRIPT_DIR/install.sh" --vendor "$TARGET"
else
  bash "$SCRIPT_DIR/install.sh" --clean
fi

echo "Updated hephaestus: $OLD_VERSION → $NEW_VERSION"
if [ "$MODE" = vendor ]; then
  # Match the paths install.sh just listed — a project that adopted changelog
  # fragments has more to stage than the adapters.
  CHANGELOG_PATHS=""
  [ -d "$TARGET/changelog.d" ] && CHANGELOG_PATHS=" changelog.d scripts/collect-changelog.sh CHANGELOG.md .gitattributes"
  echo ""
  echo "Commit the refreshed copy:"
  echo "  git -C $TARGET add .heph-manifest .claude .opencode .agents .codex .cursor .hermes/skills .hermes/agents$CHANGELOG_PATHS && git -C $TARGET commit -m 'chore: update hephaestus to $NEW_VERSION'"
fi
