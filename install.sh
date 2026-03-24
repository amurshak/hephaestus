#!/usr/bin/env bash
# install.sh — Set up hephaestus submodule and symlinks in a target project
#
# Usage:
#   ./install.sh [--audit | --force] <target_project_path>
#
# Flags:
#   --audit   Show what would happen without modifying the filesystem
#   --force   Replace existing files with hephaestus symlinks
#
# What it does:
#   1. Adds this repo as a git submodule at <target>/.hephaestus
#   2. Symlinks shared agents into <target>/.claude/agents/
#   3. Symlinks shared commands into <target>/.claude/commands/
#   4. Symlinks shared codex skills into <target>/.codex/skills/
#   5. Scaffolds orient.md template if missing
#   6. Validates CLAUDE.md has development commands
#
# Idempotent: safe to re-run. Never overwrites existing files (unless --force).

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────
AUDIT_MODE=false
FORCE_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --audit) AUDIT_MODE=true; shift ;;
    --force) FORCE_MODE=true; shift ;;
    -*) echo "Error: unknown flag '$1'"; echo "Usage: ./install.sh [--audit | --force] <target>"; exit 1 ;;
    *) break ;;
  esac
done

if [ "$AUDIT_MODE" = true ] && [ "$FORCE_MODE" = true ]; then
  echo "Error: --audit and --force cannot be used together."
  exit 1
fi

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

# ── Helpers ──────────────────────────────────────────────────────────────────

# Normalize a git URL for comparison: convert SSH colon to slash, strip protocol/host, strip .git
# Handles https://github.com/user/repo.git, git@github.com:user/repo.git, ssh://git@github.com/user/repo
# Does NOT handle file:// or bare local paths — those pass through unchanged.
normalize_url() {
  echo "$1" \
    | sed -E 's#^git@([^:]+):#git@\1/#' \
    | sed -E 's#^(https?://|git@|ssh://)[^/]*/##; s#\.git$##'
}

# Link or audit a single item. Usage: link_item <source_symlink_path> <dest> <name> <category>
# source_symlink_path: relative symlink target (e.g., ../../.hephaestus/.claude/agents/coder.md)
# source_abs: absolute path to the hephaestus source file (for audit line counts)
# dest: path in target project
# name: display name
# category: agents/commands/skills (for audit table)
link_item() {
  local symlink_path="$1" source_abs="$2" dest="$3" name="$4"

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$AUDIT_MODE" = true ]; then
      local yours_lines heph_lines
      yours_lines=$(wc -l < "$dest" 2>/dev/null | tr -d ' ' || echo "?")
      heph_lines=$(wc -l < "$source_abs" 2>/dev/null | tr -d ' ' || echo "?")
      printf "  %-25s %-12s %s\n" "$name" "conflict" "yours: ${yours_lines} lines, hephaestus: ${heph_lines} lines"
    elif [ "$FORCE_MODE" = true ]; then
      rm -f "$dest"
      ln -s "$symlink_path" "$dest"
      echo "  [replace] $name"
    else
      echo "  [skip] $name (already exists)"
      echo "         → replace: rm $dest && re-run install.sh"
      echo "         → compare: diff $dest .hephaestus/${dest#./}"
    fi
  else
    if [ "$AUDIT_MODE" = true ]; then
      printf "  %-25s %-12s %s\n" "$name" "new" "will symlink"
    else
      ln -s "$symlink_path" "$dest"
      echo "  [link] $name"
    fi
  fi
}

