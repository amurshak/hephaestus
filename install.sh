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
#       Hermes/Cursor), AGENTS.md, opencode.json, .hermes/.gitignore. Once per repo.
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
#   --changelog-fragments
#              Adopt one-changelog-entry-per-PR: scaffold changelog.d/, a
#              CHANGELOG.md if absent, scripts/collect-changelog.sh, and
#              `CHANGELOG.md merge=union` in .gitattributes. Opt-in, because it
#              changes where /ship writes. Once adopted, later runs keep it.
#
# Every install records what it wrote in a manifest, and reads that manifest on
# the next run — so re-installing updates its own files, never yours.
#   user-level: $XDG_STATE_HOME/hephaestus/manifest   vendored: <project>/.heph-manifest
#
# Harness config dirs honor $CLAUDE_CONFIG_DIR, $XDG_CONFIG_HOME, $CODEX_HOME,
# $HERMES_HOME, and $CURSOR_HOME.
# Idempotent: safe to re-run.

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────
MODE=user
AUDIT_MODE=false
FORCE_MODE=false
CLEAN_MODE=false
MIGRATE=false
CHANGELOG_FRAGMENTS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)    MODE=user; shift ;;
    --project) MODE=project; shift ;;
    --vendor)  MODE=vendor; shift ;;
    --audit)   AUDIT_MODE=true; shift ;;
    --force)   FORCE_MODE=true; shift ;;
    --clean)   CLEAN_MODE=true; shift ;;
    --migrate) MIGRATE=true; shift ;;
    --changelog-fragments) CHANGELOG_FRAGMENTS=true; shift ;;
    # Track the header rather than a line range — a hardcoded range silently
    # truncates --help every time the block grows.
    -h|--help) awk 'NR>1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    -*) echo "Error: unknown flag '$1'"; echo "Usage: ./install.sh [--user | --project | --vendor] [--audit | --force | --clean | --migrate | --changelog-fragments] [path]"; exit 1 ;;
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
if [ "$CHANGELOG_FRAGMENTS" = true ] && [ "$MODE" = user ]; then
  echo "Error: --changelog-fragments scaffolds a repo, so it needs --project or --vendor."
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
CURSOR_HOME_DIR="${CURSOR_HOME:-$HOME/.cursor}"

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
.cursor/commands|$CURSOR_HOME_DIR/commands|file
.cursor/agents|$CURSOR_HOME_DIR/agents|file
.cursor/rules|$CURSOR_HOME_DIR/rules|file
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
.cursor/commands|$TARGET/.cursor/commands|file
.cursor/agents|$TARGET/.cursor/agents|file
.cursor/rules|$TARGET/.cursor/rules|file
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

# scaffold_text <dest> <label> <hint> — like scaffold(), with the body on stdin.
scaffold_text() {
  local dest="$1" label="$2" hint="$3"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$AUDIT_MODE" = true ]; then
      printf "  %-25s %-12s %s\n" "$label" "exists" "project-specific (will keep yours)"
    else
      echo "  [skip] $label (already exists)"
    fi
  elif [ "$AUDIT_MODE" = true ]; then
    printf "  %-25s %-12s %s\n" "$label" "missing" "will scaffold"
  else
    mkdir -p "$(dirname "$dest")"
    cat > "$dest"
    echo "  [scaffold] $label ($hint)"
  fi
}

