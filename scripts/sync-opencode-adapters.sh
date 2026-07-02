#!/usr/bin/env bash
# sync-opencode-adapters.sh — Generate/check OpenCode command and agent adapters.
#
# Canonical workflow specs live in .ai/workflows/*.md. Claude agent definitions
# remain the source of truth for shared subagent prompts. This script renders
# OpenCode-compatible adapters from those sources so adapter metadata cannot drift.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOWS_DIR="$ROOT/.ai/workflows"
CLAUDE_AGENTS_DIR="$ROOT/.claude/agents"
OPENCODE_COMMANDS_DIR="$ROOT/.opencode/commands"
OPENCODE_AGENTS_DIR="$ROOT/.opencode/agent"
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

yaml_quote() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

first_body_line() {
  local file=$1 start=$2
  awk -v start="$start" 'NR >= start && NF { print; exit }' "$file"
}

render_opencode_command() {
  local workflow=$1
  local name requires chains start desc

  name=$(field "$workflow" "name")
  requires=$(field "$workflow" "requires")
  chains=$(field "$workflow" "chains")
  start=$(body_start_line "$workflow")

  if [ -z "$name" ] || [ -z "$requires" ] || [ -z "$chains" ] || [ -z "$start" ]; then
    echo "ERR: invalid workflow frontmatter in $workflow" >&2
    return 1
  fi

  desc=$(first_body_line "$workflow" "$start")
  desc=$(yaml_quote "${desc:0:180}")

  {
    echo "---"
    echo "description: \"$desc\""
    echo "---"
    echo "<!-- requires: ${requires} -->"
    echo "<!-- chains: ${chains} -->"
    echo "<!-- generated from .ai/workflows/${name}.md; do not edit directly -->"
    echo ""
    sed -n "${start},\$p" "$workflow"
  }
}

render_permission() {
  local tools=$1

  echo "permission:"
  echo "  read: allow"
  echo "  glob: allow"
  echo "  grep: allow"
  echo "  list: allow"

  if [[ "$tools" == *"Edit"* ]] || [[ "$tools" == *"Write"* ]]; then
    echo "  edit: allow"
  else
    echo "  edit: deny"
  fi

  if [[ "$tools" == *"Bash"* ]]; then
    echo "  bash: ask"
  else
    echo "  bash: deny"
  fi

  if [[ "$tools" == *"WebFetch"* ]]; then
    echo "  webfetch: allow"
  fi
  if [[ "$tools" == *"WebSearch"* ]]; then
    echo "  websearch: allow"
  fi
}

render_opencode_agent() {
  local agent=$1
  local name description tools start

  name=$(field "$agent" "name")
  description=$(field "$agent" "description")
  tools=$(field "$agent" "tools")
  start=$(body_start_line "$agent")

  if [ -z "$name" ] || [ -z "$description" ] || [ -z "$tools" ] || [ -z "$start" ]; then
    echo "ERR: invalid Claude agent frontmatter in $agent" >&2
    return 1
  fi

  description=$(yaml_quote "$description")

  {
    echo "---"
    echo "# generated from .claude/agents/${name}.md; do not edit directly"
    echo "description: \"$description\""
    echo "mode: subagent"
    render_permission "$tools"
    echo "---"
    echo ""
    sed -n "${start},\$p" "$agent"
  }
}

check_or_write() {
  local target=$1 tmp=$2 label=$3

  if [ "$MODE" = "--check" ]; then
    if [ ! -f "$target" ]; then
      echo "ERR: missing OpenCode adapter $target" >&2
      return 1
    fi
    if ! diff -u "$target" "$tmp" >/dev/null; then
      echo "ERR: OpenCode adapter drift for $label" >&2
      diff -u "$target" "$tmp" >&2
      return 1
    fi
  else
    mkdir -p "$(dirname "$target")"
    cp "$tmp" "$target"
  fi
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
  target="$OPENCODE_COMMANDS_DIR/${name}.md"
  tmp=$(mktemp "${TMPDIR:-/tmp}/heph-opencode-command-XXXXXX")
  render_opencode_command "$workflow" > "$tmp" || { drift=1; rm -f "$tmp"; continue; }
  check_or_write "$target" "$tmp" "/$name" || drift=1
  rm -f "$tmp"
done

for agent in "$CLAUDE_AGENTS_DIR"/*.md; do
  [ -e "$agent" ] || continue
  name=$(field "$agent" "name")
  if [ -z "$name" ]; then
    echo "ERR: missing name in $agent" >&2
    drift=1
    continue
  fi
  target="$OPENCODE_AGENTS_DIR/${name}.md"
  tmp=$(mktemp "${TMPDIR:-/tmp}/heph-opencode-agent-XXXXXX")
  render_opencode_agent "$agent" > "$tmp" || { drift=1; rm -f "$tmp"; continue; }
  check_or_write "$target" "$tmp" "@$name" || drift=1
  rm -f "$tmp"
done

if [ "$MODE" = "--check" ]; then
  [ "$drift" -eq 0 ] && echo "✓ OpenCode adapters in sync"
  exit "$drift"
fi

echo "✓ OpenCode adapters generated"
