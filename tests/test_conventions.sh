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
  cp -R "$HEPHAESTUS_ROOT/.ai/agents" "$dir/.ai/agents"
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
  echo "Proceed under a 4-iteration maximum."
  echo "Repeat, max 4 further full critique iterations."
  echo "Iterations: 4"   # capitalised: the report is folded, so the check must be
  # Every noun that names no loop, and every quantifier the shape knows. Each
  # phrase is distinct: the report is deduped, so a repeat would mask a check.
  echo "Repeat, max 4 passes."
  echo "Repeat, max 4 loops."
  echo "Retry the plan 3 attempts."
  echo "Re-review 3 rounds before shipping."
  echo "Give the fix 3 tries."
  echo "Allow 1 retry, 1 attempt, 1 round and 1 loop."
  echo "Repeat, at most five iterations."
  echo "Repeat, up to six iterations."
  # Clauses sharing a line with a valid restatement — every line that states a
  # limit carries one, so they are the lines a limit-changing edit touches.
  echo "Refine until SOUND (max 3 iterations), then at most seven iterations more."
  echo "Refine until SOUND (max 3 iterations). Config says iterations: 9."
} >> "$F1B2/.ai/workflows/refactor.md"

if out=$(bash "$F1B2/tests/check_conventions.sh" 2>&1); then
  fail "verifier should reject every out-of-shape phrasing" "exited 0, output: $out"
else
  for quoted in 'says "max four iterations"' \
                'says "iteration maximum"' \
                'says "max 4 further full critique iterations"' \
                'says "iterations: 4"' \
                'says "4 passes"' 'says "4 loops"' 'says "3 attempts"' \
                'says "3 rounds"' 'says "3 tries"' \
                'says "1 retry"' 'says "1 attempt"' 'says "1 round"' 'says "1 loop"' \
                'says "at most five iterations"' 'says "up to six iterations"' \
                'says "at most seven iterations"' 'says "iterations: 9"'; do
    assert_contains "reports ${quoted#says }" "$out" "$quoted"
  done
fi

# ── The shape check may not second-guess a restatement the spec check read ───
# The quantifier need not sit against the count: "a maximum of 3 iterations" is
# a valid restatement, and reporting it as out-of-shape would tell a maintainer
# to reword prose that already agrees with the spec.
begin_test "verifier accepts a restatement whose quantifier is not adjacent"

F1B2B=$(make_fixture); FIXTURES="$FIXTURES $F1B2B"
{
  echo "Allow a maximum of 3 iterations on the critique loop."
  echo "Repeat the plan-critique loop up to the limit of 3 iterations."
} >> "$F1B2B/.ai/workflows/refactor.md"

if out=$(bash "$F1B2B/tests/check_conventions.sh" 2>&1); then
  pass "a spec-agreeing restatement is not reported as out-of-shape"
else
  fail "verifier second-guessed a restatement it had already validated" "$out"
fi

# ── (a) and (b) read the file whole; only the shape check reads prose ────────
# Stripping fences and code spans for every check would hide a limit restated
# inside ship.md's PR-body fence — the drift this file exists to catch.
begin_test "verifier reads limits inside fences and code spans"

while IFS='|' read -r placement expected; do
  [ -n "$placement" ] || continue
  F=$(make_fixture); FIXTURES="$FIXTURES $F"
  printf "$placement" >> "$F/.ai/workflows/refactor.md"
  if out=$(bash "$F/tests/check_conventions.sh" 2>&1); then
    fail "verifier missed a limit in a code context" "exited 0"
  else
    assert_contains "reads a limit stated inside code" "$out" "$expected"
  fi
done <<'PLACEMENTS'
\n```\nRepeat until SOUND (max 9 iterations).\n```\n|says "9 iterations", but .ai/conventions.md sets a critique loop to 3
\nBound it to `max 9 iterations` here.\n|says "9 iterations", but .ai/conventions.md sets a critique loop to 3
\n```\nRepeat until SOUND (max 9 retries).\n```\n|says "9 retries"; .ai/conventions.md measures its loops
PLACEMENTS

# ── The loop binding is the trailing noun, not a substring of the filler ─────
begin_test "verifier binds on the noun, not a filler word containing it"

F1B2C=$(make_fixture); FIXTURES="$FIXTURES $F1B2C"
{
  echo "Fix within 2 lifecycle iterations, then 3 more cycle."
  # The spec's own wording for the test-fix row: two filler words, one
  # hyphenated. Narrow the filler count or drop the hyphen from its character
  # class and (a) stops reading the canonical shape entirely.
  echo "Iterate until green, max 9 full plan-implement-test cycles."
} >> "$F1B2C/.ai/workflows/refactor.md"

if out=$(bash "$F1B2C/tests/check_conventions.sh" 2>&1); then
  fail "verifier should reject all three counts" "exited 0, output: $out"
