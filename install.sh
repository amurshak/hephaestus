#!/usr/bin/env bash
# install.sh — Install hephaestus adapters
#
# Usage:
#   ./install.sh [--audit | --force | --clean]
#       User-level install (default). Symlinks shared commands and agents from
#       this clone into the harness config dirs. Run once per machine.
#
#   ./install.sh --project [--audit | --force] [path]
#       Scaffold the files a project owns: orient (Claude/OpenCode/Codex/
#       Hermes), AGENTS.md, opencode.json, .hermes/.gitignore. Once per repo.
#
#   ./install.sh --vendor [--audit | --force | --clean] [path]
#       --project, plus a copy of the shared adapters committed into the repo.
#       For teams that want the workflow version pinned alongside the code.
#
# Flags:
#   --audit    Show what would happen without modifying the filesystem
#   --force    Replace existing files hephaestus did not install
#   --clean    Remove adapters dropped upstream since the last install
#   --migrate  First remove a pre-2.2 `.hephaestus` submodule install from the
#              target repo, then install. Implies --project unless --vendor.
#
# Every install records what it wrote in a manifest, and reads that manifest on
# the next run — so re-installing updates its own files, never yours.
#   user-level: $XDG_STATE_HOME/hephaestus/manifest   vendored: <project>/.heph-manifest
#
# Harness config dirs honor $CLAUDE_CONFIG_DIR, $XDG_CONFIG_HOME, $CODEX_HOME,
# and $HERMES_HOME.
# Idempotent: safe to re-run.

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────
MODE=user
AUDIT_MODE=false
FORCE_MODE=false
CLEAN_MODE=false
MIGRATE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)    MODE=user; shift ;;
    --project) MODE=project; shift ;;
    --vendor)  MODE=vendor; shift ;;
    --audit)   AUDIT_MODE=true; shift ;;
    --force)   FORCE_MODE=true; shift ;;
    --clean)   CLEAN_MODE=true; shift ;;
    --migrate) MIGRATE=true; shift ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Error: unknown flag '$1'"; echo "Usage: ./install.sh [--user | --project | --vendor] [--audit | --force | --clean | --migrate] [path]"; exit 1 ;;
    *) break ;;
  esac
done

# Migration is inherently per-repo: the submodule lived in a project.
if [ "$MIGRATE" = true ] && [ "$MODE" = user ]; then
  MODE=project
fi

if [ "$AUDIT_MODE" = true ] && [ "$FORCE_MODE" = true ]; then
  echo "Error: --audit and --force cannot be used together."
  exit 1
fi
if [ "$AUDIT_MODE" = true ] && [ "$CLEAN_MODE" = true ]; then
  echo "Error: --audit and --clean cannot be used together."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$MODE" = user ] && [ $# -gt 0 ]; then
  echo "Error: a target path is only meaningful with --project or --vendor."
  echo "  User-level install (shared commands and agents):  ./install.sh"
  echo "  Project scaffold (orient, AGENTS.md):             ./install.sh --project $1"
  echo "  Project scaffold + committed adapter copies:      ./install.sh --vendor $1"
  exit 1
fi

TARGET="${1:-$(pwd)}"

if [ "$MODE" != user ]; then
  [ -d "$TARGET" ] || { echo "Error: target directory '$TARGET' does not exist."; exit 1; }
  # `.git` is a file, not a directory, in a git worktree — ask git instead.
  git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 \
    || { echo "Error: '$TARGET' is not a git repository."; exit 1; }
  TARGET="$(cd "$TARGET" && pwd)"
fi

# ── Destinations ─────────────────────────────────────────────────────────────
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
OPENCODE_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
HERMES_HOME_DIR="${HERMES_HOME:-$HOME/.hermes}"

if [ "$MODE" = vendor ]; then
  MANIFEST="$TARGET/.heph-manifest"
else
  MANIFEST="${XDG_STATE_HOME:-$HOME/.local/state}/hephaestus/manifest"
fi

