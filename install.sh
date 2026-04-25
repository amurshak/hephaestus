#!/usr/bin/env bash
# install.sh — Set up hephaestus submodule and symlinks in a target project
#
# Usage:
#   ./install.sh [--audit | --force | --clean] <target_project_path>
#
# Flags:
#   --audit   Show what would happen without modifying the filesystem
#   --force   Replace existing files with hephaestus symlinks
#   --clean   Remove dangling symlinks pointing to .hephaestus/
#
# What it does:
#   1. Adds this repo as a git submodule at <target>/.hephaestus
#   2. Symlinks shared agents into <target>/.claude/agents/
#   3. Symlinks shared commands into <target>/.claude/commands/
#   4. Scaffolds orient.md template if missing
#   5. Validates CLAUDE.md has development commands
#
# Idempotent: safe to re-run. Never overwrites existing files (unless --force).

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────
AUDIT_MODE=false
FORCE_MODE=false
CLEAN_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --audit) AUDIT_MODE=true; shift ;;
    --force) FORCE_MODE=true; shift ;;
    --clean) CLEAN_MODE=true; shift ;;
    -*) echo "Error: unknown flag '$1'"; echo "Usage: ./install.sh [--audit | --force | --clean] <target>"; exit 1 ;;
    *) break ;;
  esac
done

if [ "$AUDIT_MODE" = true ] && [ "$FORCE_MODE" = true ]; then
  echo "Error: --audit and --force cannot be used together."
  exit 1
fi

if [ "$AUDIT_MODE" = true ] && [ "$CLEAN_MODE" = true ]; then
  echo "Error: --audit and --clean cannot be used together."
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

# Link or audit a single item. Usage: link_item <source_symlink_path> <source_abs> <dest> <name>
# source_symlink_path: relative symlink target (e.g., ../../.hephaestus/agents/coder.md)
# source_abs: absolute path to the hephaestus source file (for audit line counts)
# dest: path in target project
# name: display name
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
      echo "         → compare: diff $dest .hephaestus/$dest"
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
    # Skip symlinks pointing into .hephaestus (these are ours, not the user's)
    if [ -L "$target_file" ] && [[ "$(readlink "$target_file")" == *".hephaestus/"* ]]; then
      continue
    fi
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
  if [ -e ".hephaestus/.git" ] || grep -q '\.hephaestus' .gitmodules 2>/dev/null; then
    echo "[ok]   .hephaestus submodule already registered"
  else
    echo "[new]  .hephaestus submodule will be added"
  fi
  echo ""
