#!/usr/bin/env bash
# sync-cursor-adapters.sh — Generate/check Cursor command, subagent, and rule adapters.
#
# Canonical workflow specs live in .ai/workflows/*.md. Claude agent definitions
# remain the source of truth for shared subagent prompts. This script renders
# Cursor-compatible adapters from those sources so adapter metadata cannot drift:
#   .ai/workflows/<name>.md   → .cursor/commands/<name>.md   (Cursor slash command)
#   .claude/agents/<name>.md  → .cursor/agents/<name>.md     (Cursor subagent)
#   both of the above         → .cursor/rules/hephaestus.mdc (always-apply project rule)
#
# Cursor mechanics that shape the output:
#   - Cursor injects .cursor/commands/*.md verbatim and strips YAML frontmatter
#     only from imported .claude/commands files, so command adapters carry none.
#   - Cursor substitutes $ARGUMENTS and $1..$n in commands, so the placeholder
#     is preserved as-is (unlike the Codex adapters, which must explain it).
#   - The command hover preview is the first non-blank line, so the workflow's
#     own opening line leads and the metadata comments follow it.
#   - Cursor subagents have no worktree isolation; they share one working tree.
#   - Cursor's subagent parser does not unquote values, so they are emitted bare.
#     `readonly: true` is honoured (permissionMode READONLY) but only sandboxes
#     the shell; `tools` is only rendered as prose for the model, so it is not
#     used as an access control.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOWS_DIR="$ROOT/.ai/workflows"
CLAUDE_AGENTS_DIR="$ROOT/.claude/agents"
CURSOR_COMMANDS_DIR="$ROOT/.cursor/commands"
CURSOR_AGENTS_DIR="$ROOT/.cursor/agents"
CURSOR_RULES_DIR="$ROOT/.cursor/rules"
RULE_NAME="hephaestus.mdc"
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

# Line number of the first non-blank body line — the command's hover preview.
first_body_line_no() {
  local file=$1 start=$2
  awk -v start="$start" 'NR >= start && NF { print NR; exit }' "$file"
}

# Rewrite Claude-dialect body text for Cursor mechanics. Cursor has subagents and
# a to-do list, so only the worktree isolation and the todo tool need remapping.
cursor_localize_body() {
  sed \
    -e 's/coder subagents (in worktrees)/coder subagents (serialize file edits — Cursor subagents share one working tree)/g' \
    -e 's/TodoWrite/the to-do list/g' \
    -e 's/seeded Claude Code session/seeded Cursor session/g' \
    -e 's|claude --permission-mode default |cursor-agent |g' \
    -e 's|&& claude "|\&\& cursor-agent "|g' \
    -e 's|`--permission-mode default` prevents spawned sessions inheriting plan mode and stalling|the positional prompt seeds the spawned session with the command|g' \
    -e "s/Claude Code's title rewrites/the TUI's title rewrites/g"
}

render_cursor_command() {
  local workflow=$1
  local name requires chains start desc_line

  name=$(field "$workflow" "name")
  requires=$(field "$workflow" "requires")
  chains=$(field "$workflow" "chains")
  start=$(body_start_line "$workflow")
  [ -n "$start" ] && desc_line=$(first_body_line_no "$workflow" "$start")

  if [ -z "$name" ] || [ -z "$requires" ] || [ -z "$chains" ] || [ -z "${desc_line:-}" ]; then
    echo "ERR: invalid workflow frontmatter in $workflow" >&2
    return 1
  fi

  {
    sed -n "${desc_line}p" "$workflow" | cursor_localize_body
    echo ""
    echo "<!-- requires: ${requires} -->"
    echo "<!-- chains: ${chains} -->"
    echo "<!-- generated from .ai/workflows/${name}.md; do not edit directly -->"
    echo ""
    if [ "$chains" != "none" ]; then
      echo "> **Cursor:** run from the project root that contains \`.cursor/\`. Invoke nested workflows as slash commands (${chains}) so their full templates load — do not paraphrase. Delegate to the subagents in \`.cursor/agents/\`; they share one working tree, so serialize file-modifying tasks."
    else
      echo "> **Cursor:** run from the project root that contains \`.cursor/\`. Delegate to the subagents in \`.cursor/agents/\`; they share one working tree, so serialize file-modifying tasks."
    fi
    echo ""
    sed -n "$((desc_line + 1)),\$p" "$workflow" | cursor_localize_body
  }
}