else
  assert_contains "'lifecycle' in the filler does not reroute to the test-fix loop" "$out" \
    'says "2 lifecycle iterations", but .ai/conventions.md sets a critique loop to 3'
  assert_contains "a singular trailing noun still binds its loop" "$out" \
    'says "3 more cycle", but .ai/conventions.md sets the test-fix loop to 2'
  assert_contains "the spec's own two-filler hyphenated shape is read" "$out" \
    'says "9 full plan-implement-test cycles", but .ai/conventions.md sets the test-fix loop to 2'
fi

# ── The spec must keep the two nouns bound to distinct values ────────────────
# The noun binding is only meaningful while "iterations" and "cycles" resolve to
# one value each and those differ; a spec edit that collapses them would let the
# two limits swap again with every workflow still passing.
begin_test "verifier rejects a spec whose nouns no longer separate the loops"

F1B2D=$(make_fixture); FIXTURES="$FIXTURES $F1B2D"
sed -i.bak 's/| 2 full plan-implement-test cycles |/| 3 full plan-implement-test cycles |/' \
  "$F1B2D/.ai/conventions.md"
rm -f "$F1B2D/.ai/conventions.md.bak"

if out=$(bash "$F1B2D/tests/check_conventions.sh" 2>&1); then
  fail "verifier should reject a spec that binds both nouns to one value" "exited 0, output: $out"
else
  assert_contains "names the constraint the spec broke" "$out" \
    "must bind 'iterations' and 'cycles' to one distinct value each"
fi

# ── A spec that stops parsing must hard-fail, not feed check 2 empty limits ──
# Both arms of the same guard: the section gone, and the section present but
# holding no data rows. Either way check 2 would measure every workflow against
# nothing, so the parse failure is an ERR, not a drift report.
begin_test "verifier hard-fails when the retry-limit table is missing or empty"

F1B2E=$(make_fixture); FIXTURES="$FIXTURES $F1B2E"
sed -i.bak 's/^## Retry limits$/## Retry ceilings/' "$F1B2E/.ai/conventions.md"
rm -f "$F1B2E/.ai/conventions.md.bak"

if out=$(bash "$F1B2E/tests/check_conventions.sh" 2>&1); then
  fail "verifier should hard-fail without a '## Retry limits' section" "exited 0, output: $out"
else
  assert_contains "names the section it could not find" "$out" \
    "ERR: no retry-limit table under '## Retry limits'"
fi

F1B2F=$(make_fixture); FIXTURES="$FIXTURES $F1B2F"
sed -i.bak -E '/^\| (Plan-critique|Pre-ship code critique|Test-fix) \|/d' \
  "$F1B2F/.ai/conventions.md"
rm -f "$F1B2F/.ai/conventions.md.bak"

if out=$(bash "$F1B2F/tests/check_conventions.sh" 2>&1); then
  fail "verifier should hard-fail on a table with no data rows" "exited 0, output: $out"
else
  assert_contains "a header-only table parses to nothing" "$out" \
    "ERR: no retry-limit table under '## Retry limits'"
fi

# ── Each spec noun must resolve to exactly one value ─────────────────────────
# The other two arms of the guard F1B2D exercises — a noun matching two rows
# with different values, and a noun matching no row at all — each taken from
# both sides, since the guard's conjuncts are per-noun and deleting one side
# alone must not survive. The got-clause is asserted whole so the test proves
# which resolution the guard saw, not merely that some spec edit upset it.
begin_test "verifier rejects a spec noun resolving to more than one value"

F1B2G=$(make_fixture); FIXTURES="$FIXTURES $F1B2G"
sed -i.bak 's/| Pre-ship code critique | 3 iterations |/| Pre-ship code critique | 5 iterations |/' \
  "$F1B2G/.ai/conventions.md"
rm -f "$F1B2G/.ai/conventions.md.bak"

if out=$(bash "$F1B2G/tests/check_conventions.sh" 2>&1); then
  fail "verifier should reject a noun bound to two values" "exited 0, output: $out"
else
  assert_contains "reports both values 'iterations' resolves to" "$out" \
    "must bind 'iterations' and 'cycles' to one distinct value each (got '3 5 ' and '2 ')"
fi

F1B2J=$(make_fixture); FIXTURES="$FIXTURES $F1B2J"
sed -i.bak 's/| Pre-ship code critique | 3 iterations |/| Pre-ship code critique | 5 review cycles |/' \
  "$F1B2J/.ai/conventions.md"
rm -f "$F1B2J/.ai/conventions.md.bak"

if out=$(bash "$F1B2J/tests/check_conventions.sh" 2>&1); then
  fail "verifier should reject a noun bound to two values" "exited 0, output: $out"
else
  assert_contains "reports both values 'cycles' resolves to" "$out" \
    "must bind 'iterations' and 'cycles' to one distinct value each (got '3 ' and '2 5 ')"
fi

begin_test "verifier rejects a spec noun resolving to no value"

# The rows stay: deleting one outright would fire this same guard with
# byte-identical output, so changing only the noun isolates the vocabulary
# loss as the cause.
F1B2H=$(make_fixture); FIXTURES="$FIXTURES $F1B2H"
sed -i.bak 's/| Test-fix | 2 full plan-implement-test cycles |/| Test-fix | 2 full plan-implement-test rounds |/' \
  "$F1B2H/.ai/conventions.md"
