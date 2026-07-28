#!/usr/bin/env bash
# sync-codex-adapters.sh — Generate/check Codex skill and agent-role adapters.
#
# Canonical workflow specs live in .ai/workflows/*.md. Claude agent definitions
# remain the source of truth for shared subagent prompts. This script renders
# Codex-compatible adapters from those sources so adapter metadata cannot drift:
#   .ai/workflows/<name>.md   → .agents/skills/<name>/SKILL.md  (Codex skill)
#   .claude/agents/<name>.md  → .codex/agents/<name>.toml       (Codex agent role)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOWS_DIR="$ROOT/.ai/workflows"
CLAUDE_AGENTS_DIR="$ROOT/.claude/agents"
CODEX_SKILLS_DIR="$ROOT/.agents/skills"
CODEX_AGENTS_DIR="$ROOT/.codex/agents"
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

# Escapes backslash and double-quote — valid for both YAML and TOML basic strings.
quote_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

first_body_line() {
  local file=$1 start=$2
  awk -v start="$start" 'NR >= start && NF { print; exit }' "$file"
}

# Rewrite Claude-dialect body text for Codex mechanics.
codex_localize_body() {
  sed \
    -e 's/parallel coder subagents (in worktrees)/parallel coder role agents when available (serialize file edits; Codex has no worktree isolation)/g' \
    -e 's/coder subagents (in worktrees)/coder role agents when available (serialize file edits; Codex has no worktree isolation)/g' \
    -e 's/parallel coder subagents/parallel coder role agents when available/g' \
    -e 's/coder subagent(s)/coder role agent(s)/g' \
    -e 's/coder subagents/coder role agents/g' \
    -e 's/explorer subagent(s)/explorer role agent(s)/g' \
    -e 's/explorer subagents/explorer role agents/g' \
    -e 's/reviewer subagent(s)/reviewer role agent(s)/g' \
    -e 's/reviewer subagents/reviewer role agents/g' \
    -e 's/tester subagent(s)/tester role agent(s)/g' \
    -e 's/tester subagents/tester role agents/g' \
    -e 's/researcher subagent(s)/researcher role agent(s)/g' \
    -e 's/researcher subagents/researcher role agents/g' \
    -e 's/subagent(s)/role agent(s)/g' \
    -e 's/subagents/role agents/g' \
    -e 's/subagent/role agent/g' \
    -e 's/TodoWrite/the plan tool/g'
}

render_codex_skill() {
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

  # Codex skill descriptions drive implicit invocation — swap the unsubstituted
  # $ARGUMENTS placeholder for a readable token, truncate on a word boundary,
  # and anchor the slash-command name for matching.
  desc=$(first_body_line "$workflow" "$start")
  desc=$(printf '%s' "$desc" | sed 's/\$ARGUMENTS/<argument>/g; s/  */ /g')
  if [ "${#desc}" -gt 180 ]; then
    desc="${desc:0:180}"
    desc="${desc% *}…"
  fi
  desc=$(quote_escape "$desc Use for /${name} requests.")

  {
    echo "---"
    echo "name: $name"
    echo "description: \"$desc\""
    echo "---"
    echo "<!-- requires: ${requires} -->"
    echo "<!-- chains: ${chains} -->"
    echo "<!-- generated from .ai/workflows/${name}.md; do not edit directly -->"
    echo ""
    if [ "$chains" != "none" ]; then
      echo "> **Codex:** this skill is the \`/${name}\` adapter. For chained workflows (${chains}), invoke the matching generated skill (for example \`heph:<workflow>\`) when it is available; otherwise read and follow \`.agents/skills/<workflow>/SKILL.md\`. Use Codex role agents from \`.codex/agents/\` when the runtime exposes them; otherwise perform the work directly and keep the same structured output."
    else
      echo "> **Codex:** this skill is the \`/${name}\` adapter. Use Codex role agents from \`.codex/agents/\` when the runtime exposes them; otherwise perform the work directly and keep the same structured output."
    fi
    echo ""
    if grep -q '\$ARGUMENTS' "$workflow"; then
      echo "> Codex does not substitute \`\$ARGUMENTS\` — read it as the arguments given in the user's request."
      echo ""
    fi
    sed -n "${start},\$p" "$workflow" | codex_localize_body
  }
}

# Sandbox mapping mirrors the OpenCode permission surface: a write-capable shell
# or edit tools ⇒ workspace-write; otherwise read-only (e.g. researcher).
render_sandbox_mode() {
  local tools=$1
  if [[ "$tools" == *"Bash"* ]] || [[ "$tools" == *"Edit"* ]] || [[ "$tools" == *"Write"* ]]; then
    echo "workspace-write"
  else
    echo "read-only"
  fi
}

