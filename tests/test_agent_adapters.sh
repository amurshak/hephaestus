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

sed -i.bak '/^name:/d' "$FIXTURE2/.ai/workflows/ship.md"
bash "$FIXTURE2/scripts/sync-agent-adapters.sh" >/dev/null 2>&1
assert_exit_code "sync fails on unparseable source" 1 "$?"
assert_file_exists "sync keeps adapter of unparseable source" "$FIXTURE2/.claude/commands/ship.md"

begin_test "plugin manifest agents list matches .claude/agents/ contents"

# plugin.json must enumerate agent files individually (Claude Code's plugin
# schema rejects directory paths for agents), so the list can drift when
# agents are added or removed. Lock it to the directory contents.
manifest_agents=$(grep -oE '\./\.claude/agents/[a-z-]+\.md' "$HEPHAESTUS_ROOT/.claude-plugin/plugin.json" | sed 's|.*/||' | sort)
dir_agents=$(ls "$HEPHAESTUS_ROOT/.claude/agents/" | grep '\.md$' | sort)
assert_eq "plugin.json agents == .claude/agents/*.md" "$dir_agents" "$manifest_agents"

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

# ─────────────────────────────────────────────────────────────────────────────

begin_test "hand-written files in .claude/commands survive the stale sweep"

FIXTURE_OWN=$(mktemp -d "${TMPDIR:-/tmp}/heph-adapters-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2" "$FIXTURE_OWN"' EXIT

cp -R "$HEPHAESTUS_ROOT/.ai" "$FIXTURE_OWN/.ai"
cp -R "$HEPHAESTUS_ROOT/.claude" "$FIXTURE_OWN/.claude"
mkdir -p "$FIXTURE_OWN/scripts"
cp "$HEPHAESTUS_ROOT/scripts/sync-agent-adapters.sh" "$FIXTURE_OWN/scripts/sync-agent-adapters.sh"

# A user's own command carries no generated-from marker, so it is not ours to delete.
printf -- '---\ndescription: my own command\n---\nbody\n' > "$FIXTURE_OWN/.claude/commands/my-own.md"

if own_check=$(bash "$FIXTURE_OWN/scripts/sync-agent-adapters.sh" --check 2>&1); then
  fail "check should flag the unexpected file" "exited 0: $own_check"
else
  assert_contains "check names the file"      "$own_check" "my-own.md"
  assert_contains "check says non-generated"  "$own_check" "unexpected non-generated file"
fi

own_sync=$(bash "$FIXTURE_OWN/scripts/sync-agent-adapters.sh" 2>&1)
assert_exit_code   "sync exits non-zero rather than claiming success" 1 "$?"
assert_file_exists "hand-written command survives sync" "$FIXTURE_OWN/.claude/commands/my-own.md"
assert_not_contains "sync never reports removing it" "$own_sync" "removed stale Claude adapter $FIXTURE_OWN/.claude/commands/my-own.md"

print_summary
