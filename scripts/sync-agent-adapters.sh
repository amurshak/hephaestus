#!/usr/bin/env bash
# sync-agent-adapters.sh — Generate/check tool-specific workflow adapters.
#
# Canonical workflow specs live in .ai/workflows/*.md and canonical agent
# definitions in .ai/agents/*.md. This script generates Claude command wrappers
# from workflow frontmatter and Claude agent adapters from the agent
# definitions so adapter metadata cannot drift.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOWS_DIR="$ROOT/.ai/workflows"
AI_AGENTS_DIR="$ROOT/.ai/agents"
CLAUDE_COMMANDS_DIR="$ROOT/.claude/commands"
CLAUDE_AGENTS_DIR="$ROOT/.claude/agents"
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

# The Claude render is the identity render: the spec schema is already Claude
# dialect, so the adapter is the source plus a generated-from header after the
# frontmatter (the frontmatter itself must stay first for Claude Code to parse).
render_claude_agent() {
  local agent=$1
  local name start

  name=$(field "$agent" "name")
  start=$(body_start_line "$agent")

  if [ -z "$name" ] || [ -z "$start" ]; then
    echo "ERR: invalid agent frontmatter in $agent" >&2
    return 1
  fi

  {
    sed -n "1,$((start - 1))p" "$agent"
    echo "<!-- generated from .ai/agents/${name}.md; do not edit directly -->"
    sed -n "${start},\$p" "$agent"
  }
}

drift=0
expected=""
for workflow in "$WORKFLOWS_DIR"/*.md; do
  [ -e "$workflow" ] || continue
  name=$(field "$workflow" "name")
  if [ -z "$name" ]; then
    echo "ERR: missing name in $workflow" >&2
    drift=1
    continue
  fi
  expected="$expected ${name}.md"

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

expected_agents=""
for agent in "$AI_AGENTS_DIR"/*.md; do
  [ -e "$agent" ] || continue
  name=$(field "$agent" "name")
  if [ -z "$name" ]; then
    echo "ERR: missing name in $agent" >&2
    drift=1
    continue
  fi
  expected_agents="$expected_agents ${name}.md"

  target="$CLAUDE_AGENTS_DIR/${name}.md"
  if [ "$MODE" = "--check" ]; then
    if [ ! -f "$target" ]; then
      echo "ERR: missing Claude agent adapter $target" >&2
      drift=1
      continue
    fi
    tmp=$(mktemp "${TMPDIR:-/tmp}/heph-adapter-XXXXXX")
    render_claude_agent "$agent" > "$tmp" || { drift=1; rm -f "$tmp"; continue; }
    if ! diff -u "$target" "$tmp" >/dev/null; then
      echo "ERR: Claude agent adapter drift for $name" >&2
      diff -u "$target" "$tmp" >&2
      drift=1
    fi
    rm -f "$tmp"
  else
    render_claude_agent "$agent" > "$target" || drift=1
  fi
done

# Stale adapters: generated files whose source workflow was renamed or deleted.
# In sync mode, skip when any source failed to parse — an unparseable source is
# not a deleted one, and deleting its adapter would destroy a live command.
[ "$MODE" = "sync" ] && [ "$drift" -ne 0 ] && exit 1
for adapter in "$CLAUDE_COMMANDS_DIR"/*.md; do
  [ -e "$adapter" ] || continue
  base=$(basename "$adapter")
  case " $expected " in
    *" $base "*) ;;
    *)
      # Only sweep files this generator wrote. An unmarked file is the user's.
      if ! grep -q "generated from .ai/workflows/" "$adapter"; then
        echo "ERR: unexpected non-generated file $adapter in .claude/commands — move it or remove it manually" >&2
        drift=1
      elif [ "$MODE" = "--check" ]; then
        echo "ERR: stale Claude adapter $adapter (no matching workflow in $WORKFLOWS_DIR)" >&2
        drift=1
      else
        rm -f "$adapter"
        echo "✗ removed stale Claude adapter $adapter"
      fi
      ;;
  esac
done

for adapter in "$CLAUDE_AGENTS_DIR"/*.md; do
  [ -e "$adapter" ] || continue
  base=$(basename "$adapter")
  case " $expected_agents " in
    *" $base "*) ;;
    *)
      # Only sweep files this generator wrote. An unmarked file is the user's.
      if ! grep -q "generated from .ai/agents/" "$adapter"; then
        echo "ERR: unexpected non-generated file $adapter in .claude/agents — move it or remove it manually" >&2
        drift=1
      elif [ "$MODE" = "--check" ]; then
        echo "ERR: stale Claude agent adapter $adapter (no matching agent in $AI_AGENTS_DIR)" >&2
        drift=1
      else
        rm -f "$adapter"
        echo "✗ removed stale Claude agent adapter $adapter"
      fi
      ;;
  esac
done

if [ "$MODE" = "--check" ]; then
  [ "$drift" -eq 0 ] && echo "✓ agent adapters in sync"
  exit "$drift"
fi

# A reported error must not be masked by a success line (matches Codex/Hermes).
[ "$drift" -ne 0 ] && exit 1
echo "✓ agent adapters generated"
