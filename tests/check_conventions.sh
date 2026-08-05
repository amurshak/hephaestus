#!/usr/bin/env bash
# check_conventions.sh — Verify the workflows agree with .ai/conventions.md.
#
# .ai/conventions.md is the product behavior spec; .ai/workflows/*.md are the
# shipped artifact. An installed project has no .ai/ directory, so a workflow
# cannot point at the spec at runtime — it must restate each limit at the point
# of use. That restating is the thing that can drift, so it is checked:
#
#   1. The spec's retry-limit table parses, and every loop it names has a value.
#   2. Every retry count a workflow states is one the spec allows. A workflow
#      saying "max 4 iterations" fails even though nothing else would notice.
#   3. No file reintroduces a by-name reference to the limits ("per CLAUDE.md
#      retry limits"). That pointer is what forced /orient to retype the limits
#      into every installed project's CLAUDE.md — the duplication this layout
#      exists to prevent.
#   4. Nothing scaffolds a "## Workflow Rules" block. It is an optional
#      per-project override now, not something hephaestus writes for you.
#
# Exits 0 if in sync, 1 on drift (report on stderr).
# Invoked by tests/test_conventions.sh and the repo's quality gates.

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

# The set of counts the spec sanctions, e.g. "2 3"
allowed=$(echo "$limits" | sed -E 's/.*\| *//' | grep -oE '^[0-9]+' | sort -u)
[ -n "$allowed" ] || { echo "ERR: no numeric limits parsed from $SPEC" >&2; exit 1; }

for loop in "Plan-critique" "Pre-ship code critique" "Test-fix"; do
  echo "$limits" | grep -qiF "$loop" \
    || report "spec is missing a retry limit for '$loop'"
done

# ── 2. Every count a workflow states must be one the spec allows ─────────────
# Matches "max 3 iterations", "max 2 full cycles", "all 3 attempts",
# "after 3 iterations", "max 2 cycles".
for workflow in "$WORKFLOWS_DIR"/*.md; do
  name=$(basename "$workflow")
  counts=$(grep -oiE '(max|after|all) [0-9]+ (full )?(iterations?|cycles?|attempts?)' "$workflow" \
           | grep -oE '[0-9]+' | sort -u)
  for count in $counts; do
    echo "$allowed" | grep -qx "$count" \
      || report "$name states a retry count of $count, which .ai/conventions.md does not allow (allowed: $(echo "$allowed" | tr '\n' ' ' | sed 's/ $//'))"
  done
done

# ── 3. No by-name reference to the limits ────────────────────────────────────
# Checked across the canonical sources, the generated adapters, and the
# scaffolding templates — the pointer is only harmful where it ships.
stale=$(grep -rlE 'per CLAUDE\.md retry limits|retry limits \(per CLAUDE\.md\)|per CLAUDE\.md\)' \
          "$WORKFLOWS_DIR" "$ROOT/.claude/commands" "$ROOT/.opencode/commands" \
          "$ROOT/.agents/skills" "$ROOT/.hermes/skills" "$ROOT/.cursor/commands" \
          "$ROOT/templates" 2>/dev/null)
if [ -n "$stale" ]; then
  while IFS= read -r file; do
    report "${file#"$ROOT"/} references the retry limits by name; state the value instead"
  done <<< "$stale"
fi

# ── 4. Nothing scaffolds a Workflow Rules block ──────────────────────────────
scaffolded=$(grep -rl '^ *## Workflow Rules' "$WORKFLOWS_DIR" "$ROOT/templates" \
               "$ROOT/.claude/commands" 2>/dev/null)
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
