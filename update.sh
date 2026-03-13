#!/usr/bin/env bash
# update.sh — Pull the latest hephaestus into the current project
#
# Run this from inside a project that already has .hephaestus installed.
# Updates the submodule to the latest commit on the hephaestus main branch.

set -euo pipefail

if [ ! -d ".hephaestus/.git" ] && ! grep -q '\.hephaestus' .gitmodules 2>/dev/null; then
  echo "Error: .hephaestus submodule not found. Run install.sh first."
  exit 1
fi

echo "Updating .hephaestus submodule..."
git submodule update --remote .hephaestus
echo ""

echo "Repairing symlinks (adds any new agents/commands/skills)..."
bash .hephaestus/install.sh .
echo ""

echo "Commit the submodule pointer update:"
echo "  git add .hephaestus .claude .codex && git commit -m 'chore: update hephaestus'"
