#!/usr/bin/env bash
# check_conventions.sh — Verify the workflows agree with .ai/conventions.md.
#
# .ai/conventions.md is the product behavior spec; .ai/workflows/*.md are the
# shipped artifact. An installed project has no .ai/ directory, so a workflow
# cannot point at the spec at runtime — it must restate each limit at the point
# of use. That restating is the thing that can drift, so it is checked:
#
#   1. The spec's retry-limit table parses, and every loop it names has a value.
#   2. Every retry count a workflow states matches the spec limit for the loop
#      it names. The binding is the noun: the spec measures the critique loops
#      in "iterations" and the test-fix loop in "cycles", so a workflow saying
#      "max 2 iterations" fails even though 2 is a number the spec uses
#      elsewhere. Set membership alone would let the two limits swap silently.
#   3. No file reintroduces a by-name reference to the limits ("per CLAUDE.md
#      retry limits"). That pointer is what forced /orient to retype the limits
#      into every installed project's CLAUDE.md — the duplication this layout
#      exists to prevent.
#   4. Nothing scaffolds a "## Workflow Rules" block. It is an optional
#      per-project override now, not something hephaestus writes for you.
#
# Checks 3 and 4 scan the same set: the canonical sources, every generated
# adapter family, and the scaffolding templates. A pointer is only harmful
# where it ships, and all of those ship.
#
# Exits 0 if in sync, 1 on drift (report on stderr).
# Invoked by tests/test_conventions.sh and the repo's quality gates.
# hephaestus:doc-verifier

set -uo pipefail
# -e omitted intentionally: collect every drift, don't bail on the first.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$ROOT/.ai/conventions.md"
WORKFLOWS_DIR="$ROOT/.ai/workflows"

drift=0
report() { drift=1; echo "  ✗ $1" >&2; }

[ -f "$SPEC" ] || { echo "ERR: missing $SPEC" >&2; exit 1; }

# ── 1. Parse the spec's retry-limit table ────────────────────────────────────
# Rows look like: | Plan-critique | 3 iterations |
limits=$(awk '/^## Retry limits/{f=1; next} f && /^## /{f=0} f' "$SPEC" \
         | grep -E '^\|' | grep -vE '^\|[ -]*\|[ -]*\|$' \
         | sed -E 's/^\| *//; s/ *\| *$//' | grep -vi '^loop *|')

if [ -z "$limits" ]; then
  echo "ERR: no retry-limit table under '## Retry limits' in $SPEC" >&2
  exit 1
fi

# Bind each limit to the noun the spec measures it in, so the counts cannot
# swap. "iterations" → the critique loops; "cycles" → the test-fix loop.
limit_for_noun() {
  echo "$limits" | grep -i "$1" | sed -E 's/.*\| *//' | grep -oE '^[0-9]+' | sort -u
}
iter_limit=$(limit_for_noun 'iteration')
cycle_limit=$(limit_for_noun 'cycle')

[ -n "$iter_limit" ] && [ -n "$cycle_limit" ] \
  || { echo "ERR: $SPEC must state its limits in 'iterations' and 'cycles'" >&2; exit 1; }

for loop in "Plan-critique" "Pre-ship code critique" "Test-fix"; do
  echo "$limits" | grep -qiF "$loop" \
    || report "spec is missing a retry limit for '$loop'"
done

# ── 2. Every count a workflow states must match the spec for that loop ───────
# The noun carries the binding, so the pattern must be generous about the verb
# and the words between the number and the noun: "max 3 iterations", "up to 3
# iterations", "all 3 attempts", "max 2 full plan-implement-test cycles".
COUNT_RE='[0-9]+ +([a-z-]+ +){0,2}(iterations?|cycles?|attempts?|retries|retry|rounds?)'

for workflow in "$WORKFLOWS_DIR"/*.md; do
  name=$(basename "$workflow")
  while IFS= read -r phrase; do
    [ -n "$phrase" ] || continue
    count=$(echo "$phrase" | grep -oE '^[0-9]+')
    # cycles and retries measure the test-fix loop; everything else a critique loop.
    case "$phrase" in
      *cycle*|*retries|*retry) expected="$cycle_limit"; loop="the test-fix loop" ;;
      *)                       expected="$iter_limit";  loop="a critique loop"  ;;
    esac
    echo "$expected" | grep -qx "$count" \
      || report "$name says \"$phrase\", but .ai/conventions.md sets $loop to $(echo "$expected" | tr '\n' '/' | sed 's|/$||')"
  done <<< "$(grep -oiE "$COUNT_RE" "$workflow" | tr 'A-Z' 'a-z' | sort -u)"
done

# The set of every shipped surface a stale pointer could hide in.
SHIPPED="$WORKFLOWS_DIR $ROOT/.claude/commands $ROOT/.claude/agents
$ROOT/.opencode/commands $ROOT/.opencode/agents $ROOT/.agents/skills
$ROOT/.codex/agents $ROOT/.hermes/skills $ROOT/.hermes/agents
$ROOT/.cursor/commands $ROOT/.cursor/agents $ROOT/.cursor/rules $ROOT/templates"

# ── 3. No by-name reference to the limits ────────────────────────────────────
# Only the retry-limit pointer, not every "(per CLAUDE.md)" — a project's
# CLAUDE.md is still the right target for quality gates and worktree config.
stale=$(grep -rlE 'per CLAUDE\.md retry limits|retry limits \(per CLAUDE\.md\)' \
          $SHIPPED 2>/dev/null)
if [ -n "$stale" ]; then
  while IFS= read -r file; do
    report "${file#"$ROOT"/} references the retry limits by name; state the value instead"
  done <<< "$stale"
fi

# ── 4. Nothing scaffolds a Workflow Rules block ──────────────────────────────
scaffolded=$(grep -rl '^ *## Workflow Rules' $SHIPPED 2>/dev/null)
if [ -n "$scaffolded" ]; then
  while IFS= read -r file; do
    report "${file#"$ROOT"/} scaffolds a '## Workflow Rules' block; it is an optional project override, not something hephaestus writes"
  done <<< "$scaffolded"
fi

if [ "$drift" -ne 0 ]; then
  echo "" >&2
  echo "Conventions drift. Fix .ai/conventions.md first, then the workflows, then re-run." >&2
  exit 1
fi

echo "✓ workflows agree with .ai/conventions.md"