rm -f "$F1B2H/.ai/conventions.md.bak"

if out=$(bash "$F1B2H/tests/check_conventions.sh" 2>&1); then
  fail "verifier should reject a noun bound to no value" "exited 0, output: $out"
else
  assert_contains "reports 'cycles' resolving to nothing" "$out" \
    "must bind 'iterations' and 'cycles' to one distinct value each (got '3 ' and ' ')"
fi

F1B2K=$(make_fixture); FIXTURES="$FIXTURES $F1B2K"
sed -i.bak 's/| 3 iterations |/| 3 rounds |/' "$F1B2K/.ai/conventions.md"
rm -f "$F1B2K/.ai/conventions.md.bak"

if out=$(bash "$F1B2K/tests/check_conventions.sh" 2>&1); then
  fail "verifier should reject a noun bound to no value" "exited 0, output: $out"
else
  assert_contains "reports 'iterations' resolving to nothing" "$out" \
    "must bind 'iterations' and 'cycles' to one distinct value each (got ' ' and '2 ')"
fi

# ── A loop row the spec no longer names is drift ─────────────────────────────
# The iteration rows are the ones to drop: each leaves "iterations" resolving
# through the other, so the value guards stay quiet and only the row check can
# catch the loss — one fixture per name, since the check is a per-name list.
# Test-fix has no such fixture by construction: dropping its only "cycles" row
# empties the noun, and the value guard exits first.
begin_test "verifier rejects a spec that drops a loop's row"

F1B2I=$(make_fixture); FIXTURES="$FIXTURES $F1B2I"
sed -i.bak '/^| Pre-ship code critique | 3 iterations |$/d' "$F1B2I/.ai/conventions.md"
rm -f "$F1B2I/.ai/conventions.md.bak"

if out=$(bash "$F1B2I/tests/check_conventions.sh" 2>&1); then
  fail "verifier should reject a spec missing a loop row" "exited 0, output: $out"
else
  assert_contains "names the loop whose row vanished" "$out" \
    "spec is missing a retry limit for 'Pre-ship code critique'"
fi

F1B2L=$(make_fixture); FIXTURES="$FIXTURES $F1B2L"
sed -i.bak '/^| Plan-critique | 3 iterations |$/d' "$F1B2L/.ai/conventions.md"
rm -f "$F1B2L/.ai/conventions.md.bak"

if out=$(bash "$F1B2L/tests/check_conventions.sh" 2>&1); then
  fail "verifier should reject a spec missing a loop row" "exited 0, output: $out"
else
  assert_contains "checks every name on its list, not just one" "$out" \
    "spec is missing a retry limit for 'Plan-critique'"
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
# The shape check needs a spec noun within four words of the quantifier, and
# reads prose only. Loop vocabulary further off, an unrelated cap, a word merely
# containing a loop noun, and a code-span identifier all stay silent.
begin_test "verifier ignores a cap that names no loop"

F1B4=$(make_fixture); FIXTURES="$FIXTURES $F1B4"
{
  echo 'Spawn max 3 explorers in parallel; keep `max iterations` out of it.'
  echo "Spawn up to 3 explorers in parallel, then let the critique loop finish."
  echo "Run the workaround at most once when the branch is stale."
  echo "Keep up to 5 changelog entries in the fragment directory."
  echo "The reviewer may request up to 3 rounded estimates."
  echo "Use 5 iterationsx as the placeholder token."
  # A word merely ending in a quantifier: the leading boundary keeps it out.
  echo "Set HEPH_MAX before the plan iterations begin."
  # Blanking a restatement must not merge its clause with the next one, nor
  # pull a later noun into the window — the `~` and the restored delimiter.
  echo "Refine until SOUND, max 3 iterations. Iterations beyond that need approval."
  echo "Cap the loop at max 3 iterations so later iterations never run."
  # A restatement ending the line: only the \$ arm of the blank's right edge
  # reaches it, and BSD sed would ignore a \\b there.
  echo "Refine until SOUND, max 3 iterations"
  # A correct restatement in the spec's own two-filler wording: the blank must
  # reach as far as (a) does, or the shape check second-guesses it.
  echo "Fix and re-run, max 2 full plan-implement-test cycles."
  # Spec nouns four and eleven words off the quantifier: only the window keeps
  # these out, and the shorter one pins it at four rather than merely below ten.
  echo "Spawn at most 3 explorers before the plan iterations begin."
  echo "Spawn up to 3 explorers in parallel and let the plan critique loop run its iterations."
  # A rejected phrasing quoted as an example: only the fence strip keeps this out.
  printf 'The gate rejects prose like this:\n\n```\nmax four iterations\n```\n'
} >> "$F1B4/.ai/workflows/refactor.md"

if out=$(bash "$F1B4/tests/check_conventions.sh" 2>&1); then
  pass "caps, near-miss words, quoted examples, and code spans do not read as limits"
else
  fail "verifier fired on prose that bounds no loop" "$out"
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
