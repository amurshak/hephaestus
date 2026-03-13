#!/usr/bin/env bash
# install.sh — Set up hephaestus submodule and symlinks in a target project
#
# Usage:
#   ./install.sh <target_project_path>
#
# What it does:
#   1. Adds this repo as a git submodule at <target>/.hephaestus
#   2. Symlinks shared agents into <target>/.claude/agents/
#   3. Symlinks shared commands into <target>/.claude/commands/
#   4. Symlinks shared codex skills into <target>/.codex/skills/
#
# Idempotent: safe to re-run. Never overwrites existing files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEPHAESTUS_REPO="$(cd "$SCRIPT_DIR" && git remote get-url origin 2>/dev/null || echo "")"
TARGET="${1:-$(pwd)}"

if [ -z "$HEPHAESTUS_REPO" ]; then
  echo "Error: hephaestus repo has no remote origin configured."
  echo "Push hephaestus to GitHub first, then re-run install.sh."
  exit 1
fi

if [ ! -d "$TARGET" ]; then
  echo "Error: target directory '$TARGET' does not exist."
  exit 1
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "Error: '$TARGET' is not a git repository."
  exit 1
fi

echo "Installing hephaestus into $TARGET"
echo "  Source repo: $HEPHAESTUS_REPO"
echo ""

# ── 1. Submodule ─────────────────────────────────────────────────────────────
cd "$TARGET"

if [ -d ".hephaestus/.git" ] || grep -q '\.hephaestus' .gitmodules 2>/dev/null; then
  echo "[skip] .hephaestus submodule already registered — running update"
  git submodule update --init .hephaestus
else
  echo "[add]  Adding .hephaestus submodule"
  git submodule add "$HEPHAESTUS_REPO" .hephaestus
  git submodule update --init .hephaestus
fi
echo ""

# ── 2. Claude agents ─────────────────────────────────────────────────────────
mkdir -p .claude/agents
echo "Symlinking agents:"
for f in .hephaestus/.claude/agents/*.md; do
  name=$(basename "$f")
  dest=".claude/agents/$name"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "  [skip] $name (already exists)"
  else
    ln -s "../../.hephaestus/.claude/agents/$name" "$dest"
    echo "  [link] $name"
  fi
done
echo ""

# ── 3. Claude commands ───────────────────────────────────────────────────────
# orient.md is intentionally excluded — it's project-specific.
SKIP_COMMANDS="orient.md"
mkdir -p .claude/commands
echo "Symlinking commands (skipping: $SKIP_COMMANDS):"
for f in .hephaestus/.claude/commands/*.md; do
  name=$(basename "$f")
  if echo "$SKIP_COMMANDS" | grep -qw "$name"; then
    echo "  [skip] $name (project-specific)"
    continue
  fi
  dest=".claude/commands/$name"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "  [skip] $name (already exists)"
  else
    ln -s "../../.hephaestus/.claude/commands/$name" "$dest"
    echo "  [link] $name"
  fi
done
echo ""

# ── 4. Codex skills ──────────────────────────────────────────────────────────
mkdir -p .codex/skills
echo "Symlinking codex skills:"
for d in .hephaestus/.codex/skills/*/; do
  name=$(basename "$d")
  dest=".codex/skills/$name"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "  [skip] $name (already exists)"
  else
    ln -s "../../.hephaestus/.codex/skills/$name" "$dest"
    echo "  [link] $name"
  fi
done
echo ""

echo "Done. Next steps:"
echo "  1. Add a project-specific .claude/commands/orient.md"
echo "  2. Add project-specific .claude/hooks/ (lint-on-commit.sh, protect-files.sh)"
echo "  3. Update AGENTS.md to list newly available skills"
echo "  4. git add .gitmodules .hephaestus .claude .codex && git commit"
