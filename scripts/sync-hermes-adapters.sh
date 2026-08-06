#!/usr/bin/env bash
# sync-hermes-adapters.sh — Generate/check Hermes skill and delegate adapters.
#
# Canonical workflow specs live in .ai/workflows/*.md. Claude agent definitions
# remain the source of truth for shared subagent prompts. This script renders
# Hermes-compatible adapters from those sources so adapter metadata cannot drift:
#   .ai/workflows/<name>.md   → .hermes/skills/hephaestus/<name>/SKILL.md
#   .claude/agents/<name>.md  → .hermes/agents/<name>.md  (delegate_task brief)
#
# Hermes is not a command-file harness: skills are directories holding a
# SKILL.md, discovered from ~/.hermes/skills plus any `skills.external_dirs`.
# The `hephaestus/` level is the skill category, matching how Hermes groups its
# own bundled skills. Generated skills carry no `version:` field on purpose —
# tying adapter content to VERSION would rewrite all 13 files every release.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOWS_DIR="$ROOT/.ai/workflows"
CLAUDE_AGENTS_DIR="$ROOT/.claude/agents"
HERMES_SKILLS_DIR="$ROOT/.hermes/skills/hephaestus"
HERMES_AGENTS_DIR="$ROOT/.hermes/agents"
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

# Escapes backslash and double-quote — valid for YAML double-quoted scalars.
quote_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

first_body_line() {
  local file=$1 start=$2
  awk -v start="$start" 'NR >= start && NF { print; exit }' "$file"
}

# Trim to Hermes's recommended description length. LC_ALL is pinned so the cut
# lands identically whether the caller's locale counts bytes or characters —
# otherwise --check reports drift on machines that merely differ in $LANG. Words
# are dropped whole, so a multibyte character can never be split mid-sequence.
truncate_desc() {
  LC_ALL=C awk -v max=60 '
    { if (length($0) <= max) { print; exit }
      out = ""
      n = split($0, w, " ")
      for (i = 1; i <= n; i++) {
        cand = (out == "" ? w[i] : out " " w[i])
        if (length(cand) > max) break
        out = cand
      }
      # A first word longer than max fits nothing; keep it whole rather than
      # emit a bare ellipsis — over budget beats a description-less skill, and
      # cutting mid-word could split a multibyte character.
      if (out == "") out = w[1]
      print out "…"
    }'
}

# Rewrite Claude-dialect body text for Hermes mechanics.
#
# Spawn commands are localized per skill, never generically. `hermes chat -q`
# bypasses the slash dispatcher, so a generic `claude "<prompt>"` → `hermes chat
# -q "<prompt>"` rule would quietly turn any `/<skill>` spawn into literal text
# the model never acts on. Left unmatched instead, a new Claude-form spawn keeps
# the word `claude` and trips the leak guard in tests/test_hermes_adapters.sh —
# loud, and pointing at the line that needs its own `-s` rule.
hermes_localize_body() {
  sed \
    -e 's/, use parallel coder subagents (in worktrees)/, you **must** spawn one coder delegate per file via `delegate_task` instead of editing them yourself (serialize file edits; Hermes delegates share one working tree)/g' \
    -e 's/, spawn parallel explorer subagents/, you **must** spawn parallel explorer delegates via `delegate_task`/g' \
    -e 's/, spawn multiple explorer subagents/, you **must** spawn multiple explorer delegates via `delegate_task`/g' \
    -e 's/parallel coder subagents (in worktrees)/parallel coder delegates via `delegate_task` (serialize file edits; Hermes delegates share one working tree)/g' \
    -e 's/coder subagents (in worktrees)/coder delegates via `delegate_task` (serialize file edits; Hermes delegates share one working tree)/g' \
    -e 's/parallel coder subagents/parallel coder delegates/g' \
    -e 's/coder subagent(s)/coder delegate(s)/g' \
    -e 's/coder subagents/coder delegates/g' \
    -e 's/explorer subagent(s)/explorer delegate(s)/g' \
    -e 's/explorer subagents/explorer delegates/g' \
    -e 's/reviewer subagent(s)/reviewer delegate(s)/g' \
    -e 's/reviewer subagents/reviewer delegates/g' \
    -e 's/tester subagent(s)/tester delegate(s)/g' \
    -e 's/tester subagents/tester delegates/g' \
    -e 's/researcher subagent(s)/researcher delegate(s)/g' \
    -e 's/researcher subagents/researcher delegates/g' \
    -e 's/subagent(s)/delegate(s)/g' \
    -e 's/subagents/delegates/g' \
    -e 's/subagent/delegate/g' \
    -e 's/TodoWrite/the todo tool/g' \
    -e 's/seeded Claude Code session/seeded Hermes session/g' \
    -e 's|claude --permission-mode default \\"/start-issue <N>\\"|hermes chat -s hephaestus/start-issue -q \\"Run the start-issue workflow for issue <N>.\\"|g' \
    -e 's|claude "/start-issue <N>"|hermes chat -s hephaestus/start-issue -q "Run the start-issue workflow for issue <N>."|g' \
    -e 's|`--permission-mode default` prevents spawned sessions inheriting plan mode and stalling|`-s` preloads the skill, because a bare `/start-issue` is never dispatched in `-q` mode — it reaches the model as literal text|g' \
    -e "s/Claude Code's title rewrites/the TUI's title rewrites/g"
}