# `readonly: true` maps to permissionMode READONLY. Measured on Cursor 3.13.21
# (2026-07-28) rather than assumed — a probe subagent reported its tool list and
# then tried to write both ways:
#   - the shell runs, but under a read-only filesystem sandbox: a shell write
#     fails with "operation not permitted"
#   - `Shell` and `Write` both stay in the tool list; only `SwitchMode` is dropped
#   - the write *tool* bypasses the sandbox and succeeds
# So READONLY constrains the shell and nothing else. It is safe for any role that
# never needs to write, and fatal to one whose shell must (see `shell: write`).
# Because the write tool still works, this is a guard rail, not a sandbox — the
# emitted prose must not claim more than that.
render_readonly() {
  local tools=$1 shell=$2
  if [[ "$tools" == *"Edit"* ]] || [[ "$tools" == *"Write"* ]] || [ "$shell" = "write" ]; then
    echo "no"
  else
    echo "yes"
  fi
}

# Roles Claude Code denies edit tools. Those with a shell rely on instruction.
render_advisory_readonly() {
  local tools=$1
  if [[ "$tools" == *"Edit"* ]] || [[ "$tools" == *"Write"* ]]; then
    echo "no"
  else
    echo "yes"
  fi
}

render_cursor_agent() {
  local agent=$1
  local name description tools isolation tier model shell start

  name=$(field "$agent" "name")
  description=$(field "$agent" "description")
  tools=$(field "$agent" "tools")
  isolation=$(field "$agent" "isolation")
  tier=$(field "$agent" "model")
  shell=$(field "$agent" "shell")
  start=$(body_start_line "$agent")

  if [ -z "$name" ] || [ -z "$description" ] || [ -z "$tools" ] || [ -z "$start" ]; then
    echo "ERR: invalid Claude agent frontmatter in $agent" >&2
    return 1
  fi

  models_validate_tier "$tier" "$agent" || return 1
  model=$(models_lookup "cursor" "$tier" "model")

  # Cursor has no worktree isolation; surface that where the orchestrator decides
  # to parallelize (description) and where the agent runs (body).
  if [ "$isolation" = "worktree" ]; then
    description="$description NOTE: Cursor has no worktree isolation — parallel ${name} subagents share one working tree; serialize file-modifying tasks."
  fi
  # Cursor splits on the first ':' and does not unquote, so a quoted value would
  # reach the model with its quotes attached. Emit the description bare.
  description=$(printf '%s' "$description" | tr '\n' ' ')

  {
    echo "---"
    echo "# generated from .claude/agents/${name}.md; do not edit directly"
    echo "name: ${name}"
    echo "description: ${description}"
    [ -n "$model" ] && echo "model: $model"
    [ "$(render_readonly "$tools" "$shell")" = "yes" ] && echo "readonly: true"
    echo "---"
    echo ""
    if [ "$(render_advisory_readonly "$tools")" = "yes" ]; then
      if [ "$(render_readonly "$tools" "$shell")" = "yes" ]; then
        echo "> **Read-only.** \`readonly: true\` sandboxes your shell — a shell write fails with \`operation not permitted\`. It does **not** withhold the write tools, and those bypass the sandbox: do not use them."
      else
        echo "> **Read-only by instruction.** Your shell must stay writable, so nothing is sandboxed: do not modify files."
      fi
      echo ""
    fi
    if [ "$isolation" = "worktree" ]; then
      echo "> **No worktree isolation.** The Claude version of this agent runs in an isolated git worktree; Cursor has no equivalent. Parallel ${name} subagents edit the same working tree — serialize file-modifying tasks."
      echo ""
    fi
    sed -n "${start},\$p" "$agent" | cursor_localize_body
  }
}