scaffold_project() {
  echo "Project files:"
  scaffold "$SCRIPT_DIR/templates/orient.md" "$TARGET/.claude/commands/orient.md" "orient.md"
  scaffold "$SCRIPT_DIR/templates/orient.md" "$TARGET/.opencode/commands/orient.md" "opencode orient.md"
  scaffold "$SCRIPT_DIR/templates/orient.md" "$TARGET/.cursor/commands/orient.md" "cursor orient.md"

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

# ── Changelog fragments (opt-in) ─────────────────────────────────────────────
# One entry per PR as its own file, so parallel branches never edit a shared
# anchor. Opt-in via --changelog-fragments because it changes where /ship
# writes — unlike orient or AGENTS.md, which only add. Adoption is then read
# back from the repo, so later runs (update.sh included) carry it forward
# without repeating the flag.
#
# Project mode writes no manifest, so adoption has to be inferred — and a path
# alone is not evidence. Both marks must be present, and the collect script
# must carry our header before anything overwrites it: a repo with its own
# scripts/collect-changelog.sh is not an adopter, and its file is never ours
# to replace. scriv claims changelog.d/ but ships no such script, so the pair
# excludes it too.
#
# The distributed copy is stamped with the clone version it came from and the
# checksum of the pristine source. A bare token proves only "we wrote this",
# which conflates two states with opposite handling: upstream shipped a fix
# (ours to refresh, nothing to lose) versus the operator edited our copy (never
# overwrite unasked). The checksum separates them, so an untouched copy self-
# heals on the next update and an edited one is preserved until --force.
COLLECT_TOKEN='# hephaestus:collect-changelog'
COLLECT_MARKER="^${COLLECT_TOKEN}([[:space:]]|\$)"

# ours <file> — true when <file> carries the provenance token, stamped or bare.
collect_is_ours() { [ -f "$1" ] && grep -qE "$COLLECT_MARKER" "$1" 2>/dev/null; }

# Checksum of <file> with its stamp line reduced to the bare token, so a copy's
# hash is comparable to the source's across version stamps.
# Each returns empty for a file that is absent or unreadable rather than
# failing: under `set -euo pipefail` a bare sed on a missing path takes the
# whole run down, and these are called before the copy exists.
collect_sum() {
  [ -f "$1" ] || return 0
  sed "s|^${COLLECT_TOKEN}.*|${COLLECT_TOKEN}|" "$1" \
    | { shasum 2>/dev/null || sha1sum; } | cut -c1-12
}

# The sha= / v… recorded in a distributed copy; empty when the copy is unstamped.
collect_recorded_sum() { [ -f "$1" ] || return 0; sed -n "s|^${COLLECT_TOKEN} .*sha=\([0-9a-f]*\).*|\1|p" "$1" | head -1; }
collect_recorded_ver() { [ -f "$1" ] || return 0; sed -n "s|^${COLLECT_TOKEN} v\([^ ]*\).*|\1|p" "$1" | head -1; }

# Copy the clone's script into place, stamping the token line as it lands.
write_collect() {
  local src="$1" dest="$2" sum
  sum=$(collect_sum "$src")
  mkdir -p "$(dirname "$dest")"
  rm -f "$dest"
  sed "s|^${COLLECT_TOKEN}\$|${COLLECT_TOKEN} v${VERSION} sha=${sum}|" "$src" > "$dest"
  chmod +x "$dest"
}

changelog_adopted() {
  [ -d "$TARGET/changelog.d" ] && collect_is_ours "$TARGET/scripts/collect-changelog.sh"
}

scaffold_changelog() {
  local src="$SCRIPT_DIR/scripts/collect-changelog.sh"
  local dest="$TARGET/scripts/collect-changelog.sh"
  local label="collect-changelog.sh" status

  # stale    — ours, provably untouched, and the clone has moved: refresh freely.
  # modified — ours, but edited since we wrote it: never overwrite without --force.
  # legacy   — ours from before stamping, and differing; edited or stale is now
  #            indistinguishable, so it keeps the old --force handling. An
  #            identical legacy copy is simply restamped, and self-heals after.
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then  status=new
  elif ! collect_is_ours "$dest"; then           status=foreign
  else
    local recorded; recorded=$(collect_recorded_sum "$dest")
    if [ -z "$recorded" ]; then
      cmp -s "$src" "$dest" 2>/dev/null && status=restamp || status=legacy
    elif [ "$recorded" != "$(collect_sum "$dest")" ]; then
      status=modified
    elif [ "$recorded" != "$(collect_sum "$src")" ]; then
      status=stale
    else
      status=current
    fi
  fi

  echo "Changelog fragments:"

  # A same-named script we did not write means the project already has release
  # tooling there. Refuse the whole adoption rather than scaffolding the other
  # three files around a collect script that will never be installed — that
  # half-state points /ship at changelog.d/ with nothing able to fold it.
  if [ "$status" = foreign ]; then
    echo "  [skip] $label is yours, not written by hephaestus — adoption declined."
    echo "         Nothing was scaffolded. Move your script aside to adopt fragments."
    echo ""
    return 0
  fi

  # scriv also claims changelog.d/, keeping the category in the fragment body —
  # no <id>.<category>.md rename target exists, and the files are not ours to
  # rewrite. Warn while any unfoldable file remains, not just on the run that
  # adopts; dotfiles like .gitkeep are placeholders, not fragments. Test the
  # captured output, not grep -qv's exit code — BSD grep exits 0 there on
  # empty input where GNU exits 1.
  if [ -n "$(ls "$TARGET/changelog.d" 2>/dev/null | grep -v '^README\.md$' \
               | grep -Ev '\.(added|changed|fixed|removed)\.md$')" ]; then
    echo "  [warn] changelog.d/ holds files another tool may own."
    echo "         collect-changelog.sh folds only <id>.<category>.md — --check rejects other .md names and never sees the rest."
    echo "         Fold them with the tool that wrote them (scriv: 'scriv collect') — see changelog.d/README.md."
  fi

  if [ ! -f "$SCRIPT_DIR/changelog.d/README.md" ]; then
    echo "  [skip] changelog.d/README.md (missing from this clone)"
  else
    scaffold_text "$TARGET/changelog.d/README.md" "changelog.d/README.md" "how to write a fragment" \
      < "$SCRIPT_DIR/changelog.d/README.md"
  fi

  scaffold_text "$TARGET/CHANGELOG.md" "CHANGELOG.md" "fragments are folded in here at release" <<'EOF'
# Changelog

All notable changes to this project are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Entries are written as fragments in `changelog.d/` and folded into a dated
section by `scripts/collect-changelog.sh <version>` at release.

## Unreleased
EOF

  # collect-changelog.sh splices the new section in at `## Unreleased` and dies
  # without it. Say so now rather than at release, when it blocks a cut.
  if [ -f "$TARGET/CHANGELOG.md" ] && ! grep -q '^## Unreleased' "$TARGET/CHANGELOG.md"; then
    echo "  [warn] CHANGELOG.md has no '## Unreleased' heading — add one, or the release fold fails."
  fi

  # Our own copy is code, not a customization point, so an untouched one is
  # refreshed on sight — that is what makes `update.sh` carry a fix into an
  # adopted project without --force, whose blast radius reaches hand-edited
  # adapters the operator never asked to replace. Local edits still hold it.
  if [ "$AUDIT_MODE" = true ]; then
    case "$status" in
      new)      printf "  %-25s %-12s %s\n" "$label" "missing"  "will copy from the clone" ;;
      current)  printf "  %-25s %-12s %s\n" "$label" "current"  "matches this clone" ;;
      stale)    printf "  %-25s %-12s %s\n" "$label" "stale"    "unmodified — will refresh to $VERSION" ;;
      restamp)  printf "  %-25s %-12s %s\n" "$label" "unstamped" "matches this clone — will stamp $VERSION" ;;
      modified) printf "  %-25s %-12s %s\n" "$label" "modified" "edited locally (--force to overwrite)" ;;
      legacy)   printf "  %-25s %-12s %s\n" "$label" "unstamped" "differs from this clone (--force to refresh)" ;;
    esac
  elif [ "$status" = new ] || [ "$status" = stale ] || [ "$status" = restamp ] \
       || { { [ "$status" = modified ] || [ "$status" = legacy ]; } && [ "$FORCE_MODE" = true ]; }; then
    local was; was=$(collect_recorded_ver "$dest")
    write_collect "$src" "$dest"
    case "$status" in
      new)     echo "  [scaffold] $label (fold at release: scripts/collect-changelog.sh <version>)" ;;
      stale)   echo "  [update] $label (${was:-unstamped} → $VERSION, unmodified copy refreshed)" ;;
      restamp) echo "  [ok] $label (up to date — stamped $VERSION)" ;;
      *)       echo "  [update] $label (overwritten by --force)" ;;
    esac
  elif [ "$status" = modified ]; then
    echo "  [skip] $label (edited locally since we wrote it — --force to overwrite)"
  elif [ "$status" = legacy ]; then
    echo "  [skip] $label (differs from this clone — refresh with --force)"
  else
    echo "  [ok] $label (up to date)"
  fi

  # A union merge on CHANGELOG.md is the backstop for any direct edit that slips
  # past the fragment convention. An existing .gitattributes stays the project's.
  if [ ! -e "$TARGET/.gitattributes" ]; then
    scaffold_text "$TARGET/.gitattributes" ".gitattributes" "union merge on CHANGELOG.md" <<'EOF'
