#!/usr/bin/env bash
# test_composition.sh — Verify README Composition tree stays in sync with
# command metadata (`requires:` / `chains:` headers). Wraps check_composition.sh.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

begin_test "README Composition tree matches command metadata"

if output=$(bash "$SCRIPT_DIR/check_composition.sh" 2>&1); then
  pass "check_composition.sh exits 0"
else
  fail "check_composition.sh exits non-zero" "$output"
fi

# Again under a byte-only locale. The tree is drawn with multibyte glyphs, and
# /update-docs runs this verifier in whatever locale the session inherits — a
# parse that collapses under LC_ALL=C reports the README as structurally wrong.
if output=$(LC_ALL=C bash "$SCRIPT_DIR/check_composition.sh" 2>&1); then
  pass "check_composition.sh exits 0 under LC_ALL=C"
else
  fail "check_composition.sh exits non-zero under LC_ALL=C" "$output"
fi

# Negative test: mutate a requires: header in a tempdir copy and confirm the
# verifier flags the drift. Operates on a fixture, never the real repo.
begin_test "verifier detects drift when a requires: header changes"

FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/heph-comp-XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

cp -R "$HEPHAESTUS_ROOT/.claude" "$FIXTURE/.claude"
cp -R "$HEPHAESTUS_ROOT/tests" "$FIXTURE/tests"
cp "$HEPHAESTUS_ROOT/README.md" "$FIXTURE/README.md"

# Sed-mutate /ship's requires: header; the README still says "requires: tester"
sed -i.bak 's|<!-- requires: tester -->|<!-- requires: tester, drifted -->|' \
  "$FIXTURE/.claude/commands/ship.md"
rm -f "$FIXTURE/.claude/commands/ship.md.bak"

if drift_output=$(bash "$FIXTURE/tests/check_composition.sh" 2>&1); then
  fail "verifier should detect drift" "exited 0, output: $drift_output"
else
  if echo "$drift_output" | grep -q "/ship: README says"; then
    pass "verifier reports the /ship drift"
  else
    fail "verifier exited non-zero but did not name /ship" "$drift_output"
  fi
fi

# Negative test 2: drop a chain edge from a file but keep it in the README.
# The original verifier walked file→README only and missed this case.
begin_test "verifier detects drift when a chain edge is removed from a file"

FIXTURE2=$(mktemp -d "${TMPDIR:-/tmp}/heph-comp-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2"' EXIT

cp -R "$HEPHAESTUS_ROOT/.claude" "$FIXTURE2/.claude"
cp -R "$HEPHAESTUS_ROOT/tests" "$FIXTURE2/tests"
cp "$HEPHAESTUS_ROOT/README.md" "$FIXTURE2/README.md"

# Drop /critique from /ship's chains: header. README still shows /critique under /ship.
sed -i.bak 's|<!-- chains: /critique -->|<!-- chains: none -->|' \
  "$FIXTURE2/.claude/commands/ship.md"
rm -f "$FIXTURE2/.claude/commands/ship.md.bak"

if drift_output2=$(bash "$FIXTURE2/tests/check_composition.sh" 2>&1); then
  fail "verifier should detect chain-edge drift" "exited 0, output: $drift_output2"
else
  if echo "$drift_output2" | grep -q "/ship: README children"; then
    pass "verifier reports the /ship chain-edge drift"
  else
    fail "verifier exited non-zero but did not name /ship chains" "$drift_output2"
  fi
fi

print_summary
