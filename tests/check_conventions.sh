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
#      it names, and every limit-shaped phrase is in a shape this check can
#      read. The binding is the noun: the spec measures the critique loops in
#      "iterations" and the test-fix loop in "cycles", so a workflow saying
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

# Each noun must resolve to exactly one value, and the two must differ. A spec
# row worded so that "iterations" also matches the test-fix limit would widen
# both sets until the swap this binding exists to catch slips through again.
[ "$(echo "$iter_limit" | wc -l)" -eq 1 ] && [ "$(echo "$cycle_limit" | wc -l)" -eq 1 ] \
  && [ -n "$iter_limit" ] && [ -n "$cycle_limit" ] && [ "$iter_limit" != "$cycle_limit" ] \
  || { echo "ERR: $SPEC must bind 'iterations' and 'cycles' to one distinct value each (got '$(echo "$iter_limit" | tr '\n' ' ')' and '$(echo "$cycle_limit" | tr '\n' ' ')')" >&2; exit 1; }

for loop in "Plan-critique" "Pre-ship code critique" "Test-fix"; do
  echo "$limits" | grep -qiF "$loop" \
    || report "spec is missing a retry limit for '$loop'"
done

# ── 2. Every count a workflow states must match the spec for that loop ───────
# A restatement has a shape: a count, up to two filler words, then one of the
# two nouns the spec measures in — "max 3 iterations", "up to 3 iterations",
# "max 2 full plan-implement-test cycles". The noun carries the loop binding,
# so it must be a noun the spec actually uses; a generic one names no loop and
# cannot be checked against anything.
#
# A regex reads only what it recognises, so that shape is not the only one read:
#
#   b. A count bound to a noun the spec does not measure in — "max 2 retries",
#      "3 rounds". The fix is to restate in the spec's noun, not for this check
#      to guess which loop was meant.
#   c. Whatever is left that still reads as a limit: a quantifier and a spec
#      noun within four words, or a count after the noun — "max four
#      iterations", "a 4-iteration maximum", "iterations: 4". The window and the
#      spec noun are what keep an unrelated cap ("up to 3 explorers, then let
#      the loop finish") out.
#
# The shape is the fence, so the boundary is its vocabulary and window: (c)
# reads only the four quantifiers and the two spec nouns, within four words, so
# "no more than four iterations" and "max 4 further full plan critique
# iterations" still slip. Widen the lists when a phrasing earns it; leave the
# window, which is what holds the false positives down.
SPEC_NOUN='iterations?|cycles?'
OFF_SPEC_NOUN='attempts?|retr(y|ies)|rounds?|passes|loops?|tries'
QUANTIFIER='max(imum)?|at most|up to'
COUNT_RE="[0-9]+ +([a-z-]+ +){0,2}($SPEC_NOUN)\\b"
OFF_SPEC_RE="[0-9]+ +([a-z-]+ +){0,2}($OFF_SPEC_NOUN)\\b"
OUT_OF_SHAPE="\\b($QUANTIFIER)( +[a-z0-9-]+){0,4} +($SPEC_NOUN)\\b\
|\\b($SPEC_NOUN)( +[a-z0-9-]+){0,4} +($QUANTIFIER)\\b\
|\\b($SPEC_NOUN) *: *[0-9]"

# prose_of <file> — the file with fenced blocks and inline code spans dropped.
# Only (c) reads it: `max:` in a code span is an identifier (worktrees'
# concurrency key), not a limit, and (c) is the check a stray quantifier can
# trip. (a) and (b) read the file whole — they are anchored on a count, and a
# limit restated inside ship.md's PR-body fence still ships.
prose_of() {
  awk '/^ *```/{f=!f; next} !f' "$1" | sed -E 's/`[^`]*`//g'
}

iter_seen=0
cycle_seen=0

