#!/usr/bin/env bash
# test_conventions.sh — Verify the product/contributor split holds: the
# workflows agree with .ai/conventions.md, and the duplication that split
# removed cannot come back. Wraps check_conventions.sh.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Build a tempdir copy of everything check_conventions.sh reads, so every
# negative test mutates a fixture and never the real repo.
make_fixture() {
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/heph-conv-XXXXXX")
  mkdir -p "$dir/.ai"
  cp "$HEPHAESTUS_ROOT/.ai/conventions.md" "$dir/.ai/conventions.md"
  cp -R "$HEPHAESTUS_ROOT/.ai/workflows" "$dir/.ai/workflows"
  cp -R "$HEPHAESTUS_ROOT/tests" "$dir/tests"
  cp -R "$HEPHAESTUS_ROOT/templates" "$dir/templates"
  cp -R "$HEPHAESTUS_ROOT/.claude" "$dir/.claude"
  echo "$dir"
}

FIXTURES=""
cleanup() { [ -z "$FIXTURES" ] || rm -rf $FIXTURES; }
trap cleanup EXIT

begin_test "workflows agree with .ai/conventions.md"

if output=$(bash "$SCRIPT_DIR/check_conventions.sh" 2>&1); then
  pass "check_conventions.sh exits 0"
else
  fail "check_conventions.sh exits non-zero" "$output"
fi

# ── The spec is the source: a workflow may not invent its own limit ──────────
begin_test "verifier detects a workflow stating a limit the spec does not allow"

F1=$(make_fixture); FIXTURES="$FIXTURES $F1"
sed -i.bak 's|(max 3 iterations)|(max 7 iterations)|' "$F1/.ai/workflows/start-issue.md"
rm -f "$F1/.ai/workflows/start-issue.md.bak"

if out=$(bash "$F1/tests/check_conventions.sh" 2>&1); then
  fail "verifier should detect an out-of-spec retry count" "exited 0, output: $out"
else
  if echo "$out" | grep -q "start-issue.md states a retry count of 7"; then
    pass "verifier names the offending workflow and count"
  else
    fail "verifier exited non-zero but did not name the count" "$out"
  fi
fi

# ── The pointer that caused the duplication may not come back ────────────────
# "per CLAUDE.md retry limits" is unresolvable in an installed project, which is
# why /orient had to retype the limits into every target project's CLAUDE.md.
begin_test "verifier rejects a by-name reference to the retry limits"

F2=$(make_fixture); FIXTURES="$FIXTURES $F2"
sed -i.bak 's|(max 3 iterations)|(per CLAUDE.md retry limits)|' "$F2/.ai/workflows/ship.md"
rm -f "$F2/.ai/workflows/ship.md.bak"

if out=$(bash "$F2/tests/check_conventions.sh" 2>&1); then
  fail "verifier should reject the by-name reference" "exited 0, output: $out"
else
  if echo "$out" | grep -q "ship.md references the retry limits by name"; then
    pass "verifier names the file carrying the pointer"
  else
    fail "verifier exited non-zero but did not name ship.md" "$out"
  fi
fi

# ── Nothing scaffolds a Workflow Rules block ─────────────────────────────────
begin_test "verifier rejects a scaffolded '## Workflow Rules' block"

F3=$(make_fixture); FIXTURES="$FIXTURES $F3"
printf '\n## Workflow Rules\nRetry limits: plan-critique max 3 iterations.\n' \
  >> "$F3/templates/CLAUDE.md.snippet"

if out=$(bash "$F3/tests/check_conventions.sh" 2>&1); then
  fail "verifier should reject the scaffolded block" "exited 0, output: $out"
else
  if echo "$out" | grep -q "templates/CLAUDE.md.snippet scaffolds a '## Workflow Rules' block"; then
    pass "verifier names the file scaffolding the block"
  else
    fail "verifier exited non-zero but did not name the template" "$out"
  fi
fi

# ── The split itself: audience declared, no cross-contamination ──────────────
begin_test "each surface declares its audience"

for doc in CLAUDE.md CONTRIBUTING.md AGENTS.md .ai/conventions.md; do
  assert_contains "$doc declares its audience" \
    "$(head -12 "$HEPHAESTUS_ROOT/$doc")" "Audience:"
done

assert_contains "README points at both other surfaces" \
  "$(cat "$HEPHAESTUS_ROOT/README.md")" ".ai/conventions.md"

begin_test "the shipped orient carries no maintainer-only procedure"

orient=$(cat "$HEPHAESTUS_ROOT/.claude/commands/orient.md")
assert_not_contains "orient no longer retypes the retry limits" "$orient" \
  "Retry limits: plan-critique"
assert_contains "orient skips bootstrap in the hephaestus source clone" "$orient" \
  "scripts/sync-agent-adapters.sh"

begin_test "/finish carries no repo-specific trigger list"

finish=$(cat "$HEPHAESTUS_ROOT/.claude/commands/finish.md")
assert_not_contains "finish.md drops the 'in this repo' parentheticals" "$finish" \
  "in this repo:"
assert_contains "finish.md still honours a project override" "$finish" \
  "Docs Requirements"

begin_test "this repo overrides the docs triggers"

claude_md=$(cat "$HEPHAESTUS_ROOT/CLAUDE.md")
assert_contains "CLAUDE.md declares Docs Requirements" "$claude_md" \
  "## Docs Requirements"
assert_contains "CLAUDE.md names a home for the config-surface rule" "$claude_md" \
  "## Configuration Surfaces"
assert_not_contains "README is no longer serialized" "$claude_md" \
  '`serialize_paths:` `install.sh`, `README.md`'

print_summary