# The always-apply rule carries what Cursor cannot infer from the adapters alone:
# the workflow graph, and how Claude-native mechanics map onto Cursor. Quality
# gates and retry limits stay in CLAUDE.md — restating them here would drift.
render_cursor_rule() {
  local chain_rows=$1

  echo "---"
  echo "description: Hephaestus delivery workflow — how its commands, subagents, and chains work in this project"
  echo "alwaysApply: true"
  echo "---"
  echo "<!-- generated from .ai/workflows/ and .claude/agents/; do not edit directly -->"
  echo ""
  echo "# Hephaestus"
  echo ""
  echo "Delivery runs a fixed loop — orient, plan, critique, implement, review, test, ship, finish. Slash commands in \`.cursor/commands/\` drive it; the subagents in \`.cursor/agents/\` absorb the verbose work. Quality gates, retry limits, and autonomy rules live in \`CLAUDE.md\` — read it there rather than assuming."
  echo ""
  echo "## Chains"
  echo ""
  echo "A command that chains another must load that command's file and follow it — never paraphrase it from memory."
  echo ""
  echo "| Command | Chains |"
  echo "| --- | --- |"
  printf '%s' "$chain_rows"
  echo ""
  echo "## Cursor mapping"
  echo ""
  echo "- **Subagents, no worktrees.** Under Claude Code the \`coder\` agent runs in an isolated git worktree. Cursor subagents share one working tree — serialize file-modifying tasks."
  echo "- **Least privilege is only partly enforced.** \`researcher\`, \`reviewer\`, and \`explorer\` carry \`readonly: true\`, which sandboxes their shell — shell writes fail. It does not withhold the write tools, and those bypass the sandbox, so file writes still rest on instruction. \`tester\` is exempt: its shell must write for tests to run. \`tools:\` is prose to Cursor, not an access control."
  echo "- **Commands are injected verbatim.** Cursor strips YAML frontmatter only from imported \`.claude/commands\` files, so these adapters carry none. \`\$ARGUMENTS\` and \`\$1\`… are substituted."
  echo "- **Never hand-edit \`.cursor/\`.** Edit \`.ai/workflows/\` and \`.claude/agents/\` in the hephaestus clone, then run \`scripts/sync-cursor-adapters.sh\`."
}

check_or_write() {
  local target=$1 tmp=$2 label=$3

  if [ "$MODE" = "--check" ]; then
    if [ ! -f "$target" ]; then
      echo "ERR: missing Cursor adapter $target" >&2
      return 1
    fi
    if ! diff -u "$target" "$tmp" >/dev/null; then
      echo "ERR: Cursor adapter drift for $label" >&2
      diff -u "$target" "$tmp" >&2
      return 1
    fi
  else
    mkdir -p "$(dirname "$target")"
    cp "$tmp" "$target"
  fi
}

