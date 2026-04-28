#!/usr/bin/env bash
# sync-agent-adapters.sh — Generate/check tool-specific workflow adapters.
#
# Canonical workflow specs live in .ai/workflows/*.md. This script generates
# Claude command wrappers from their frontmatter so adapter metadata cannot drift.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOWS_DIR="$ROOT/.ai/workflows"
CLAUDE_COMMANDS_DIR="$ROOT/.claude/commands"
MODE="${1:-sync}"

if [ "$MODE" != "sync" ] && [ "$MODE" != "--check" ]; then
  echo "Usage: $0 [--check]" >&2
  exit 2
fi

field() {
  local file=$1 key=$2
  awk -F': *' -v key="$key" '
    /^---$/ { if (++f == 2) exit; next }
    f == 1 && $1 == key { sub(/^[^:]+: */, ""); print; exit }
  ' "$file"
}

body_start_line() {
  local file=$1
  awk '/^---$/ { if (++f == 2) { print NR + 1; exit } }' "$file"
}

render_claude_wrapper() {
  local workflow=$1
  local name requires chains start

  name=$(field "$workflow" "name")
  requires=$(field "$workflow" "requires")
  chains=$(field "$workflow" "chains")
  start=$(body_start_line "$workflow")

  if [ -z "$name" ] || [ -z "$requires" ] || [ -z "$chains" ] || [ -z "$start" ]; then
    echo "ERR: invalid workflow frontmatter in $workflow" >&2
    return 1
  fi

  {
    echo "<!-- requires: ${requires} -->"
    echo "<!-- chains: ${chains} -->"
    echo "<!-- generated from .ai/workflows/${name}.md; do not edit directly -->"
    echo ""
    sed -n "${start},\$p" "$workflow"
  }
}

drift=0
for workflow in "$WORKFLOWS_DIR"/*.md; do
  [ -e "$workflow" ] || continue
  name=$(field "$workflow" "name")
  if [ -z "$name" ]; then
    echo "ERR: missing name in $workflow" >&2
    drift=1
    continue
  fi

  target="$CLAUDE_COMMANDS_DIR/${name}.md"
  if [ "$MODE" = "--check" ]; then
    if [ ! -f "$target" ]; then
      echo "ERR: missing Claude adapter $target" >&2
      drift=1
      continue
    fi
    tmp=$(mktemp "${TMPDIR:-/tmp}/heph-adapter-XXXXXX")
    render_claude_wrapper "$workflow" > "$tmp" || { drift=1; rm -f "$tmp"; continue; }
    if ! diff -u "$target" "$tmp" >/dev/null; then
      echo "ERR: Claude adapter drift for /$name" >&2
      diff -u "$target" "$tmp" >&2
      drift=1
    fi
    rm -f "$tmp"
  else
    render_claude_wrapper "$workflow" > "$target" || drift=1
  fi
done

if [ "$MODE" = "--check" ]; then
  [ "$drift" -eq 0 ] && echo "✓ agent adapters in sync"
  exit "$drift"
fi

echo "✓ agent adapters generated"