# Adapter set, as "source_subdir|destination|kind" rows. Destination differs
# between user-level config dirs and a project checkout; the source never does.
adapter_rows() {
  if [ "$MODE" = user ]; then
    cat <<EOF
.claude/commands|$CLAUDE_HOME/commands|file
.claude/agents|$CLAUDE_HOME/agents|file
.opencode/commands|$OPENCODE_HOME/commands|file
.opencode/agents|$OPENCODE_HOME/agents|file
.agents/skills|$CODEX_HOME_DIR/skills|dir
.codex/agents|$CODEX_HOME_DIR/agents|file
.hermes/skills/hephaestus|$HERMES_HOME_DIR/skills/hephaestus|dir
.hermes/agents|$HERMES_HOME_DIR/agents|file
EOF
  else
    cat <<EOF
.claude/commands|$TARGET/.claude/commands|file
.claude/agents|$TARGET/.claude/agents|file
.opencode/commands|$TARGET/.opencode/commands|file
.opencode/agents|$TARGET/.opencode/agents|file
.agents/skills|$TARGET/.agents/skills|dir
.codex/agents|$TARGET/.codex/agents|file
.hermes/skills/hephaestus|$TARGET/.hermes/skills/hephaestus|dir
.hermes/agents|$TARGET/.hermes/agents|file
EOF
  fi
}

# ── Manifest ─────────────────────────────────────────────────────────────────
# Vendored manifests hold project-relative paths so the repo stays portable;
# user-level manifests hold absolute paths across three config dirs.

OLD_ENTRIES=""
NEW_ENTRIES=""
STALE_KEPT=""

manifest_key() {
  if [ "$MODE" = vendor ]; then echo "${1#"$TARGET"/}"; else echo "$1"; fi
}

manifest_path() {
  if [ "$MODE" = vendor ]; then echo "$TARGET/$1"; else echo "$1"; fi
}

load_manifest() {
  [ -f "$MANIFEST" ] || return 0
  OLD_ENTRIES=$(grep -v '^#' "$MANIFEST" 2>/dev/null || true)
}

was_installed() {
  [ -n "$OLD_ENTRIES" ] || return 1
  printf '%s\n' "$OLD_ENTRIES" | grep -qxF -- "$1"
}

record() {
  NEW_ENTRIES="${NEW_ENTRIES}$1
"
}

write_manifest() {
  [ "$AUDIT_MODE" != true ] || return 0
  mkdir -p "$(dirname "$MANIFEST")"
  {
    echo "# hephaestus $MODE install — regenerate with install.sh"
    echo "# version: $VERSION"
    echo "# source: $SCRIPT_DIR@$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    printf '%s' "$NEW_ENTRIES"
    printf '%s' "$STALE_KEPT"
  } > "$MANIFEST"
}

# ── Placement ────────────────────────────────────────────────────────────────

# place_item <source_abs> <dest> <name>
# User mode symlinks; vendor mode copies. Files this install owns (per the
# manifest) are refreshed; anything else is left alone unless --force.
place_item() {
  local source_abs="$1" dest="$2" name="$3"
  local key; key=$(manifest_key "$dest")

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    local ours=false
    was_installed "$key" && ours=true

    if [ "$AUDIT_MODE" = true ]; then
      if [ "$ours" = true ]; then
        printf "  %-25s %-12s %s\n" "$name" "update" "installed by hephaestus"
      elif [ -f "$dest" ] && [ -f "$source_abs" ]; then
        printf "  %-25s %-12s %s\n" "$name" "conflict" \
          "yours: $(wc -l < "$dest" | tr -d ' ') lines, hephaestus: $(wc -l < "$source_abs" | tr -d ' ') lines"
      else
        printf "  %-25s %-12s %s\n" "$name" "conflict" "exists, not installed by hephaestus"
      fi
      # --audit and --force are mutually exclusive, so a conflict stays theirs.
      [ "$ours" = true ] && record "$key"
      return 0
    fi

    if [ "$ours" = false ] && [ "$FORCE_MODE" != true ]; then
      echo "  [skip] $name (already exists, not installed by hephaestus)"
      echo "         → replace with --force, or compare: diff $dest $source_abs"
      return 0
    fi
    rm -rf "$dest"
    write_item "$source_abs" "$dest"
    record "$key"
    [ "$ours" = true ] && echo "  [update] $name" || echo "  [replace] $name"
    return 0
  fi

  if [ "$AUDIT_MODE" = true ]; then
    printf "  %-25s %-12s %s\n" "$name" "new" "$([ "$MODE" = user ] && echo "will symlink" || echo "will copy")"
  else
    write_item "$source_abs" "$dest"
    echo "  [install] $name"
  fi
  record "$key"
}

