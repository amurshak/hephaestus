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

# Normalize a git URL for comparison: convert SSH colon to slash, strip protocol/host, strip .git
# Handles https://github.com/user/repo.git, git@github.com:user/repo.git, ssh://git@github.com/user/repo
# Does NOT handle file:// or bare local paths — those pass through unchanged.
normalize_url() {
  echo "$1" \
    | sed -E 's#^git@([^:]+):#git@\1/#' \
    | sed -E 's#^(https?://|git@|ssh://)[^/]*/##; s#\.git$##'
}

HEPHAESTUS_NORMALIZED=$(normalize_url "$HEPHAESTUS_REPO")

# Check if hephaestus is already registered as a submodule at a different path.
# Accumulates path + url per block, checks when both are set or at next [submodule] header.
if [ -f .gitmodules ]; then
  EXISTING_PATH=""
  EXISTING_URL=""

  check_duplicate() {
    if [ -n "$EXISTING_PATH" ] && [ -n "$EXISTING_URL" ] && [ "$EXISTING_PATH" != ".hephaestus" ]; then
      if [ "$(normalize_url "$EXISTING_URL")" = "$HEPHAESTUS_NORMALIZED" ]; then
        echo "[error] hephaestus already exists at ./$EXISTING_PATH (via .gitmodules)"
        echo "        → To use it: ./$EXISTING_PATH/install.sh ."
        echo "        → To relocate: git rm -f \"$EXISTING_PATH\" && re-run install.sh"
        exit 1
      fi
    fi
  }

  while IFS= read -r line; do
    case "$line" in
      "["*"]")
        check_duplicate
        EXISTING_PATH=""
        EXISTING_URL=""
        ;;
      *"path = "*)  EXISTING_PATH="$(echo "${line#*path = }" | sed 's/[[:space:]]*$//')" ;;
      *"url = "*)   EXISTING_URL="$(echo "${line#*url = }" | sed 's/[[:space:]]*$//')" ;;
    esac
  done < .gitmodules
  check_duplicate
fi

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

# ── 5. Post-install validation ────────────────────────────────────────────────

# Scaffold orient.md if the target project doesn't have one
if [ ! -e .claude/commands/orient.md ] && [ ! -L .claude/commands/orient.md ]; then
  cp .hephaestus/templates/orient.md .claude/commands/orient.md
  echo "[scaffold] orient.md (created template — customize for your project)"
else
  echo "[skip] orient.md (already exists)"
fi

# Check CLAUDE.md for Development Commands section
if [ -f CLAUDE.md ]; then
  if grep -qiE '(development commands|## .*(test|lint|build))' CLAUDE.md; then
    echo "[ok]   CLAUDE.md has development commands"
  else
    echo ""
    echo "[warn] CLAUDE.md missing test/lint/build commands"
    echo "       Hephaestus reads these to run quality gates. Add a section like:"
    echo ""
    echo "       ## Development Commands"
    echo "       \`\`\`bash"
    echo "       npm test          # test"
    echo "       npm run lint      # lint"
    echo "       npm run build     # build"
    echo "       \`\`\`"
  fi
else
  echo ""
  echo "[warn] No CLAUDE.md found"
  echo "       Hephaestus reads CLAUDE.md to discover test/lint/build commands."
  echo "       Create one with a \"Development Commands\" section."
fi
echo ""

echo "Done. Next steps:"
echo "  1. Customize .claude/commands/orient.md for your project"
echo "  2. Add project-specific .claude/hooks/ (lint-on-commit.sh, protect-files.sh)"
echo "  3. Update AGENTS.md to list newly available skills"
echo "  4. git add .gitmodules .hephaestus .claude .codex && git commit"
echo ""
echo "Optional — headless autonomous loop (fresh session per run):"
echo "  nohup ./.hephaestus/loop.sh 30 > autopilot.log 2>&1 &"