# "/a, /b" → "[a, b]"; "none" → "[]". Feeds metadata.hermes.related_skills.
render_related_skills() {
  local chains=$1
  if [ "$chains" = "none" ]; then
    echo "[]"
    return
  fi
  echo "[$(printf '%s' "$chains" | tr -d ' /' | tr ',' ' ' | xargs | tr ' ' ',' | sed 's/,/, /g')]"
}

render_hermes_skill() {
  local workflow=$1
  local name requires chains start desc related

  name=$(field "$workflow" "name")
  requires=$(field "$workflow" "requires")
  chains=$(field "$workflow" "chains")
  start=$(body_start_line "$workflow")

  if [ -z "$name" ] || [ -z "$requires" ] || [ -z "$chains" ] || [ -z "$start" ]; then
    echo "ERR: invalid workflow frontmatter in $workflow" >&2
    return 1
  fi

  # Hermes lists skills by name + description and recommends ≤60 characters, so
  # the first body line is trimmed on a word boundary. The name is the literal
  # slash command, so the description carries no invocation anchor.
  desc=$(first_body_line "$workflow" "$start")
  desc=$(printf '%s' "$desc" | sed 's/\$ARGUMENTS/<argument>/g; s/  */ /g' | truncate_desc)
  desc=$(quote_escape "$desc")
  related=$(render_related_skills "$chains")

  {
    echo "---"
    echo "name: $name"
    echo "description: \"$desc\""
    echo "platforms: [linux, macos, windows]"
    echo "metadata:"
    echo "  hermes:"
    echo "    category: hephaestus"
    echo "    tags: [hephaestus, delivery, ${name}]"
    echo "    requires_toolsets: [terminal]"
    echo "    related_skills: ${related}"
    echo "---"
    echo "<!-- requires: ${requires} -->"
    echo "<!-- chains: ${chains} -->"
    echo "<!-- generated from .ai/workflows/${name}.md; do not edit directly -->"
    echo ""
    echo "> **Hermes:** this skill is the \`/${name}\` adapter."
    if [ "$requires" != "none" ]; then
      echo "> Where a step below names a role (${requires}), you **must** call \`delegate_task\` for it rather than doing that step yourself — measured: orchestrators otherwise inline the whole workflow and never delegate. Each role's toolsets, cap and prompt are in \`.hermes/agents/<role>.md\`. A delegate inherits **none** of your conversation and **not your working directory** — give \`context\` absolute paths plus every constraint and prior finding it needs. Delegates get no per-child worktree, so parallel ones share one working tree: serialize file-modifying work."
    fi
    if [ "$chains" != "none" ]; then
      echo "> For chained workflows (${chains}), invoke the matching skill (\`/<workflow>\`) when it is installed; otherwise read and follow \`.hermes/skills/hephaestus/<workflow>/SKILL.md\`."
    fi
    echo ""
    if grep -q '\$ARGUMENTS' "$workflow"; then
      echo "> Hermes does not substitute \`\$ARGUMENTS\` — read it as the arguments given in the user's request."
      echo ""
    fi
    sed -n "${start},\$p" "$workflow" | hermes_localize_body
  }
}

# Map Claude tool grants onto Hermes toolset names, in a stable order.
# Bash → terminal; file readers/writers → file; web tools → web.
render_toolsets() {
  local tools=$1 sets=""
  [[ "$tools" == *"Bash"* ]] && sets="\"terminal\""
  if [[ "$tools" == *"Read"* ]] || [[ "$tools" == *"Edit"* ]] || [[ "$tools" == *"Write"* ]] \
    || [[ "$tools" == *"Glob"* ]] || [[ "$tools" == *"Grep"* ]]; then
    sets="${sets:+$sets, }\"file\""
  fi
  if [[ "$tools" == *"WebSearch"* ]] || [[ "$tools" == *"WebFetch"* ]]; then
    sets="${sets:+$sets, }\"web\""
  fi
  echo "[${sets}]"
}