for workflow in "$WORKFLOWS_DIR"/*.md; do
  name=$(basename "$workflow")
  lower=$(tr 'A-Z' 'a-z' < "$workflow")

  # (a) counts bound to a spec noun — checked against the spec
  while IFS= read -r phrase; do
    [ -n "$phrase" ] || continue
    count=$(echo "$phrase" | grep -oE '^[0-9]+')
    # The trailing noun is the binding — a filler word that merely contains
    # "cycle" ("3 lifecycle iterations") must not reroute it.
    case "$phrase" in
      *cycle|*cycles) expected="$cycle_limit"; loop="the test-fix loop"; cycle_seen=1 ;;
      *)              expected="$iter_limit";  loop="a critique loop";  iter_seen=1  ;;
    esac
    [ "$count" = "$expected" ] \
      || report "$name says \"$phrase\", but .ai/conventions.md sets $loop to $expected"
  done <<< "$(echo "$lower" | grep -oE "$COUNT_RE" | sort -u)"

  # (b) counts bound to a noun that names no loop
  while IFS= read -r phrase; do
    [ -n "$phrase" ] || continue
    report "$name says \"$phrase\"; .ai/conventions.md measures its loops in iterations and cycles — restate in one of those, or reword if this bounds no loop"
  done <<< "$(echo "$lower" | grep -oE "$OFF_SPEC_RE" | sort -u)"

  # (c) limit vocabulary neither shape claimed. What (a) already read is blanked
  # rather than its whole line — every line that states a limit carries an (a)
  # match by construction, so dropping them whole would blind (c) to exactly the
  # lines a limit-changing edit touches. The blank leaves `~`, which is outside
  # the window's token class: without a barrier, removing text pulls a
  # quantifier and an unrelated later noun into range of each other. The right
  # edge is spelt out because BSD sed ignores \b — reusing $COUNT_RE here would
  # no-op on macOS and work on Linux.
  while IFS= read -r phrase; do
    [ -n "$phrase" ] || continue
    report "$name says \"$phrase\"; that reads as a limit but not in the restatement shape (<count> <iterations|cycles>) — reword it"
  done <<< "$(prose_of "$workflow" | tr 'A-Z' 'a-z' \
    | sed -E "s/[0-9]+ +([a-z-]+ +){0,2}($SPEC_NOUN)([^a-z]|\$)/ ~/g" \
    | grep -oE "$OUT_OF_SHAPE" | sort -u)"
done

# A limit deleted from every workflow is drift too, and the loudest kind: the
# workflows would ship with no limit at all, which is what the by-name pointer
# produced in an installed project. Silence is not agreement.
[ "$iter_seen" -eq 1 ] \
  || report "no workflow states the critique limit ($iter_limit); an installed project would run those loops unbounded"
[ "$cycle_seen" -eq 1 ] \
  || report "no workflow states the test-fix limit ($cycle_limit); an installed project would run that loop unbounded"

# ── Every shipped surface a stale pointer could hide in ──────────────────────
# Newline-separated and scanned one directory at a time: a path containing a
# space must not word-split into non-existent directories, and a directory that
# was renamed (a new harness generator, a layout change) must fail loudly rather
# than silently drop its coverage.
SHIPPED="$WORKFLOWS_DIR
$ROOT/.claude/commands
$ROOT/.claude/agents
$ROOT/.opencode/commands
$ROOT/.opencode/agents
$ROOT/.agents/skills
$ROOT/.codex/agents
$ROOT/.hermes/skills
$ROOT/.hermes/agents
$ROOT/.cursor/commands
$ROOT/.cursor/agents
$ROOT/.cursor/rules
$ROOT/templates"

while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  [ -d "$dir" ] \
    || report "${dir#"$ROOT"/} is scanned by this check but does not exist; update SHIPPED or restore the directory"
done <<< "$SHIPPED"

# scan_shipped <extended-regex> → paths of matching files, one per line
scan_shipped() {
  local pattern="$1" dir
  while IFS= read -r dir; do
    [ -d "$dir" ] || continue
    grep -rlE "$pattern" "$dir" 2>/dev/null
  done <<< "$SHIPPED"
}

# ── 3. No by-name reference to the limits ────────────────────────────────────
# Only the retry-limit pointer, not every "(per CLAUDE.md)" — a project's
# CLAUDE.md is still the right target for quality gates and worktree config.
stale=$(scan_shipped 'per CLAUDE\.md retry limits|retry limits \(per CLAUDE\.md\)')
if [ -n "$stale" ]; then
  while IFS= read -r file; do
    report "${file#"$ROOT"/} references the retry limits by name; state the value instead"
  done <<< "$stale"
fi

# ── 4. Nothing scaffolds a Workflow Rules block ──────────────────────────────
scaffolded=$(scan_shipped '^ *## Workflow Rules')
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
