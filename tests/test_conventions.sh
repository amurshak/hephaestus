#!/usr/bin/env bash
# test_conventions.sh — Verify the product/contributor split holds: the
# workflows agree with .ai/conventions.md, and the duplication that split
# removed cannot come back. Wraps check_conventions.sh.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Build a tempdir copy of everything check_conventions.sh reads, so every
# negative test mutates a fixture and never the real repo. Every scanned
# directory is copied — the verifier sends its `grep -r` errors to /dev/null,
# so a fixture missing one would pass for the wrong reason.
make_fixture() {
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/heph-conv-XXXXXX")
  mkdir -p "$dir/.ai"
  cp "$HEPHAESTUS_ROOT/.ai/conventions.md" "$dir/.ai/conventions.md"
  cp -R "$HEPHAESTUS_ROOT/.ai/workflows" "$dir/.ai/workflows"
  for d in tests templates .claude .opencode .agents .codex .hermes .cursor; do
    cp -R "$HEPHAESTUS_ROOT/$d" "$dir/$d"
  done
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
  if echo "$out" | grep -q 'start-issue.md says "7 iterations"'; then
    pass "verifier names the offending workflow and count"
  else
    fail "verifier exited non-zero but did not name the count" "$out"
  fi
fi

# ── The counts may not swap between loops ────────────────────────────────────
# 2 and 3 are both numbers the spec uses, so a set-membership check would let
# plan-critique take the test-fix limit silently. The noun carries the binding.
begin_test "verifier detects a limit swapped between loops"

F1B=$(make_fixture); FIXTURES="$FIXTURES $F1B"
sed -i.bak 's|(max 3 iterations)|(max 2 iterations)|' "$F1B/.ai/workflows/start-issue.md"
rm -f "$F1B/.ai/workflows/start-issue.md.bak"

if out=$(bash "$F1B/tests/check_conventions.sh" 2>&1); then
  fail "verifier should detect the swapped limit" "exited 0, output: $out"
else
  if echo "$out" | grep -q 'start-issue.md says "2 iterations"'; then
    pass "verifier binds the count to the loop, not just the allowed set"
  else
    fail "verifier exited non-zero but did not name the swap" "$out"
  fi
fi

# A stale adapter must fail too — adapters are what an installed project runs.
begin_test "verifier scans the generated adapters, not just the canonical sources"

F1C=$(make_fixture); FIXTURES="$FIXTURES $F1C"
sed -i.bak 's|(max 3 iterations)|(per CLAUDE.md retry limits)|' \
  "$F1C/.cursor/commands/start-issue.md"
rm -f "$F1C/.cursor/commands/start-issue.md.bak"

if out=$(bash "$F1C/tests/check_conventions.sh" 2>&1); then
  fail "verifier should scan .cursor/commands" "exited 0, output: $out"
else
  if echo "$out" | grep -q ".cursor/commands/start-issue.md references the retry limits by name"; then
    pass "verifier reaches a generated adapter family"
  else
    fail "verifier exited non-zero but did not name the adapter" "$out"
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
assert_contains "orient skips bootstrap where the workflow is defined" "$orient" \
  'scripts/sync-*-adapters.sh'
assert_not_contains "orient's guard does not name this repo" "$orient" \
  "hephaestus source clone"

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