# Stale adapters: generated files whose source was renamed or deleted. A file is
# ours only if its marker names ITS OWN source — matching the source *directory*
# alone would also claim a user's copy of our adapter under a new name, and a
# generic "do not edit directly" banner would claim another tool's output. Both
# would be deleted, silently and unrecoverably. Anything unclaimed is an error
# here, since both these dirs are generator-owned; it is never removed.
#
# .cursor/rules deliberately has no sweep: we ship exactly one constant filename
# there, so every other .mdc in that shared namespace belongs to the project.
check_stale() {
  local dir=$1 expected=$2 source_dir=$3 marker_prefix=$4
  local adapter base rc=0
  for adapter in "$dir"/*.md; do
    [ -e "$adapter" ] || continue
    base=$(basename "$adapter")
    case " $expected " in
      *" $base "*) continue ;;
    esac
    if grep -qF "generated from ${marker_prefix}/${base}" "$adapter" 2>/dev/null; then
      if [ "$MODE" = "--check" ]; then
        echo "ERR: stale Cursor adapter $adapter (no matching source in $source_dir)" >&2
        rc=1
      else
        rm -f "$adapter"
        echo "✗ removed stale Cursor adapter $adapter"
      fi
    else
      echo "ERR: unexpected non-generated file $adapter in $dir — move it or remove it manually" >&2
      rc=1
    fi
  done
  return "$rc"
}

drift=0
workflow_parse_error=0
expected_commands=""
expected_agents=""
chain_rows=""

for workflow in "$WORKFLOWS_DIR"/*.md; do
  [ -e "$workflow" ] || continue
  name=$(field "$workflow" "name")
  if [ -z "$name" ]; then
    echo "ERR: missing name in $workflow" >&2
    workflow_parse_error=1
    continue
  fi
  expected_commands="$expected_commands ${name}.md"
  chains=$(field "$workflow" "chains")
  if [ -n "$chains" ] && [ "$chains" != "none" ]; then
    chain_rows="${chain_rows}| /${name} | ${chains} |"$'\n'
  fi
  target="$CURSOR_COMMANDS_DIR/${name}.md"
  tmp=$(mktemp "${TMPDIR:-/tmp}/heph-cursor-command-XXXXXX")
  render_cursor_command "$workflow" > "$tmp" || { workflow_parse_error=1; rm -f "$tmp"; continue; }
  check_or_write "$target" "$tmp" "/$name" || drift=1
  rm -f "$tmp"
done

# The rule inventories the workflow graph, so an unparseable workflow would
# render an incomplete rule. Report that source instead of manufacturing drift.
# Ordinary command drift does not gate it — chain_rows is still complete, and
# suppressing the rule check would hide a second drift behind the first.
if [ "$workflow_parse_error" -eq 0 ]; then
  tmp=$(mktemp "${TMPDIR:-/tmp}/heph-cursor-rule-XXXXXX")
  render_cursor_rule "$chain_rows" > "$tmp"
  check_or_write "$CURSOR_RULES_DIR/$RULE_NAME" "$tmp" "$RULE_NAME" || drift=1
  rm -f "$tmp"
fi
drift=$(( drift | workflow_parse_error ))

for agent in "$CLAUDE_AGENTS_DIR"/*.md; do
  [ -e "$agent" ] || continue
  name=$(field "$agent" "name")
  if [ -z "$name" ]; then
    echo "ERR: missing name in $agent" >&2
    drift=1
    continue
  fi
  expected_agents="$expected_agents ${name}.md"
  target="$CURSOR_AGENTS_DIR/${name}.md"
  tmp=$(mktemp "${TMPDIR:-/tmp}/heph-cursor-agent-XXXXXX")
  render_cursor_agent "$agent" > "$tmp" || { drift=1; rm -f "$tmp"; continue; }
  check_or_write "$target" "$tmp" "@$name" || drift=1
  rm -f "$tmp"
done

# In sync mode, skip stale removal when any source failed to parse — an
# unparseable source is not a deleted one, and deleting its adapter would
# destroy a live command or subagent.
[ "$MODE" = "sync" ] && [ "$drift" -ne 0 ] && exit 1
check_stale "$CURSOR_COMMANDS_DIR" "$expected_commands" "$WORKFLOWS_DIR" ".ai/workflows" || drift=1
check_stale "$CURSOR_AGENTS_DIR" "$expected_agents" "$CLAUDE_AGENTS_DIR" ".claude/agents" || drift=1

if [ "$MODE" = "--check" ]; then
  [ "$drift" -eq 0 ] && echo "✓ Cursor adapters in sync"
  exit "$drift"
fi

[ "$drift" -ne 0 ] && exit 1
echo "✓ Cursor adapters generated"
