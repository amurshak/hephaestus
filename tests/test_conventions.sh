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

# ── Limit-shaped prose outside the restatement shape must fail ───────────────
# Each of these slipped past the single regex that used to be check 2. Widening
# it to cover them would trade false negatives for false positives over free
# prose; the restatement has a shape instead, and anything limit-shaped that is
# not in it is reported so it gets reworded.
begin_test "verifier rejects limit phrasings outside the restatement shape"

F1B2=$(make_fixture); FIXTURES="$FIXTURES $F1B2"
{
  echo "Repeat, max four iterations."
  echo "Repeat, max 4 passes."
  echo "Repeat, max 4 loops."
  echo "Proceed under a 4-iteration maximum."
  echo "Repeat, max 4 further full critique iterations."
  echo "iterations: 4"
} >> "$F1B2/.ai/workflows/refactor.md"

if out=$(bash "$F1B2/tests/check_conventions.sh" 2>&1); then
  fail "verifier should reject every out-of-shape phrasing" "exited 0, output: $out"
else
  for quoted in 'says "repeat, max four iterations."' \
                'says "4 passes"' \
                'says "4 loops"' \
                'says "proceed under a 4-iteration maximum."' \
                'says "repeat, max 4 further full critique iterations."' \
                'says "iterations: 4"'; do
    assert_contains "reports ${quoted#says }" "$out" "$quoted"
  done
fi

# ── A generic noun names no loop, so it may not be read as one ───────────────
# "retries" used to be hard-bound to the test-fix loop, so a correct "3 retries"
# on a critique path was reported as drift against a limit it never meant. It is
# now reported as unrestated — the fix is the spec's noun, not a guessed loop.
begin_test "verifier does not bind a generic noun to a loop"

F1B3=$(make_fixture); FIXTURES="$FIXTURES $F1B3"
printf '\nRe-run the critique after 3 retries.\n' >> "$F1B3/.ai/workflows/ship.md"

if out=$(bash "$F1B3/tests/check_conventions.sh" 2>&1); then
  fail "verifier should reject a limit stated in a generic noun" "exited 0, output: $out"
else
  assert_contains "asks for the spec's noun" "$out" \
    'ship.md says "3 retries"; .ai/conventions.md measures its loops in iterations and cycles'
  assert_not_contains "does not claim drift against the test-fix limit" "$out" \
    "sets the test-fix loop to"
fi

# ── A cap that bounds no loop is not a retry limit ───────────────────────────
# The out-of-shape check keys on a quantifier beside loop vocabulary, and reads
# prose only, so an unrelated cap and a code-span identifier stay silent.
begin_test "verifier ignores a cap that names no loop"

F1B4=$(make_fixture); FIXTURES="$FIXTURES $F1B4"
printf '\nSpawn max 3 explorers in parallel; set `max:` to 3 in the worktrees block.\n' \
  >> "$F1B4/.ai/workflows/refactor.md"

if out=$(bash "$F1B4/tests/check_conventions.sh" 2>&1); then
  pass "an unrelated cap and a code-span identifier do not read as limits"
else
  fail "verifier fired on a cap that bounds no loop" "$out"
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

# ── A scanned surface that disappears must fail, not silently lose coverage ──
# The likely path: a new harness generator renames a directory and nobody
# extends SHIPPED. The check would go green while a stale pointer sat in the
# tree — the exact regression shape of #111.
begin_test "verifier fails when a scanned directory goes missing"

F1D=$(make_fixture); FIXTURES="$FIXTURES $F1D"
mv "$F1D/.cursor" "$F1D/.cursor-renamed"

if out=$(bash "$F1D/tests/check_conventions.sh" 2>&1); then
  fail "verifier should fail on a missing scanned directory" "exited 0, output: $out"
else
  if echo "$out" | grep -q ".cursor/commands is scanned by this check but does not exist"; then
    pass "verifier names the directory that vanished"
  else
    fail "verifier exited non-zero but did not name the directory" "$out"
  fi
fi

# ── Deleting the limits everywhere is drift too ──────────────────────────────
# Silence is not agreement: workflows carrying no limit at all is what the
# by-name pointer produced in an installed project.
begin_test "verifier detects limits deleted from every workflow"

F1E=$(make_fixture); FIXTURES="$FIXTURES $F1E"
sed -i.bak -E 's/[0-9]+ +([a-z-]+ +){0,2}(iterations?|cycles?)//gI' \
  "$F1E"/.ai/workflows/*.md
rm -f "$F1E"/.ai/workflows/*.bak

if out=$(bash "$F1E/tests/check_conventions.sh" 2>&1); then
  fail "verifier should detect the deleted limits" "exited 0, output: $out"
else
  if echo "$out" | grep -q "no workflow states the critique limit"; then
    pass "verifier reports the unbounded loops"
  else
    fail "verifier exited non-zero but did not report the deletion" "$out"
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