else
  if [ -e ".hephaestus/.git" ] || grep -q '\.hephaestus' .gitmodules 2>/dev/null; then
    echo "[skip] .hephaestus submodule already registered"
    # Only initialize if not yet checked out (e.g., fresh clone without --recurse-submodules).
    # Do NOT run `git submodule update` here — it resets to the committed pointer,
    # undoing any `git submodule update --remote` the developer just did.
    if [ ! -e ".hephaestus/.git" ]; then
      git submodule update --init .hephaestus
    fi
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
for f in "$HEPH_SRC"/agents/*.md; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  link_item "../../.hephaestus/agents/$name" "$f" ".claude/agents/$name" "$name"
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
for f in "$HEPH_SRC"/commands/*.md; do
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
  link_item "../../.hephaestus/commands/$name" "$f" ".claude/commands/$name" "$name"
done
echo ""

# ── 4. Name collision check ─────────────────────────────────────────────────
COLLISIONS_FOUND=false
for target_dir_label in ".claude/commands:commands" ".claude/agents:agents"; do
  target_dir="${target_dir_label%%:*}"
  label="${target_dir_label##*:}"
  heph_dir="$HEPH_SRC/$label"
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

# ── 5. Stale symlink detection ────────────────────────────────────────────────
# Find symlinks pointing into .hephaestus/ whose target no longer exists (e.g., after upstream renames/removals)

detect_stale_links() {
  local dir="$1"
  [ -d "$dir" ] || return 0

  for f in "$dir"/*; do
    # Check for symlinks (including broken ones — -L works on broken symlinks, -e does not)
    [ -L "$f" ] || continue
    local link_target
    link_target=$(readlink "$f")
    [[ "$link_target" == *".hephaestus/"* ]] || continue
    # If the symlink target doesn't exist, it's stale
    if [ ! -e "$f" ]; then
      local name
      name=$(basename "$f")
      if [ "$CLEAN_MODE" = true ]; then
        rm "$f"
        echo "  [cleaned] $name → $link_target (target removed)"
      else
        echo "  [stale] $name → $link_target (target removed)"
        echo "          → remove: rm $f"
      fi
      STALE_FOUND=true
    fi
  done
}

STALE_FOUND=false
detect_stale_links ".claude/agents"
detect_stale_links ".claude/commands"

if [ "$STALE_FOUND" = true ]; then
  echo ""
  echo "Stale symlinks found (targets removed upstream)."
  if [ "$CLEAN_MODE" != true ]; then
    echo "  Run with --clean to auto-remove."
  fi
  echo ""
elif [ "$CLEAN_MODE" = true ]; then
  echo "  (no stale symlinks found)"
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
    echo ""
    echo "       Or append the full hephaestus snippet:"
    echo "       cat .hephaestus/templates/CLAUDE.md.snippet >> CLAUDE.md"
  fi
else
  echo ""
  echo "[warn] No CLAUDE.md found"
  echo "       Hephaestus reads CLAUDE.md to discover test/lint/build commands."
  echo "       Create one and append the hephaestus snippet:"
  echo "       cat .hephaestus/templates/CLAUDE.md.snippet >> CLAUDE.md"
fi
echo ""

# ── 7. Health check ──────────────────────────────────────────────────────────
echo ""
echo "Health check:"

# Validate symlinks
VALID_LINKS=0
BROKEN_LINKS=0
for dir in .claude/agents .claude/commands; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*; do
    [ -L "$f" ] || continue
    link_target=$(readlink "$f")
    [[ "$link_target" == *".hephaestus/"* ]] || continue
    if [ -e "$f" ]; then
      VALID_LINKS=$((VALID_LINKS + 1))
    else
      BROKEN_LINKS=$((BROKEN_LINKS + 1))
    fi
  done
done
if [ "$BROKEN_LINKS" -eq 0 ]; then
  echo "  ✓ $VALID_LINKS hephaestus symlinks valid"
else
  echo "  ✗ $BROKEN_LINKS broken symlink(s) — run with --clean to fix"
fi

# Check gh CLI
if command -v gh >/dev/null 2>&1; then
  echo "  ✓ gh CLI available"
else
  echo "  ✗ gh CLI not found — hephaestus commands use gh for issues and PRs"
fi

# orient.md
if [ -e .claude/commands/orient.md ]; then
  echo "  ✓ orient.md present"
else
  echo "  ✗ orient.md missing"
fi

# CLAUDE.md dev commands (already checked above, just summarize)
if [ -f CLAUDE.md ] && grep -qiE '^#{2,} .*(development commands|test(s|ing)?|lint(ing)?|build)' CLAUDE.md; then
  echo "  ✓ CLAUDE.md has development commands"
else
  echo "  ✗ CLAUDE.md missing development commands"
fi

# Validate command → agent dependencies
# Commands declare dependencies via <!-- requires: agent1, agent2 --> on line 1
DEPS_OK=true
if [ -d .claude/commands ]; then
  for cmd in .claude/commands/*.md; do
    [ -e "$cmd" ] || continue
    requires=$(head -1 "$cmd" | sed -n 's/^<!-- requires: \(.*\) -->/\1/p')
    [ -n "$requires" ] || continue
    [ "$requires" != "none" ] || continue
    missing=""
    IFS=', ' read -ra agents <<< "$requires"
    for agent in "${agents[@]}"; do
      agent=$(echo "$agent" | tr -d ' ')
      if [ ! -e ".claude/agents/${agent}.md" ] && [ ! -L ".claude/agents/${agent}.md" ]; then
        missing="${missing:+$missing, }$agent"
      fi
    done
    if [ -n "$missing" ]; then
      cmd_name=$(basename "$cmd")
      echo "  ✗ $cmd_name requires: $requires — missing: $missing"
      DEPS_OK=false
    fi
  done
fi
if [ "$DEPS_OK" = true ]; then
  echo "  ✓ all command dependencies satisfied"
fi
echo ""

echo "Done. Next steps:"
echo "  1. Customize .claude/commands/orient.md for your project"
echo "  2. Add project-specific .claude/hooks/ (lint-on-commit.sh, protect-files.sh)"
echo "  3. Update AGENTS.md to list newly available agents"
echo "  4. git add .gitmodules .hephaestus .claude && git commit"
echo ""
echo "Optional — headless autonomous loop (fresh session per run):"
echo "  nohup ./.hephaestus/loop.sh 30 autopilot.log &"