render_hermes_agent() {
  local agent=$1
  local name description tools isolation tier model start toolsets

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
  model=$(models_lookup "hermes" "$tier" "model")
  toolsets=$(render_toolsets "$tools")

  {
    echo "<!-- generated from .claude/agents/${name}.md; do not edit directly -->"
    echo "# ${name} delegate"
    echo ""
    echo "${description}"
    echo ""
    echo "Hermes has no agent-definition file format — it spawns children through"
    echo "\`delegate_task\`. Pass the **Prompt** below as \`context\` and call with:"
    echo ""
    echo "\`\`\`"
    echo "delegate_task(goal: \"<the task>\", context: \"<this prompt + everything the delegate needs>\","
    echo "              toolsets: ${toolsets}, role: \"leaf\")"
    echo "\`\`\`"
    echo ""
    echo "- **Toolsets**: \`${toolsets}\` — intersected with yours, silently. A toolset you lack is dropped with no error, so confirm the session holds these before delegating."
    echo "- **Role**: \`leaf\` — cannot delegate further, and Hermes already blocks \`memory\`, \`clarify\`, \`send_message\` and \`cronjob\` for children."
    echo "- **No inherited cwd**: the child gets only a workspace *hint* in its system prompt. Put the absolute repo or worktree path in \`context\`."
    if [ -n "$model" ]; then
      echo "- **Model tier**: \`${tier}\` → \`${model}\`. Advisory: Hermes applies one global \`delegation.model\`, so set it from the highest tier a workflow uses."
    else
      echo "- **Model tier**: \`${tier:-inherit}\` — inherits the session model."
    fi
    if [[ "$tools" != *"Edit"* ]] && [[ "$tools" != *"Write"* ]]; then
      echo "- **Read-only**: the Claude role grants no edit tools. Hermes's \`file\` toolset does include writes, so state the constraint in \`context\` — this delegate reports findings, it does not change files."
    fi
    if [ "$isolation" = "worktree" ]; then
      echo "- **No worktree isolation**: the Claude version runs in an isolated git worktree; \`delegate_task\` has no per-child equivalent (session-level \`hermes chat -w\` is the closest). Parallel ${name} delegates edit the same working tree — serialize file-modifying tasks."
    fi
    echo ""
    echo "## Prompt"
    echo ""
    sed -n "${start},\$p" "$agent"
  }
}

check_or_write() {
  local target=$1 tmp=$2 label=$3

  if [ "$MODE" = "--check" ]; then
    if [ ! -f "$target" ]; then
      echo "ERR: missing Hermes adapter $target" >&2
      return 1
    fi
    if ! diff -u "$target" "$tmp" >/dev/null; then
      echo "ERR: Hermes adapter drift for $label" >&2
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
  for dir in "$HERMES_SKILLS_DIR"/*/; do
    [ -e "$dir" ] || continue
    base=$(basename "$dir")
    case " $expected_skills " in
      *" $base "*) continue ;;
    esac
    skill_md="$dir/SKILL.md"
    if [ -f "$skill_md" ] && grep -q "generated from .ai/workflows/" "$skill_md"; then
      if [ "$MODE" = "--check" ]; then
        echo "ERR: stale Hermes skill $dir (no matching source in $WORKFLOWS_DIR)" >&2
        rc=1
      else
        rm -rf "$dir"
        echo "✗ removed stale Hermes skill $dir"
      fi
    else
      echo "ERR: unexpected non-generated dir $dir in .hermes/skills/hephaestus — move it or remove it manually" >&2
      rc=1
    fi
  done
  return "$rc"
}

check_stale_agents() {
  local adapter base rc=0
  for adapter in "$HERMES_AGENTS_DIR"/*.md; do
    [ -e "$adapter" ] || continue
    base=$(basename "$adapter")
    case " $expected_agents " in
      *" $base "*) continue ;;
    esac
    # Only sweep files this generator wrote, matching check_stale_skills.
    if ! grep -q "generated from .claude/agents/" "$adapter"; then
      echo "ERR: unexpected non-generated file $adapter in .hermes/agents — move it or remove it manually" >&2
      rc=1
    elif [ "$MODE" = "--check" ]; then
      echo "ERR: stale Hermes agent adapter $adapter (no matching source in $CLAUDE_AGENTS_DIR)" >&2
      rc=1
    else
      rm -f "$adapter"
      echo "✗ removed stale Hermes agent adapter $adapter"
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
  target="$HERMES_SKILLS_DIR/$name/SKILL.md"
  tmp=$(mktemp "${TMPDIR:-/tmp}/heph-hermes-skill-XXXXXX")
  render_hermes_skill "$workflow" > "$tmp" || { drift=1; rm -f "$tmp"; continue; }
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
  target="$HERMES_AGENTS_DIR/${name}.md"
  tmp=$(mktemp "${TMPDIR:-/tmp}/heph-hermes-agent-XXXXXX")
  render_hermes_agent "$agent" > "$tmp" || { drift=1; rm -f "$tmp"; continue; }
  check_or_write "$target" "$tmp" "@$name" || drift=1
  rm -f "$tmp"
done

# In sync mode, skip stale removal when any source failed to parse — an
# unparseable source is not a deleted one, and deleting its adapter would
# destroy a live skill or delegate brief.
[ "$MODE" = "sync" ] && [ "$drift" -ne 0 ] && exit 1
check_stale_skills || drift=1
check_stale_agents || drift=1

if [ "$MODE" = "--check" ]; then
  [ "$drift" -eq 0 ] && echo "✓ Hermes adapters in sync"
  exit "$drift"
fi

[ "$drift" -ne 0 ] && exit 1
echo "✓ Hermes adapters generated"
