#!/usr/bin/env bash
# test_opencode_adapters.sh — Verify OpenCode adapters stay in sync with canonical sources.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

begin_test "OpenCode adapters match workflows and Claude agents"

if output=$(bash "$HEPHAESTUS_ROOT/scripts/sync-opencode-adapters.sh" --check 2>&1); then
  pass "sync-opencode-adapters.sh --check exits 0"
else
  fail "sync-opencode-adapters.sh --check exits non-zero" "$output"
fi

begin_test "OpenCode adapter check detects command drift"

FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/heph-opencode-XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

cp -R "$HEPHAESTUS_ROOT/.ai" "$FIXTURE/.ai"
cp -R "$HEPHAESTUS_ROOT/.claude" "$FIXTURE/.claude"
cp -R "$HEPHAESTUS_ROOT/.opencode" "$FIXTURE/.opencode"
mkdir -p "$FIXTURE/scripts"
cp "$HEPHAESTUS_ROOT/scripts/sync-opencode-adapters.sh" "$FIXTURE/scripts/sync-opencode-adapters.sh"
cp "$HEPHAESTUS_ROOT/scripts/models.sh" "$FIXTURE/scripts/models.sh"

sed -i.bak 's/Run the full autonomous pipeline/Run the drifted autonomous pipeline/' \
  "$FIXTURE/.opencode/commands/autopilot.md"
rm -f "$FIXTURE/.opencode/commands/autopilot.md.bak"

if drift_output=$(bash "$FIXTURE/scripts/sync-opencode-adapters.sh" --check 2>&1); then
  fail "OpenCode adapter check should detect command drift" "exited 0, output: $drift_output"
else
  if echo "$drift_output" | grep -q "OpenCode adapter drift for /autopilot"; then
    pass "OpenCode adapter check reports /autopilot drift"
  else
    fail "OpenCode adapter check failed without naming /autopilot" "$drift_output"
  fi
fi

begin_test "OpenCode adapter check detects stale adapters after source deletion"

