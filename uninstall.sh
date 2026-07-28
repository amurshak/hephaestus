#!/usr/bin/env bash
# uninstall.sh — Remove hephaestus adapters
#
# Usage:
#   ./uninstall.sh                  Remove the user-level install
#   ./uninstall.sh --vendor <path>  Remove a project's vendored copies
#
# Removes exactly what the matching install recorded in its manifest, so files
# hephaestus never wrote are never touched. Project-owned files always stay:
# orient (all harnesses), AGENTS.md, opencode.json, .claude/hooks/, CLAUDE.md.
#
# Idempotent: safe to run if already uninstalled.

# Intentionally omit -e: cleanup should continue past individual failures.
set -uo pipefail

MODE=user
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vendor) MODE=vendor; shift ;;
    -*) echo "Error: unknown flag '$1'"; echo "Usage: ./uninstall.sh [--vendor <path>]"; exit 1 ;;
    *) TARGET="$1"; shift ;;
  esac
done

if [ "$MODE" = vendor ]; then
  TARGET="${TARGET:-$(pwd)}"
  MANIFEST="$TARGET/.heph-manifest"
  LABEL="vendored hephaestus adapters from $TARGET"
else
  MANIFEST="${XDG_STATE_HOME:-$HOME/.local/state}/hephaestus/manifest"
  LABEL="user-level hephaestus adapters"
fi

if [ ! -f "$MANIFEST" ]; then
  echo "No hephaestus install found (no manifest at $MANIFEST)."
  if [ "$MODE" = user ]; then
    echo "  For a project's vendored copy, run: ./uninstall.sh --vendor <path>"
  else
    echo "  For the user-level install, run: ./uninstall.sh"
  fi
  exit 0
fi

echo "Removing $LABEL"
echo ""

REMOVED=0
while IFS= read -r entry; do
  case "$entry" in ''|'#'*) continue ;; esac
  [ "$MODE" = vendor ] && path="$TARGET/$entry" || path="$entry"
  if [ -e "$path" ] || [ -L "$path" ]; then
    rm -rf "$path"
    echo "  [removed] $entry"
    REMOVED=$((REMOVED + 1))
  fi
done < "$MANIFEST"
rm -f "$MANIFEST"

# Drop directories the adapters left empty; keep any holding project files.
if [ "$MODE" = vendor ]; then
  for d in .claude/commands .claude/agents .opencode/commands .opencode/agents \
           .agents/skills .codex/agents .hermes/skills/hephaestus .hermes/skills \
           .hermes/agents .claude .opencode .agents .codex; do
    rmdir "$TARGET/$d" 2>/dev/null || true
  done
else
  rmdir "$(dirname "$MANIFEST")" 2>/dev/null || true
  for d in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents" \
           "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/commands" "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/agents" \
           "${CODEX_HOME:-$HOME/.codex}/skills" "${CODEX_HOME:-$HOME/.codex}/agents" \
           "${HERMES_HOME:-$HOME/.hermes}/skills/hephaestus" "${HERMES_HOME:-$HOME/.hermes}/agents"; do
    rmdir "$d" 2>/dev/null || true
  done
fi

echo ""
echo "Done. Removed $REMOVED file(s)."
echo ""
echo "Kept (project-owned):"
echo "  - orient (.claude/commands/, .opencode/commands/, .agents/skills/orient/, .hermes/skills/hephaestus/orient/)"
echo "  - AGENTS.md, opencode.json, CLAUDE.md"
echo "  - .claude/hooks/, .claude/settings.local.json"