CHANGELOG.md merge=union
EOF
  elif grep -q '^CHANGELOG\.md[[:space:]]\{1,\}merge=union' "$TARGET/.gitattributes"; then
    [ "$AUDIT_MODE" = true ] \
      && printf "  %-25s %-12s %s\n" ".gitattributes" "current" "already sets merge=union" \
      || echo "  [ok] .gitattributes (already sets CHANGELOG.md merge=union)"
  else
    [ "$AUDIT_MODE" = true ] \
      && printf "  %-25s %-12s %s\n" ".gitattributes" "exists" "add: CHANGELOG.md merge=union" \
      || echo "  [skip] .gitattributes (yours) — add the backstop: echo 'CHANGELOG.md merge=union' >> .gitattributes"
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
    if changelog_adopted; then
      echo "  ✓ changelog fragments enabled — /ship writes changelog.d/<id>.<category>.md"
    elif collect_is_ours "$TARGET/scripts/collect-changelog.sh"; then
      # Our collect script without changelog.d/ reads as un-adopted, so /ship
      # would silently go back to editing CHANGELOG.md directly.
      echo "  ✗ changelog.d/ missing — re-run with --changelog-fragments"
    fi
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
  if [ "$CHANGELOG_FRAGMENTS" = true ] || changelog_adopted; then
    scaffold_changelog
  fi
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
  CHANGELOG_PATHS=""
  changelog_adopted && CHANGELOG_PATHS=" changelog.d scripts/collect-changelog.sh CHANGELOG.md .gitattributes"
  if [ "$MODE" = vendor ]; then
    echo "  4. git add .heph-manifest .claude .opencode .agents .codex .hermes/skills .hermes/agents .hermes/.gitignore opencode.json AGENTS.md$CHANGELOG_PATHS && git commit"
  else
    echo "  4. git add .claude .opencode .agents .hermes/skills .hermes/.gitignore opencode.json AGENTS.md$CHANGELOG_PATHS && git commit"
  fi
fi
echo ""
echo "Optional — headless autonomous loop (fresh session per run, from the project root):"
echo "  nohup $SCRIPT_DIR/loop.sh 30 autopilot.log &"
echo "  HEPH_HARNESS=codex nohup $SCRIPT_DIR/loop.sh 30 autopilot-codex.log &   # claude|codex|cursor|hermes|opencode"