render_codex_agent() {
  local agent=$1
  local name description tools isolation tier model effort start

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
  model=$(models_lookup "codex" "$tier" "model")
  effort=$(models_lookup "codex" "$tier" "effort")

  # developer_instructions is a TOML literal multiline string — a body containing
  # its delimiter cannot be rendered safely.
  if sed -n "${start},\$p" "$agent" | grep -q "'''"; then
    echo "ERR: agent body in $agent contains ''' — cannot render TOML literal string" >&2
    return 1
  fi

  # Codex has no worktree isolation for subagents; surface that where the
  # orchestrator decides to parallelize (description) and where the agent runs.
  if [ "$isolation" = "worktree" ]; then
    description="$description NOTE: Codex has no worktree isolation — parallel ${name} agents share one working tree; serialize file-modifying tasks."
  fi
  description=$(quote_escape "$description")

  {
    echo "# generated from .claude/agents/${name}.md; do not edit directly"
    echo "name = \"${name}\""
    echo "description = \"${description}\""
    [ -n "$model" ] && echo "model = \"${model}\""
    [ -n "$effort" ] && echo "model_reasoning_effort = \"${effort}\""
    echo "sandbox_mode = \"$(render_sandbox_mode "$tools")\""
    echo "developer_instructions = '''"
    if [ "$isolation" = "worktree" ]; then
      echo "> **No worktree isolation.** The Claude version of this agent runs in an isolated git worktree; Codex has no equivalent. Parallel ${name} agents edit the same working tree — serialize file-modifying tasks."
      echo ""
    fi
    sed -n "${start},\$p" "$agent"
    echo "'''"
  }
}

check_or_write() {
  local target=$1 tmp=$2 label=$3

  if [ "$MODE" = "--check" ]; then
    if [ ! -f "$target" ]; then
      echo "ERR: missing Codex adapter $target" >&2
      return 1
    fi
    if ! diff -u "$target" "$tmp" >/dev/null; then
      echo "ERR: Codex adapter drift for $label" >&2
      diff -u "$target" "$tmp" >&2
      return 1
    fi
  else
    mkdir -p "$(dirname "$target")"
    cp "$tmp" "$target"
  fi
}

# Stale skill dirs: generated skills whose source workflow was renamed or deleted.
# Only dirs whose SKILL.md carries the generated-from marker are ever removed —
# a non-generated dir is user content and is reported, never deleted.
check_stale_skills() {
  local dir base skill_md rc=0
  for dir in "$CODEX_SKILLS_DIR"/*/; do
    [ -e "$dir" ] || continue
    base=$(basename "$dir")
    case " $expected_skills " in
      *" $base "*) continue ;;
    esac
    skill_md="$dir/SKILL.md"
    if [ -f "$skill_md" ] && grep -q "generated from .ai/workflows/" "$skill_md"; then
      if [ "$MODE" = "--check" ]; then
        echo "ERR: stale Codex skill $dir (no matching source in $WORKFLOWS_DIR)" >&2
        rc=1
      else
        rm -rf "$dir"
        echo "✗ removed stale Codex skill $dir"
      fi
    else
      echo "ERR: unexpected non-generated dir $dir in .agents/skills — move it or remove it manually" >&2
      rc=1
    fi
  done
  return "$rc"
}

check_stale_agents() {
  local adapter base rc=0
  for adapter in "$CODEX_AGENTS_DIR"/*.toml; do
    [ -e "$adapter" ] || continue
    base=$(basename "$adapter")
    case " $expected_agents " in
      *" $base "*) continue ;;
    esac
    if [ "$MODE" = "--check" ]; then
      echo "ERR: stale Codex agent adapter $adapter (no matching source in $CLAUDE_AGENTS_DIR)" >&2
      rc=1
    else
      rm -f "$adapter"
      echo "✗ removed stale Codex agent adapter $adapter"
    fi
  done
  return "$rc"
}

drift=0
expected_skills=""
expected_agents=""

for workflow in "$WORKFLOWS_DIR"/*.md; do
  [ -e "$workflow" ] || continue
  name=$(field "$workflow" "name")
  if [ -z "$name" ]; then
    echo "ERR: missing name in $workflow" >&2
    drift=1
    continue
  fi
  expected_skills="$expected_skills $name"
  target="$CODEX_SKILLS_DIR/$name/SKILL.md"
  tmp=$(mktemp "${TMPDIR:-/tmp}/heph-codex-skill-XXXXXX")
  render_codex_skill "$workflow" > "$tmp" || { drift=1; rm -f "$tmp"; continue; }
  check_or_write "$target" "$tmp" "\$$name" || drift=1
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
  expected_agents="$expected_agents ${name}.toml"
  target="$CODEX_AGENTS_DIR/${name}.toml"
  tmp=$(mktemp "${TMPDIR:-/tmp}/heph-codex-agent-XXXXXX")
  render_codex_agent "$agent" > "$tmp" || { drift=1; rm -f "$tmp"; continue; }
  check_or_write "$target" "$tmp" "@$name" || drift=1
  rm -f "$tmp"
done

# In sync mode, skip stale removal when any source failed to parse — an
# unparseable source is not a deleted one, and deleting its adapter would
# destroy a live skill or agent role.
[ "$MODE" = "sync" ] && [ "$drift" -ne 0 ] && exit 1
check_stale_skills || drift=1
check_stale_agents || drift=1

if [ "$MODE" = "--check" ]; then
  [ "$drift" -eq 0 ] && echo "✓ Codex adapters in sync"
  exit "$drift"
fi

[ "$drift" -ne 0 ] && exit 1
echo "✓ Codex adapters generated"
