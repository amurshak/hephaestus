#!/usr/bin/env bash
# test_agent_adapters.sh — Verify tool adapters stay in sync with .ai workflows.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

begin_test "Claude adapters match canonical .ai workflows"

if output=$(bash "$HEPHAESTUS_ROOT/scripts/sync-agent-adapters.sh" --check 2>&1); then
  pass "sync-agent-adapters.sh --check exits 0"
else
  fail "sync-agent-adapters.sh --check exits non-zero" "$output"
fi

begin_test "adapter check detects generated wrapper drift"

FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/heph-adapters-XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

cp -R "$HEPHAESTUS_ROOT/.ai" "$FIXTURE/.ai"
cp -R "$HEPHAESTUS_ROOT/.claude" "$FIXTURE/.claude"
mkdir -p "$FIXTURE/scripts"
cp "$HEPHAESTUS_ROOT/scripts/sync-agent-adapters.sh" "$FIXTURE/scripts/sync-agent-adapters.sh"

sed -i.bak 's/Run the full autonomous pipeline/Run the drifted autonomous pipeline/' \
  "$FIXTURE/.claude/commands/autopilot.md"
rm -f "$FIXTURE/.claude/commands/autopilot.md.bak"

if drift_output=$(bash "$FIXTURE/scripts/sync-agent-adapters.sh" --check 2>&1); then
  fail "adapter check should detect wrapper drift" "exited 0, output: $drift_output"
else
  if echo "$drift_output" | grep -q "Claude adapter drift for /autopilot"; then
    pass "adapter check reports /autopilot drift"
  else
    fail "adapter check failed without naming /autopilot" "$drift_output"
  fi
fi

begin_test "adapter check detects stale adapter after source deletion"

FIXTURE2=$(mktemp -d "${TMPDIR:-/tmp}/heph-adapters-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2"' EXIT

cp -R "$HEPHAESTUS_ROOT/.ai" "$FIXTURE2/.ai"
cp -R "$HEPHAESTUS_ROOT/.claude" "$FIXTURE2/.claude"
mkdir -p "$FIXTURE2/scripts"
cp "$HEPHAESTUS_ROOT/scripts/sync-agent-adapters.sh" "$FIXTURE2/scripts/sync-agent-adapters.sh"

rm "$FIXTURE2/.ai/workflows/research.md"

if stale_output=$(bash "$FIXTURE2/scripts/sync-agent-adapters.sh" --check 2>&1); then
  fail "adapter check should detect orphaned adapter" "exited 0, output: $stale_output"
else
  assert_contains "adapter check names the stale adapter" "$stale_output" "stale Claude adapter"
  assert_contains "stale adapter path includes research.md" "$stale_output" "research.md"
fi

sync_output=$(bash "$FIXTURE2/scripts/sync-agent-adapters.sh" 2>&1)
assert_contains "sync reports stale adapter removal" "$sync_output" "removed stale Claude adapter"
assert_file_not_exists "sync removes the orphaned adapter" "$FIXTURE2/.claude/commands/research.md"

begin_test "all canonical workflows declare adapter metadata"

missing=""
for workflow in "$HEPHAESTUS_ROOT"/.ai/workflows/*.md; do
  [ -e "$workflow" ] || continue
  for key in name requires chains; do
    if ! awk -F': *' -v key="$key" '
      /^---$/ { if (++f == 2) exit }
      f == 1 && $1 == key { found=1 }
      END { exit found ? 0 : 1 }
    ' "$workflow"; then
      missing="${missing:+$missing, }$(basename "$workflow"):$key"
    fi
  done
done

if [ -z "$missing" ]; then
  pass "workflow metadata is complete"
else
  fail "workflow metadata is incomplete" "$missing"
fi

print_summary