# Check for near-name collisions between target files and hephaestus files
# e.g., target has "critic.md", hephaestus has "critique.md"
check_name_collisions() {
  local target_dir="$1" heph_dir="$2" label="$3"
  [ -d "$target_dir" ] || return 0
  [ -d "$heph_dir" ] || return 0

  for target_file in "$target_dir"/*.md; do
    [ -e "$target_file" ] || continue
    local tname
    tname=$(basename "$target_file" .md)
    for heph_file in "$heph_dir"/*.md; do
      [ -e "$heph_file" ] || continue
      local hname
      hname=$(basename "$heph_file" .md)
      # Skip exact matches (handled by link_item)
      [ "$tname" = "$hname" ] && continue
      # Check if one name is a prefix of the other (critic/critique, test/tester, etc.)
      if [[ "$tname" == "$hname"* ]] || [[ "$hname" == "$tname"* ]]; then
        echo "  [note] $label: $tname.md (yours) ↔ $hname.md (hephaestus) — similar names, both will be available"
      fi
    done
  done
}

# ── Main ─────────────────────────────────────────────────────────────────────

if [ "$AUDIT_MODE" = true ]; then
  echo "Audit: hephaestus → $TARGET (no changes will be made)"
else
  echo "Installing hephaestus into $TARGET"
fi
echo "  Source repo: $HEPHAESTUS_REPO"
echo ""

cd "$TARGET"

# ── 1. Submodule ─────────────────────────────────────────────────────────────

HEPHAESTUS_NORMALIZED=$(normalize_url "$HEPHAESTUS_REPO")

# Check if hephaestus is already registered as a submodule at a different path.
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

if [ "$AUDIT_MODE" = true ]; then
  if [ -d ".hephaestus/.git" ] || grep -q '\.hephaestus' .gitmodules 2>/dev/null; then
    echo "[ok]   .hephaestus submodule already registered"
  else
    echo "[new]  .hephaestus submodule will be added"
  fi
  echo ""
else
  if [ -d ".hephaestus/.git" ] || grep -q '\.hephaestus' .gitmodules 2>/dev/null; then
    echo "[skip] .hephaestus submodule already registered — running update"
    git submodule update --init .hephaestus
  else
    echo "[add]  Adding .hephaestus submodule"
    git submodule add "$HEPHAESTUS_REPO" .hephaestus
    git submodule update --init .hephaestus
  fi
  echo ""
fi

# For audit mode, we need the hephaestus source files. Use SCRIPT_DIR if .hephaestus doesn't exist yet.
if [ -d ".hephaestus" ]; then
  HEPH_SRC=".hephaestus"
else
  HEPH_SRC="$SCRIPT_DIR"
fi

# ── 2. Claude agents ─────────────────────────────────────────────────────────
if [ "$AUDIT_MODE" != true ]; then
  mkdir -p .claude/agents
fi
echo "Agents:"
if [ "$AUDIT_MODE" = true ]; then
  printf "  %-25s %-12s %s\n" "Name" "Status" "Details"
  printf "  %-25s %-12s %s\n" "----" "------" "-------"
fi
for f in "$HEPH_SRC"/.claude/agents/*.md; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  link_item "../../.hephaestus/.claude/agents/$name" "$f" ".claude/agents/$name" "$name"
done
echo ""

# ── 3. Claude commands ───────────────────────────────────────────────────────
SKIP_COMMANDS="orient.md"
if [ "$AUDIT_MODE" != true ]; then
  mkdir -p .claude/commands
fi
echo "Commands:"
if [ "$AUDIT_MODE" = true ]; then
  printf "  %-25s %-12s %s\n" "Name" "Status" "Details"
  printf "  %-25s %-12s %s\n" "----" "------" "-------"
fi
for f in "$HEPH_SRC"/.claude/commands/*.md; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  if echo "$SKIP_COMMANDS" | grep -qw "$name"; then
    if [ "$AUDIT_MODE" = true ]; then
      printf "  %-25s %-12s %s\n" "$name" "protected" "project-specific (always skipped)"
    else
      : # orient.md handled in post-install validation
    fi
    continue
  fi
  link_item "../../.hephaestus/.claude/commands/$name" "$f" ".claude/commands/$name" "$name"
done
echo ""

# ── 4. Codex skills ──────────────────────────────────────────────────────────
if [ "$AUDIT_MODE" != true ]; then
  mkdir -p .codex/skills
fi
echo "Codex skills:"
if [ "$AUDIT_MODE" = true ]; then
  printf "  %-25s %-12s %s\n" "Name" "Status" "Details"
  printf "  %-25s %-12s %s\n" "----" "------" "-------"
fi
for d in "$HEPH_SRC"/.codex/skills/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  dest=".codex/skills/$name"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$AUDIT_MODE" = true ]; then
      printf "  %-25s %-12s %s\n" "$name" "conflict" "directory already exists"
    elif [ "$FORCE_MODE" = true ]; then
      rm -rf "$dest"
      ln -s "../../.hephaestus/.codex/skills/$name" "$dest"
      echo "  [replace] $name"
    else
      echo "  [skip] $name (already exists)"
      echo "         → replace: rm -rf $dest && re-run install.sh"
    fi
  else
    if [ "$AUDIT_MODE" = true ]; then
      printf "  %-25s %-12s %s\n" "$name" "new" "will symlink"
    else
      ln -s "../../.hephaestus/.codex/skills/$name" "$dest"
      echo "  [link] $name"
    fi
  fi
done
echo ""

# ── 5. Name collision check ─────────────────────────────────────────────────
COLLISIONS_FOUND=false
for target_dir_label in ".claude/commands:commands" ".claude/agents:agents"; do
  target_dir="${target_dir_label%%:*}"
  label="${target_dir_label##*:}"
  heph_dir="$HEPH_SRC/$target_dir"
  result=$(check_name_collisions "$target_dir" "$heph_dir" "$label" 2>/dev/null || true)
  if [ -n "$result" ]; then
    if [ "$COLLISIONS_FOUND" = false ]; then
      echo "Name collisions:"
      COLLISIONS_FOUND=true
    fi
    echo "$result"
  fi
done
if [ "$COLLISIONS_FOUND" = true ]; then
  echo ""
fi

# ── 6. Post-install validation ───────────────────────────────────────────────

if [ "$AUDIT_MODE" = true ]; then
  # In audit mode, just report orient.md and CLAUDE.md status
  if [ -e .claude/commands/orient.md ] || [ -L .claude/commands/orient.md ]; then
    printf "  %-25s %-12s %s\n" "orient.md" "exists" "project-specific (will keep yours)"
  else
    printf "  %-25s %-12s %s\n" "orient.md" "missing" "will scaffold from template"
  fi
  echo ""
  if [ -f CLAUDE.md ]; then
    if grep -qiE '^#{2,} .*(development commands|test(s|ing)?|lint(ing)?|build)' CLAUDE.md; then
      echo "[ok]   CLAUDE.md has development commands"
    else
      echo "[warn] CLAUDE.md missing test/lint/build commands"
    fi
  else
    echo "[warn] No CLAUDE.md found"
  fi
  echo ""
  echo "Audit complete. No changes were made."
  echo "Run without --audit to install, or with --force to replace existing files."
  exit 0
fi

# Scaffold orient.md if the target project doesn't have one
if [ ! -e .claude/commands/orient.md ] && [ ! -L .claude/commands/orient.md ]; then
  cp "$HEPH_SRC/templates/orient.md" .claude/commands/orient.md
  echo "[scaffold] orient.md (created template — customize for your project)"
else
  echo "[skip] orient.md (already exists)"
fi

# Check CLAUDE.md for Development Commands section
if [ -f CLAUDE.md ]; then
  if grep -qiE '^#{2,} .*(development commands|test(s|ing)?|lint(ing)?|build)' CLAUDE.md; then
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
echo "  nohup ./.hephaestus/loop.sh 30 autopilot.log &"