write_item() {
  local source_abs="$1" dest="$2"
  if [ "$MODE" = user ]; then
    ln -s "$source_abs" "$dest"
  elif [ -d "$source_abs" ]; then
    cp -R "$source_abs" "$dest"
  else
    cp "$source_abs" "$dest"
  fi
}

install_adapters() {
  while IFS='|' read -r src_sub dest_dir kind; do
    [ -n "$src_sub" ] || continue
    local src_dir="$SCRIPT_DIR/$src_sub"
    [ -d "$src_dir" ] || continue

    echo "$src_sub → $dest_dir"
    if [ "$AUDIT_MODE" = true ]; then
      printf "  %-25s %-12s %s\n" "Name" "Status" "Details"
    else
      mkdir -p "$dest_dir"
    fi

    local name
    if [ "$kind" = dir ]; then
      for d in "$src_dir"/*/; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        if [ "$name" = orient ]; then
          [ "$AUDIT_MODE" != true ] || printf "  %-25s %-12s %s\n" "$name" "protected" "project-specific"
          continue
        fi
        place_item "${d%/}" "$dest_dir/$name" "$name"
      done
    else
      for f in "$src_dir"/*; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        if [ "$name" = orient.md ]; then
          [ "$AUDIT_MODE" != true ] || printf "  %-25s %-12s %s\n" "$name" "protected" "project-specific"
          continue
        fi
        place_item "$f" "$dest_dir/$name" "$name"
      done
    fi
    echo ""
  done <<< "$(adapter_rows)"
}

# ── Stale adapters ───────────────────────────────────────────────────────────
# Anything the last install wrote that this one did not: renamed or removed
# upstream. The manifests make this exact — no guessing from symlink targets.

handle_stale() {
  [ -n "$OLD_ENTRIES" ] || return 0
  local stale=false key path
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    printf '%s' "$NEW_ENTRIES" | grep -qxF -- "$key" && continue
    path=$(manifest_path "$key")
    { [ -e "$path" ] || [ -L "$path" ]; } || continue
    stale=true
    if [ "$CLEAN_MODE" = true ]; then
      rm -rf "$path"
      echo "  [cleaned] $key (dropped upstream)"
    else
      # Keep the record so a later --clean can still find it.
      STALE_KEPT="${STALE_KEPT}${key}
"
      echo "  [stale] $key (dropped upstream)"
    fi
  done <<< "$OLD_ENTRIES"

  if [ "$stale" = true ]; then
    [ "$CLEAN_MODE" = true ] || echo "  Run with --clean to remove."
    echo ""
  elif [ "$CLEAN_MODE" = true ]; then
    echo "  (no stale adapters found)"
    echo ""
  fi
}

# ── Legacy submodule migration ───────────────────────────────────────────────
# Pre-2.2 installs put hephaestus in a `.hephaestus` submodule and symlinked
# every adapter through it. Those links dangle in a git worktree, which is why
# the layout was dropped. Removing them is safe: the shared set now comes from
# the user-level install (or --vendor), and nothing project-owned points into
# `.hephaestus/`.

migrate_legacy() {
  local found=false f target dir

  echo "Legacy submodule install:"

  for dir in .claude/agents .claude/commands .opencode/agents .opencode/commands \
             .agents/skills .codex/agents .hermes/skills/hephaestus .hermes/agents; do
    [ -d "$TARGET/$dir" ] || continue
    for f in "$TARGET/$dir"/*; do
      [ -L "$f" ] || continue
      target=$(readlink "$f")
      case "$target" in *.hephaestus/*) ;; *) continue ;; esac
      found=true
      if [ "$AUDIT_MODE" = true ]; then
        printf "  %-25s %-12s %s\n" "$(basename "$f")" "legacy link" "$dir → $target"
      else
        rm "$f"
        echo "  [removed] $dir/$(basename "$f")"
      fi
    done
  done

  if [ -e "$TARGET/.hephaestus" ] || grep -qF '.hephaestus' "$TARGET/.gitmodules" 2>/dev/null; then
    found=true
    if [ "$AUDIT_MODE" = true ]; then
      printf "  %-25s %-12s %s\n" ".hephaestus" "submodule" "will be deinitialized and removed"
    else
      git -C "$TARGET" submodule deinit -f .hephaestus >/dev/null 2>&1 || true
      # `git rm` also drops the .gitmodules entry; fall back for an unregistered dir.
      git -C "$TARGET" rm -f --quiet .hephaestus >/dev/null 2>&1 || rm -rf "$TARGET/.hephaestus"
      # rev-parse reports the git dir relative to the repo, not to our cwd.
      local gitdir; gitdir=$(cd "$TARGET" && git rev-parse --git-common-dir)
      case "$gitdir" in /*) ;; *) gitdir="$TARGET/$gitdir" ;; esac
      rm -rf "$gitdir/modules/.hephaestus"
      # `git rm` strips the section but leaves the file; drop it if it is now empty.
      if [ -f "$TARGET/.gitmodules" ] && [ ! -s "$TARGET/.gitmodules" ]; then
        git -C "$TARGET" rm -f --quiet .gitmodules >/dev/null 2>&1 || rm -f "$TARGET/.gitmodules"
      fi
      echo "  [removed] .hephaestus submodule"
    fi
  fi

  if [ "$found" = false ]; then
    echo "  (nothing to migrate — no .hephaestus submodule or legacy symlinks found)"
  fi
  echo ""
}

# ── Project scaffold (project + vendor) ──────────────────────────────────────

# scaffold <source> <dest> <label> — copy only when absent; never overwrite.
scaffold() {
  local source_abs="$1" dest="$2" label="$3"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$AUDIT_MODE" = true ]; then
      printf "  %-25s %-12s %s\n" "$label" "exists" "project-specific (will keep yours)"
    else
      echo "  [skip] $label (already exists)"
    fi
  elif [ "$AUDIT_MODE" = true ]; then
    printf "  %-25s %-12s %s\n" "$label" "missing" "will scaffold from template"
  else
    mkdir -p "$(dirname "$dest")"
    cp "$source_abs" "$dest"
    echo "  [scaffold] $label (customize for your project)"
  fi
}

scaffold_project() {
  echo "Project files:"
  scaffold "$SCRIPT_DIR/templates/orient.md" "$TARGET/.claude/commands/orient.md" "orient.md"
  scaffold "$SCRIPT_DIR/templates/orient.md" "$TARGET/.opencode/commands/orient.md" "opencode orient.md"

  if [ -e "$TARGET/.agents/skills/orient/SKILL.md" ]; then
    if [ "$AUDIT_MODE" = true ]; then
      printf "  %-25s %-12s %s\n" "codex orient skill" "exists" "project-specific (will keep yours)"
    else
      echo "  [skip] codex orient skill (already exists)"
    fi
  elif [ "$AUDIT_MODE" = true ]; then
    printf "  %-25s %-12s %s\n" "codex orient skill" "missing" "will scaffold from template"
  else
    mkdir -p "$TARGET/.agents/skills/orient"
    {
      echo "---"
      echo "name: orient"
      echo "description: Orient in this project — load context, sync repo state, and find the next piece of work. Use for /orient requests."
      echo "---"
      echo ""
      cat "$SCRIPT_DIR/templates/orient.md"
    } > "$TARGET/.agents/skills/orient/SKILL.md"
    echo "  [scaffold] codex orient skill (customize for your project)"
  fi

  if [ -e "$TARGET/.hermes/skills/hephaestus/orient/SKILL.md" ]; then
    if [ "$AUDIT_MODE" = true ]; then
      printf "  %-25s %-12s %s\n" "hermes orient skill" "exists" "project-specific (will keep yours)"
    else
      echo "  [skip] hermes orient skill (already exists)"
    fi
  elif [ "$AUDIT_MODE" = true ]; then
    printf "  %-25s %-12s %s\n" "hermes orient skill" "missing" "will scaffold from template"
  else
    mkdir -p "$TARGET/.hermes/skills/hephaestus/orient"
    {
      echo "---"
      echo "name: orient"
      echo "description: \"Orient in this project — context, repo state, next work.\""
      echo "platforms: [linux, macos, windows]"
      echo "metadata:"
      echo "  hermes:"
      echo "    category: hephaestus"
      echo "    tags: [hephaestus, delivery, orient]"
      echo "    requires_toolsets: [terminal]"
      echo "    related_skills: []"
      echo "---"
      echo ""
      cat "$SCRIPT_DIR/templates/orient.md"
    } > "$TARGET/.hermes/skills/hephaestus/orient/SKILL.md"
    echo "  [scaffold] hermes orient skill (customize for your project)"
  fi

  # Running Hermes with HERMES_HOME=<project>/.hermes makes this the profile
  # home, dropping config, credentials, sessions and memories into the working
  # tree. Only the generated adapters belong in git.
  if [ -e "$TARGET/.hermes/.gitignore" ]; then
    if [ "$AUDIT_MODE" = true ]; then
      printf "  %-25s %-12s %s\n" ".hermes/.gitignore" "exists" "project-specific (will keep yours)"
    else
      echo "  [skip] .hermes/.gitignore (already exists)"
    fi
  elif [ "$AUDIT_MODE" = true ]; then
    printf "  %-25s %-12s %s\n" ".hermes/.gitignore" "missing" "will scaffold"
  else
    mkdir -p "$TARGET/.hermes"
    cat > "$TARGET/.hermes/.gitignore" <<'EOF'
# Only the generated hephaestus adapters are tracked. Everything else here is
# Hermes profile state (config, credentials, sessions, memories) if you run with
# HERMES_HOME pointed at this directory — never commit it.
*
!.gitignore
!skills/
!skills/**
!agents/
!agents/**
EOF
    echo "  [scaffold] .hermes/.gitignore (tracks adapters only, never profile state)"
  fi

  scaffold "$SCRIPT_DIR/templates/AGENTS.md" "$TARGET/AGENTS.md" "AGENTS.md"

  if [ -e "$TARGET/opencode.json" ]; then
    if [ "$AUDIT_MODE" = true ]; then
      printf "  %-25s %-12s %s\n" "opencode.json" "exists" "project-specific (will keep yours)"
    else
      echo "  [skip] opencode.json (already exists)"
    fi
  elif [ "$AUDIT_MODE" = true ]; then
    printf "  %-25s %-12s %s\n" "opencode.json" "missing" "will scaffold"
  else
    cat > "$TARGET/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["AGENTS.md", "CLAUDE.md"]
}
EOF
    echo "  [scaffold] opencode.json (loads AGENTS.md + CLAUDE.md)"
  fi
  echo ""
}

check_dev_commands() {
  if [ -f "$TARGET/CLAUDE.md" ]; then
    if grep -qiE '^#{2,} .*(development commands|test(s|ing)?|lint(ing)?|build)' "$TARGET/CLAUDE.md"; then
      echo "[ok]   CLAUDE.md has development commands"
      return 0
    fi
    echo "[warn] CLAUDE.md missing test/lint/build commands"
  else
    echo "[warn] No CLAUDE.md found"
  fi
  echo "       Hephaestus reads these development commands to run quality gates. Add them:"
  echo "       cat $SCRIPT_DIR/templates/CLAUDE.md.snippet >> $TARGET/CLAUDE.md"
  return 1
}

# ── Health check ─────────────────────────────────────────────────────────────

health_check() {
  echo "Health check:"

  if [ "$MODE" != project ]; then
    local installed=0 broken=0 key
    while IFS= read -r key; do
      [ -n "$key" ] || continue
      if [ -e "$(manifest_path "$key")" ]; then installed=$((installed + 1)); else broken=$((broken + 1)); fi
    done <<< "$NEW_ENTRIES"

    if [ "$broken" -eq 0 ]; then
      echo "  ✓ $installed hephaestus adapters installed"
    else
      echo "  ✗ $broken broken adapter link(s) — re-run with --clean"
    fi
  fi

  command -v gh >/dev/null 2>&1 \
    && echo "  ✓ gh CLI available" \
    || echo "  ✗ gh CLI not found — hephaestus commands use gh for issues and PRs"

  if [ "$MODE" != user ]; then
    [ -e "$TARGET/.claude/commands/orient.md" ] && echo "  ✓ orient.md present" || echo "  ✗ orient.md missing"
    [ -e "$TARGET/AGENTS.md" ] && echo "  ✓ AGENTS.md present" || echo "  ✗ AGENTS.md missing"
  fi

  # A scaffolded project still needs the shared set from somewhere.
  if [ "$MODE" = project ]; then
    if [ -e "$CLAUDE_HOME/commands/ship.md" ]; then
      echo "  ✓ shared commands found at user level"
    else
      echo "  ✗ no shared commands at user level — run: $SCRIPT_DIR/install.sh"
    fi
  fi

  # Every command declares the agents it launches; verify they landed.
  # Project mode installs no adapters — the shared set lives at user level.
  if [ "$MODE" = project ]; then echo ""; return 0; fi
  local deps_ok=true cmd_dir agent_dir
  if [ "$MODE" = user ]; then
    cmd_dir="$CLAUDE_HOME/commands"; agent_dir="$CLAUDE_HOME/agents"
  else
    cmd_dir="$TARGET/.claude/commands"; agent_dir="$TARGET/.claude/agents"
  fi
  if [ -d "$cmd_dir" ]; then
    for cmd in "$cmd_dir"/*.md; do
      [ -e "$cmd" ] || continue
      local requires missing=""
      requires=$(grep -m1 -oE '<!-- requires:[^>]*-->' "$cmd" 2>/dev/null | sed -E 's|<!-- requires: *||; s| *-->||' || true)
      { [ -n "$requires" ] && [ "$requires" != none ]; } || continue
      IFS=', ' read -ra agents <<< "$requires"
      for agent in "${agents[@]}"; do
        agent=$(echo "$agent" | tr -d ' ')
        [ -n "$agent" ] || continue
        [ -e "$agent_dir/${agent}.md" ] || missing="${missing:+$missing, }$agent"
      done
      if [ -n "$missing" ]; then
        echo "  ✗ $(basename "$cmd") requires: $requires — missing: $missing"
        deps_ok=false
      fi
    done
  fi
  [ "$deps_ok" = true ] && echo "  ✓ all command dependencies satisfied"
  echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────

VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown")

if [ "$AUDIT_MODE" = true ]; then
  echo "Audit: hephaestus $VERSION ($MODE install) — no changes will be made"
else
  echo "Installing hephaestus $VERSION ($MODE)"
fi
echo "  Source: $SCRIPT_DIR"
[ "$MODE" = user ] || echo "  Target: $TARGET"
echo ""

if [ "$MIGRATE" = true ]; then
  migrate_legacy
fi

if [ "$MODE" != project ]; then
  load_manifest
  install_adapters
  handle_stale
  write_manifest
fi

if [ "$MODE" != user ]; then
  scaffold_project
  check_dev_commands || true
  echo ""
fi

if [ "$AUDIT_MODE" = true ]; then
  echo "Audit complete. No changes were made."
  echo "Run without --audit to install, or with --force to replace existing files."
  exit 0
fi

health_check

echo "Done. Next steps:"
if [ "$MODE" = user ]; then
  echo "  1. Commands are available in every project: /autopilot, /ship, /finish, …"
  echo "  2. Prepare a project:  $SCRIPT_DIR/install.sh --project /path/to/project"
  echo "  3. Update later:       $SCRIPT_DIR/update.sh"
else
  echo "  1. Customize .claude/commands/orient.md (and the OpenCode/Codex copies you use)"
  echo "  2. Add project-specific .claude/hooks/ (lint-on-commit.sh, protect-files.sh)"
  echo "  3. Update AGENTS.md to list newly available agents"
  if [ "$MODE" = vendor ]; then
    echo "  4. git add .heph-manifest .claude .opencode .agents .codex .hermes/skills .hermes/agents .hermes/.gitignore opencode.json AGENTS.md && git commit"
  else
    echo "  4. git add .claude .opencode .agents .hermes/skills .hermes/.gitignore opencode.json AGENTS.md && git commit"
  fi
fi
echo ""
echo "Optional — headless autonomous loop (fresh session per run, from the project root):"
echo "  nohup $SCRIPT_DIR/loop.sh 30 autopilot.log &"
echo "  HEPH_HARNESS=opencode nohup $SCRIPT_DIR/loop.sh 30 autopilot-oc.log &"
