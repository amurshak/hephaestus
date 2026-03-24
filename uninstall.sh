#!/usr/bin/env bash
# uninstall.sh — Remove hephaestus submodule and symlinks from a target project
#
# Usage:
#   .hephaestus/uninstall.sh          (from the target project root)
#   ./uninstall.sh <target_project>   (from the hephaestus repo)
#
# What it does:
#   1. Removes symlinks in .claude/agents/, .claude/commands/, .codex/skills/ that point to .hephaestus/
#   2. Removes the .hephaestus git submodule
#   3. Does NOT remove project-specific files (orient.md, hooks, settings, CLAUDE.md)
#
# Idempotent: safe to run if already uninstalled.

# Intentionally omit -e: cleanup scripts should continue past individual failures.
set -uo pipefail

TARGET="${1:-$(pwd)}"

if [ ! -d "$TARGET" ]; then
  echo "Error: target directory '$TARGET' does not exist."
  exit 1
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "Error: '$TARGET' is not a git repository."
  exit 1
fi

cd "$TARGET"

REMOVED_LINKS=0
REMOVED_DIRS=0

echo "Uninstalling hephaestus from $TARGET"
echo ""

# ── 1. Remove symlinks pointing to .hephaestus ──────────────────────────────

remove_hephaestus_links() {
  local dir="$1"
  [ -d "$dir" ] || return 0

  for f in "$dir"/*; do
    [ -L "$f" ] || continue
    local target
    target=$(readlink "$f")
    if [[ "$target" == *".hephaestus/"* ]]; then
      rm "$f"
      echo "  [removed] $f"
      REMOVED_LINKS=$((REMOVED_LINKS + 1))
    fi
  done
}

echo "Removing hephaestus symlinks:"
remove_hephaestus_links ".claude/agents"
remove_hephaestus_links ".claude/commands"

# Codex skills are directory symlinks (use * without trailing / to catch broken symlinks)
if [ -d ".codex/skills" ]; then
  for d in .codex/skills/*; do
    [ -L "$d" ] || continue
    local_target=$(readlink "$d")
    if [[ "$local_target" == *".hephaestus/"* ]]; then
      rm "$d"
      echo "  [removed] $d"
      REMOVED_DIRS=$((REMOVED_DIRS + 1))
    fi
  done
fi

if [ "$REMOVED_LINKS" -eq 0 ] && [ "$REMOVED_DIRS" -eq 0 ]; then
  echo "  (no hephaestus symlinks found)"
fi
echo ""

# ── 2. Remove .hephaestus submodule ──────────────────────────────────────────

SUBMODULE_REMOVED=false
if [ -d ".hephaestus" ] || grep -qF '.hephaestus' .gitmodules 2>/dev/null; then
  echo "Removing .hephaestus submodule:"
  git submodule deinit -f .hephaestus 2>/dev/null || true
  git rm -f .hephaestus 2>/dev/null || true
  rm -rf .git/modules/.hephaestus 2>/dev/null || true
  echo "  [removed] .hephaestus submodule"
  SUBMODULE_REMOVED=true
else
  echo "Submodule:"
  echo "  (no .hephaestus submodule found)"
fi
echo ""

# ── 3. Summary ───────────────────────────────────────────────────────────────

TOTAL=$((REMOVED_LINKS + REMOVED_DIRS))
if [ "$SUBMODULE_REMOVED" = true ]; then
  echo "Done. Removed $TOTAL symlink(s) and the .hephaestus submodule."
else
  echo "Done. Removed $TOTAL symlink(s). No submodule was present."
fi
echo ""
echo "Kept (project-specific):"
echo "  - .claude/commands/orient.md (if present)"
echo "  - .claude/hooks/ (if present)"
echo "  - .claude/settings.local.json (if present)"
echo "  - CLAUDE.md"
echo ""
echo "Run: git add -A && git commit -m 'chore: remove hephaestus'"
