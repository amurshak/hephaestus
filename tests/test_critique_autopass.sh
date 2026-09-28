#!/usr/bin/env bash
# Code critique skips review by consequence, never by file type (#223).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

critique="$HEPHAESTUS_ROOT/.ai/workflows/critique.md"
gate=$(grep -F '**Auto-pass gate**' "$critique")
risk=$(grep -F '**Score risk**' "$critique")
reviewer=$(cat "$HEPHAESTUS_ROOT/.ai/agents/reviewer.md")

begin_test "a lockfile-only dependency update is reviewed, not auto-passed"
assert_not_contains "lockfiles are not a passable file type" "$gate" 'a lockfile, or whitespace-only'
assert_contains "dependency files always get review" "$gate" 'dependency manifests and lockfiles'
assert_contains "exemptions are by consequence" "$gate" 'Judge by consequence, not file type'
assert_contains "dependencies raise the risk score" "$risk" '+1 dependencies (manifest or lockfile)'
assert_contains "reviewer scopes a dependency assessment" "$reviewer" '**Dependencies** (manifest or lockfile changed)'
assert_contains "lockfile-only is a runtime change" "$reviewer" 'A lockfile-only change is a runtime change, not a no-op'

begin_test "instruction-bearing docs are not exempt as documentation"
for surface in '`.ai/`' '`.claude/`' 'CLAUDE.md' 'AGENTS.md' 'generated adapters' 'runbook or install steps' 'CI/build/config'; do
  assert_contains "$surface requires review" "$gate" "$surface"
done

begin_test "genuinely low-impact changes keep their shortcut"
assert_contains "whitespace and reader-facing prose still auto-pass" "$gate" 'whitespace or reader-facing prose that nothing executes or obeys'
assert_contains "empty or incomplete scope never auto-passes" "$gate" 'only if scope is complete and nonempty'
assert_contains "project review policy wins" "$gate" 'A project review policy in its CLAUDE.md wins'

print_summary
