#!/usr/bin/env bash
# sync-opencode-adapters.sh — Generate/check OpenCode command and agent adapters.
#
# Canonical workflow specs live in .ai/workflows/*.md. Claude agent definitions
# remain the source of truth for shared subagent prompts. This script renders
# OpenCode-compatible adapters from those sources so adapter metadata cannot drift.
#
# OpenCode-localizations applied at generate time (Claude adapters stay Claude-native):
#   - worktree/subagent prose → Task tool / @agent mentions + serialize-edits
#   - chain notes so nested /commands load full templates instead of paraphrased

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOWS_DIR="$ROOT/.ai/workflows"
CLAUDE_AGENTS_DIR="$ROOT/.claude/agents"
OPENCODE_COMMANDS_DIR="$ROOT/.opencode/commands"
OPENCODE_AGENTS_DIR="$ROOT/.opencode/agents"
MODE="${1:-sync}"

if [ "$MODE" != "sync" ] && [ "$MODE" != "--check" ]; then
  echo "Usage: $0 [--check]" >&2
  exit 2
fi

# shellcheck source=scripts/models.sh
. "$ROOT/scripts/models.sh"
models_load || exit 1

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

# Rewrite Claude-dialect body text for OpenCode mechanics.
opencode_localize_body() {
  sed \
    -e 's/parallel coder subagents (in worktrees)/parallel @coder Task invocations (serialize file edits — no worktree isolation)/g' \
    -e 's/coder subagents (in worktrees)/@coder Task invocations (serialize file edits — no worktree isolation)/g' \
    -e 's/parallel coder subagents/parallel @coder Task invocations/g' \
    -e 's/coder subagent(s)/@coder agent(s)/g' \
    -e 's/coder subagents/@coder agents/g' \
    -e 's/explorer subagent(s)/@explorer agent(s)/g' \
    -e 's/explorer subagents/@explorer agents/g' \
    -e 's/reviewer subagent(s)/@reviewer agent(s)/g' \
    -e 's/reviewer subagents/@reviewer agents/g' \
    -e 's/tester subagent(s)/@tester agent(s)/g' \
    -e 's/tester subagents/@tester agents/g' \
    -e 's/researcher subagent(s)/@researcher agent(s)/g' \
    -e 's/researcher subagents/@researcher agents/g' \
    -e 's/subagent(s)/agent(s) (Task tool or @mention)/g' \
    -e 's/subagents/agents (Task tool or @mention)/g' \
    -e 's/subagent/agent (Task tool or @mention)/g' \
    -e 's/TodoWrite/the todo tools/g' \
    -e 's/seeded Claude Code session/seeded OpenCode session/g' \
    -e 's|claude --permission-mode default |opencode --prompt |g' \
    -e 's|&& claude "|\&\& opencode --prompt "|g' \
    -e 's|`--permission-mode default` prevents spawned sessions inheriting plan mode and stalling|`--prompt` seeds the spawned session with the command|g' \
    -e "s/Claude Code's title rewrites/the TUI's title rewrites/g"
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

  # Localize before truncating — the description is what OpenCode routes on,
  # so Claude dialect must not survive in it (or ride in on a later reflow).
  desc=$(first_body_line "$workflow" "$start" | opencode_localize_body)
  desc=$(yaml_quote "${desc:0:180}")

  {
    echo "---"
    echo "description: \"$desc\""
    echo "---"
    echo "<!-- requires: ${requires} -->"
    echo "<!-- chains: ${chains} -->"
    echo "<!-- generated from .ai/workflows/${name}.md; do not edit directly -->"
    echo ""
    if [ "$chains" != "none" ]; then
      echo "> **OpenCode:** start from the project root that contains \`.opencode/\`. Invoke nested workflows as slash commands (${chains}) so their full templates load — do not paraphrase. Spawn role agents with the Task tool or @mentions."
    else
      echo "> **OpenCode:** start from the project root that contains \`.opencode/\`. Spawn role agents with the Task tool or @mentions when required."
    fi
    echo ""
    sed -n "${start},\$p" "$workflow" | opencode_localize_body
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
    echo "  bash: allow"
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
  local name description tools isolation tier model start

  name=$(field "$agent" "name")
  description=$(field "$agent" "description")
  tools=$(field "$agent" "tools")
  isolation=$(field "$agent" "isolation")
  tier=$(field "$agent" "model")
  start=$(body_start_line "$agent")

  if [ -z "$name" ] || [ -z "$description" ] || [ -z "$tools" ] || [ -z "$start" ]; then
    echo "ERR: invalid Claude agent frontmatter in $agent" >&2
    return 1
  fi

  models_validate_tier "$tier" "$agent" || return 1
  model=$(models_lookup "opencode" "$tier" "model")

  # OpenCode has no worktree isolation; surface that where the orchestrator
  # decides to parallelize (description) and where the agent runs (body).
  if [ "$isolation" = "worktree" ]; then
    description="$description NOTE: OpenCode has no worktree isolation — parallel ${name} agents share one working tree; serialize file-modifying tasks."
  fi
  description=$(yaml_quote "$description")

  {
    echo "---"
    echo "# generated from .claude/agents/${name}.md; do not edit directly"
    echo "description: \"$description\""
    echo "mode: subagent"
    [ -n "$model" ] && echo "model: $model"
    render_permission "$tools"
    echo "---"
    echo ""
    if [ "$isolation" = "worktree" ]; then
      echo "> **No worktree isolation.** The Claude version of this agent runs in an isolated git worktree; OpenCode has no equivalent. Parallel ${name} agents edit the same working tree — serialize file-modifying tasks."
      echo ""
    fi
    sed -n "${start},\$p" "$agent" | opencode_localize_body
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

# Stale adapters: generated files whose source was renamed or deleted.
check_stale() {
  local dir=$1 expected=$2 source_dir=$3
  local adapter base rc=0 marker
  # Files this generator wrote carry the source path; anything else is the user's.
  marker="generated from ${source_dir#"$ROOT"/}/"
  for adapter in "$dir"/*.md; do
    [ -e "$adapter" ] || continue
    base=$(basename "$adapter")
    case " $expected " in
      *" $base "*) ;;
      *)
        if ! grep -q "$marker" "$adapter"; then
          echo "ERR: unexpected non-generated file $adapter in ${dir#"$ROOT"/} — move it or remove it manually" >&2
          rc=1
        elif [ "$MODE" = "--check" ]; then
          echo "ERR: stale OpenCode adapter $adapter (no matching source in $source_dir)" >&2
          rc=1
        else
          rm -f "$adapter"
          echo "✗ removed stale OpenCode adapter $adapter"
        fi
        ;;
    esac
  done
  return "$rc"
}

drift=0
expected_commands=""
expected_agents=""

for workflow in "$WORKFLOWS_DIR"/*.md; do
  [ -e "$workflow" ] || continue
  name=$(field "$workflow" "name")
  if [ -z "$name" ]; then
    echo "ERR: missing name in $workflow" >&2
    drift=1
    continue
  fi
  expected_commands="$expected_commands ${name}.md"
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
  expected_agents="$expected_agents ${name}.md"
  target="$OPENCODE_AGENTS_DIR/${name}.md"
  tmp=$(mktemp "${TMPDIR:-/tmp}/heph-opencode-agent-XXXXXX")
  render_opencode_agent "$agent" > "$tmp" || { drift=1; rm -f "$tmp"; continue; }
  check_or_write "$target" "$tmp" "@$name" || drift=1
  rm -f "$tmp"
done

# In sync mode, skip stale removal when any source failed to parse — an
# unparseable source is not a deleted one, and deleting its adapter would
# destroy a live command or agent.
[ "$MODE" = "sync" ] && [ "$drift" -ne 0 ] && exit 1
check_stale "$OPENCODE_COMMANDS_DIR" "$expected_commands" "$WORKFLOWS_DIR" || drift=1
check_stale "$OPENCODE_AGENTS_DIR" "$expected_agents" "$CLAUDE_AGENTS_DIR" || drift=1

if [ "$MODE" = "--check" ]; then
  [ "$drift" -eq 0 ] && echo "✓ OpenCode adapters in sync"
  exit "$drift"
fi

# A reported error must not be masked by a success line (matches Codex/Hermes).
[ "$drift" -ne 0 ] && exit 1
echo "✓ OpenCode adapters generated"