FIXTURE2=$(mktemp -d "${TMPDIR:-/tmp}/heph-opencode-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2"' EXIT

cp -R "$HEPHAESTUS_ROOT/.ai" "$FIXTURE2/.ai"
cp -R "$HEPHAESTUS_ROOT/.claude" "$FIXTURE2/.claude"
cp -R "$HEPHAESTUS_ROOT/.opencode" "$FIXTURE2/.opencode"
mkdir -p "$FIXTURE2/scripts"
cp "$HEPHAESTUS_ROOT/scripts/sync-opencode-adapters.sh" "$FIXTURE2/scripts/sync-opencode-adapters.sh"
cp "$HEPHAESTUS_ROOT/scripts/models.sh" "$FIXTURE2/scripts/models.sh"

rm "$FIXTURE2/.ai/workflows/research.md"
rm "$FIXTURE2/.claude/agents/tester.md"

if stale_output=$(bash "$FIXTURE2/scripts/sync-opencode-adapters.sh" --check 2>&1); then
  fail "OpenCode check should detect orphaned adapters" "exited 0, output: $stale_output"
else
  assert_contains "check names stale command adapter" "$stale_output" ".opencode/commands/research.md"
  assert_contains "check names stale agent adapter" "$stale_output" ".opencode/agents/tester.md"
fi

sync_output=$(bash "$FIXTURE2/scripts/sync-opencode-adapters.sh" 2>&1)
assert_contains "sync reports stale adapter removal" "$sync_output" "removed stale OpenCode adapter"
assert_file_not_exists "sync removes orphaned command adapter" "$FIXTURE2/.opencode/commands/research.md"
assert_file_not_exists "sync removes orphaned agent adapter" "$FIXTURE2/.opencode/agents/tester.md"

sed -i.bak '/^name:/d' "$FIXTURE2/.claude/agents/coder.md"
bash "$FIXTURE2/scripts/sync-opencode-adapters.sh" >/dev/null 2>&1
assert_exit_code "sync fails on unparseable source" 1 "$?"
assert_file_exists "sync keeps adapter of unparseable source" "$FIXTURE2/.opencode/agents/coder.md"

begin_test "OpenCode agent adapters enforce edit permissions"

coder="$HEPHAESTUS_ROOT/.opencode/agents/coder.md"
reviewer="$HEPHAESTUS_ROOT/.opencode/agents/reviewer.md"
researcher="$HEPHAESTUS_ROOT/.opencode/agents/researcher.md"

assert_contains "coder can edit" "$(cat "$coder")" "  edit: allow"
assert_contains "coder description warns orchestrator about isolation" "$(grep '^description:' "$coder")" "NOTE: OpenCode has no worktree isolation"
assert_contains "coder body warns about missing worktree isolation" "$(cat "$coder")" "> **No worktree isolation.**"
assert_not_contains "reviewer has no isolation warning" "$(cat "$reviewer")" "No worktree isolation"
assert_contains "reviewer cannot edit" "$(cat "$reviewer")" "  edit: deny"
assert_contains "researcher cannot run bash" "$(cat "$researcher")" "  bash: deny"
assert_contains "researcher can websearch" "$(cat "$researcher")" "  websearch: allow"

begin_test "OpenCode commands use OC dialect and chain notes"

ship="$HEPHAESTUS_ROOT/.opencode/commands/ship.md"
autopilot="$HEPHAESTUS_ROOT/.opencode/commands/autopilot.md"
research="$HEPHAESTUS_ROOT/.opencode/commands/research.md"
start="$HEPHAESTUS_ROOT/.opencode/commands/start-issue.md"

assert_contains "ship has OpenCode callout" "$(cat "$ship")" "**OpenCode:**"
assert_contains "ship chain note names nested cmds" "$(cat "$ship")" "/critique"
assert_contains "autopilot chain note" "$(cat "$autopilot")" "/start-issue"
assert_contains "research uses @researcher" "$(cat "$research")" "@researcher"
assert_not_contains "research drops bare subagent" "$(cat "$research")" "researcher subagent"
assert_contains "start-issue maps coder spawn" "$(cat "$start")" "@coder"
assert_not_contains "start-issue drops worktree spawn" "$(cat "$start")" "coder subagents (in worktrees)"

begin_test "OpenCode worktrees spawns opencode, not claude"

worktrees=$(cat "$HEPHAESTUS_ROOT/.opencode/commands/worktrees.md")
assert_contains "osascript spawn uses opencode --prompt" "$worktrees" 'do script "cd <worktree> && opencode --prompt \"/start-issue <N>\""'
assert_contains "manual fallback uses opencode --prompt" "$worktrees" 'cd <worktree> && opencode --prompt "/start-issue <N>"'
assert_contains "summary names OpenCode sessions" "$worktrees" "spawn a seeded OpenCode session"

# Repo-wide guard, frontmatter included — the routing `description:` is built
# from the localized first body line, so a reflow that pushes a Claude product
# name past the truncation trips this. Bare "claude" is not a needle:
# `.claude/` paths are legitimate.
leaks=$(grep -rnF -e "Claude Code" -e "&& claude " -e "claude -" -e "--permission-mode" \
  "$HEPHAESTUS_ROOT/.opencode/commands/" "$HEPHAESTUS_ROOT/.opencode/agents/" 2>/dev/null || true)
assert_eq "no Claude-product leak in any OpenCode adapter" "" "$leaks"

begin_test "opencode.json loads repo instructions"

opencode_json=$(cat "$HEPHAESTUS_ROOT/opencode.json")
assert_contains "schema declared" "$opencode_json" '"$schema": "https://opencode.ai/config.json"'
assert_contains "CLAUDE.md included" "$opencode_json" '"CLAUDE.md"'
assert_contains "AGENTS.md included" "$opencode_json" '"AGENTS.md"'

begin_test "verify-opencode-load.sh passes when CLI present or skips cleanly"

if verify_output=$(bash "$HEPHAESTUS_ROOT/scripts/verify-opencode-load.sh" 2>&1); then
  if command -v opencode >/dev/null 2>&1; then
    assert_contains "live load reports success" "$verify_output" "OpenCode loads hephaestus"
  else
    assert_contains "skips without opencode" "$verify_output" "skip: opencode not on PATH"
  fi
else
  fail "verify-opencode-load.sh exited non-zero" "$verify_output"
fi

# ─────────────────────────────────────────────────────────────────────────────

begin_test "verify-opencode-load.sh guards the unattended flags"

# A stub `opencode` on a scratch PATH makes the checks hermetic: the real CLI
# is absent on CI, and its presence would otherwise decide what gets asserted.
# `run --help` reads from a file so each flag can be dropped per-case.
STUB_DIR=$(mktemp -d "${TMPDIR:-/tmp}/heph-opencodestub-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2" "$STUB_DIR"' EXIT
printf -- '--auto  auto-approve permissions\n--command  the command to run\n' > "$STUB_DIR/run-help"
cat > "$STUB_DIR/opencode" <<STUB
#!/bin/sh
case "\$1 \$2" in
  "debug config") echo '"autopilot" "ship" "finish" "start-issue" "critique"' ;;
  "run --help") cat "$STUB_DIR/run-help" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$STUB_DIR/opencode"

