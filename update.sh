#!/usr/bin/env bash
# update.sh — Pull the latest hephaestus into the current project
#
# Run this from inside a project that already has .hephaestus installed.
# Updates the submodule to the latest commit on the hephaestus main branch.

set -euo pipefail

if [ ! -e ".hephaestus/.git" ] && ! grep -qF '.hephaestus' .gitmodules 2>/dev/null; then
  echo "Error: .hephaestus submodule not found. Run install.sh first."
  exit 1
fi

# Record current version
OLD_VERSION=$(cat .hephaestus/VERSION 2>/dev/null || echo "unknown")
OLD_HEAD=$(git -C .hephaestus rev-parse HEAD 2>/dev/null || echo "")

echo "Updating .hephaestus submodule (current: $OLD_VERSION)..."
git submodule update --remote .hephaestus
echo ""

# Record new version
NEW_VERSION=$(cat .hephaestus/VERSION 2>/dev/null || echo "unknown")
NEW_HEAD=$(git -C .hephaestus rev-parse HEAD 2>/dev/null || echo "")

# Show what changed
if [ -n "$OLD_HEAD" ] && [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
  echo "Changes:"
  git -C .hephaestus log --oneline "$OLD_HEAD..$NEW_HEAD" 2>/dev/null || echo "  (could not read log)"
  echo ""
else
  echo "Already up to date."
  echo ""
fi

echo "Repairing symlinks and cleaning stale links..."
bash .hephaestus/install.sh --clean .
echo ""

echo "Updated hephaestus: $OLD_VERSION → $NEW_VERSION"
echo ""
echo "Commit the update:"
echo "  git add .hephaestus .claude .opencode && git commit -m 'chore: update hephaestus to $NEW_VERSION'"