out=$(PATH="$STUB_DIR:/usr/bin:/bin" bash "$HEPHAESTUS_ROOT/scripts/verify-opencode-load.sh" 2>&1)
assert_exit_code "passes while run documents the flags" 0 "$?"

# Losing --auto stalls an unattended loop.sh session on its first gated write.
printf -- '--command  the command to run\n' > "$STUB_DIR/run-help"
out=$(PATH="$STUB_DIR:/usr/bin:/bin" bash "$HEPHAESTUS_ROOT/scripts/verify-opencode-load.sh" 2>&1)
assert_exit_code "fails when --auto is gone" 1 "$?"
assert_contains  "names the dropped flag" "$out" "no longer documents --auto"
assert_contains  "points at the dispatch table" "$out" "loop.sh's dispatch table"

# The likelier drift is a rename to a superset flag. A substring match would
# call --auto-approve healthy for --auto — the check must match whole words.
printf -- '--auto-approve  approve permissions\n--command-file  read from file\n' > "$STUB_DIR/run-help"
out=$(PATH="$STUB_DIR:/usr/bin:/bin" bash "$HEPHAESTUS_ROOT/scripts/verify-opencode-load.sh" 2>&1)
assert_exit_code "fails on a superstring rename" 1 "$?"
assert_contains  "names --auto despite --auto-approve"     "$out" "no longer documents --auto"
assert_contains  "names --command despite --command-file"  "$out" "no longer documents --command"

# ─────────────────────────────────────────────────────────────────────────────

begin_test "hand-written files in .opencode dirs survive the stale sweep"

FIXTURE_OWN=$(mktemp -d "${TMPDIR:-/tmp}/heph-opencode-XXXXXX")

cp -R "$HEPHAESTUS_ROOT/.ai" "$FIXTURE_OWN/.ai"
cp -R "$HEPHAESTUS_ROOT/.claude" "$FIXTURE_OWN/.claude"
cp -R "$HEPHAESTUS_ROOT/.opencode" "$FIXTURE_OWN/.opencode"
rm -rf "$FIXTURE_OWN/.opencode/node_modules"
mkdir -p "$FIXTURE_OWN/scripts"
cp "$HEPHAESTUS_ROOT/scripts/sync-opencode-adapters.sh" "$FIXTURE_OWN/scripts/sync-opencode-adapters.sh"
cp "$HEPHAESTUS_ROOT/scripts/models.sh" "$FIXTURE_OWN/scripts/models.sh"

# Both swept dirs: a user command and a user agent, neither carrying a marker.
printf -- '---\ndescription: my own command\n---\nbody\n' > "$FIXTURE_OWN/.opencode/commands/my-own.md"
printf -- '---\ndescription: my own agent\n---\nbody\n'   > "$FIXTURE_OWN/.opencode/agents/my-own.md"

if own_check=$(bash "$FIXTURE_OWN/scripts/sync-opencode-adapters.sh" --check 2>&1); then
  fail "check should flag the unexpected files" "exited 0: $own_check"
else
  assert_contains "check names the command dir" "$own_check" ".opencode/commands"
  assert_contains "check names the agent dir"   "$own_check" ".opencode/agents"
  assert_contains "check says non-generated"    "$own_check" "unexpected non-generated file"
fi

bash "$FIXTURE_OWN/scripts/sync-opencode-adapters.sh" >/dev/null 2>&1
assert_exit_code   "sync exits non-zero rather than claiming success" 1 "$?"
assert_file_exists "hand-written command survives" "$FIXTURE_OWN/.opencode/commands/my-own.md"
assert_file_exists "hand-written agent survives"   "$FIXTURE_OWN/.opencode/agents/my-own.md"
rm -rf "$FIXTURE_OWN"

print_summary
