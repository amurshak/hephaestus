#!/usr/bin/env bash
# test_codex_adapters.sh — Verify Codex adapters stay in sync with canonical sources.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

begin_test "Codex adapters match workflows and Claude agents"

if output=$(bash "$HEPHAESTUS_ROOT/scripts/sync-codex-adapters.sh" --check 2>&1); then
  pass "sync-codex-adapters.sh --check exits 0"
else
  fail "sync-codex-adapters.sh --check exits non-zero" "$output"
fi

begin_test "Codex adapter check detects skill drift"

FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/heph-codex-XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

copy_fixture() {
  local dest=$1
  cp -R "$HEPHAESTUS_ROOT/.ai" "$dest/.ai"
  cp -R "$HEPHAESTUS_ROOT/.claude" "$dest/.claude"
  cp -R "$HEPHAESTUS_ROOT/.agents" "$dest/.agents"
  cp -R "$HEPHAESTUS_ROOT/.codex" "$dest/.codex"
  mkdir -p "$dest/scripts"
  cp "$HEPHAESTUS_ROOT/scripts/sync-codex-adapters.sh" "$dest/scripts/sync-codex-adapters.sh"
  cp "$HEPHAESTUS_ROOT/scripts/models.sh" "$dest/scripts/models.sh"
}

copy_fixture "$FIXTURE"

sed -i.bak 's/Run the full autonomous pipeline/Run the drifted autonomous pipeline/' \
  "$FIXTURE/.agents/skills/autopilot/SKILL.md"
rm -f "$FIXTURE/.agents/skills/autopilot/SKILL.md.bak"

if drift_output=$(bash "$FIXTURE/scripts/sync-codex-adapters.sh" --check 2>&1); then
  fail "Codex adapter check should detect skill drift" "exited 0, output: $drift_output"
else
  if echo "$drift_output" | grep -q 'Codex adapter drift for $autopilot'; then
    pass "Codex adapter check reports \$autopilot drift"
  else
    fail "Codex adapter check failed without naming \$autopilot" "$drift_output"
  fi
fi

begin_test "Codex adapter check detects stale adapters after source deletion"

FIXTURE2=$(mktemp -d "${TMPDIR:-/tmp}/heph-codex-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2"' EXIT

copy_fixture "$FIXTURE2"

rm "$FIXTURE2/.ai/workflows/research.md"
rm "$FIXTURE2/.claude/agents/tester.md"

if stale_output=$(bash "$FIXTURE2/scripts/sync-codex-adapters.sh" --check 2>&1); then
  fail "Codex check should detect orphaned adapters" "exited 0, output: $stale_output"
else
  assert_contains "check names stale skill dir" "$stale_output" ".agents/skills/research"
  assert_contains "check names stale agent adapter" "$stale_output" ".codex/agents/tester.toml"
fi

sync_output=$(bash "$FIXTURE2/scripts/sync-codex-adapters.sh" 2>&1)
assert_contains "sync reports stale skill removal" "$sync_output" "removed stale Codex skill"
assert_file_not_exists "sync removes orphaned skill" "$FIXTURE2/.agents/skills/research/SKILL.md"
assert_file_not_exists "sync removes orphaned agent adapter" "$FIXTURE2/.codex/agents/tester.toml"

sed -i.bak '/^name:/d' "$FIXTURE2/.claude/agents/coder.md"
bash "$FIXTURE2/scripts/sync-codex-adapters.sh" >/dev/null 2>&1
assert_exit_code "sync fails on unparseable source" 1 "$?"
assert_file_exists "sync keeps adapter of unparseable source" "$FIXTURE2/.codex/agents/coder.toml"

begin_test "Codex sync never deletes non-generated skill dirs"

FIXTURE3=$(mktemp -d "${TMPDIR:-/tmp}/heph-codex-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2" "$FIXTURE3"' EXIT

copy_fixture "$FIXTURE3"

mkdir -p "$FIXTURE3/.agents/skills/hand-rolled"
printf -- '---\nname: hand-rolled\ndescription: user-owned skill\n---\nDo things.\n' \
  > "$FIXTURE3/.agents/skills/hand-rolled/SKILL.md"

if foreign_output=$(bash "$FIXTURE3/scripts/sync-codex-adapters.sh" 2>&1); then
  fail "sync should exit non-zero on non-generated skill dir" "exited 0, output: $foreign_output"
else
  assert_contains "sync flags non-generated dir" "$foreign_output" "non-generated dir"
fi
assert_file_exists "non-generated skill dir preserved" "$FIXTURE3/.agents/skills/hand-rolled/SKILL.md"

begin_test "Codex sync rejects agent bodies containing TOML delimiter"

FIXTURE4=$(mktemp -d "${TMPDIR:-/tmp}/heph-codex-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2" "$FIXTURE3" "$FIXTURE4"' EXIT

copy_fixture "$FIXTURE4"

printf "\nUse ''' for emphasis.\n" >> "$FIXTURE4/.claude/agents/explorer.md"
bash "$FIXTURE4/scripts/sync-codex-adapters.sh" >/dev/null 2>&1
assert_exit_code "sync fails on ''' in agent body" 1 "$?"
assert_file_exists "adapter of unrenderable agent preserved" "$FIXTURE4/.codex/agents/explorer.toml"

begin_test "Codex agent adapters map sandbox modes and isolation notes"

coder="$HEPHAESTUS_ROOT/.codex/agents/coder.toml"
reviewer="$HEPHAESTUS_ROOT/.codex/agents/reviewer.toml"
researcher="$HEPHAESTUS_ROOT/.codex/agents/researcher.toml"

assert_contains "coder gets workspace-write" "$(cat "$coder")" 'sandbox_mode = "workspace-write"'
assert_contains "coder description warns orchestrator about isolation" "$(grep '^description' "$coder")" "NOTE: Codex has no worktree isolation"
assert_contains "coder instructions warn about missing worktree isolation" "$(cat "$coder")" "> **No worktree isolation.**"
assert_not_contains "reviewer has no isolation warning" "$(cat "$reviewer")" "No worktree isolation"
assert_contains "reviewer keeps write-capable shell sandbox" "$(cat "$reviewer")" 'sandbox_mode = "workspace-write"'
assert_contains "researcher is read-only" "$(cat "$researcher")" 'sandbox_mode = "read-only"'

begin_test "Codex skills carry metadata and argument note"

ship="$HEPHAESTUS_ROOT/.agents/skills/ship/SKILL.md"
orient="$HEPHAESTUS_ROOT/.agents/skills/orient/SKILL.md"

assert_contains "ship skill has name" "$(cat "$ship")" "name: ship"
assert_contains "ship skill anchors slash name in description" "$(grep '^description' "$ship")" "Use for /ship requests."
assert_not_contains "ship description drops \$ARGUMENTS placeholder" "$(grep '^description' "$ship")" "ARGUMENTS"
assert_contains "ship skill notes missing substitution" "$(cat "$ship")" 'Codex does not substitute `$ARGUMENTS`'
assert_contains "ship skill declares requires" "$(cat "$ship")" "<!-- requires: tester -->"
assert_contains "ship skill names its source" "$(cat "$ship")" "generated from .ai/workflows/ship.md"
assert_not_contains "argument note only when body uses \$ARGUMENTS" "$(cat "$orient")" 'Codex does not substitute'

begin_test "Codex skills use Codex dialect and chain notes"

start="$HEPHAESTUS_ROOT/.agents/skills/start-issue/SKILL.md"
refactor="$HEPHAESTUS_ROOT/.agents/skills/refactor/SKILL.md"
research="$HEPHAESTUS_ROOT/.agents/skills/research/SKILL.md"

assert_contains "start skill has Codex callout" "$(cat "$start")" "**Codex:**"
assert_contains "start skill chain note names nested skill" "$(cat "$start")" "/test-issue"
assert_contains "start skill maps todo tool" "$(cat "$start")" "the plan tool"
assert_not_contains "start skill drops TodoWrite" "$(cat "$start")" "TodoWrite"
assert_contains "start skill maps coder role agents" "$(cat "$start")" "coder role agents when available"
assert_not_contains "start skill drops worktree subagent wording" "$(cat "$start")" "coder subagents (in worktrees)"
assert_contains "refactor skill warns no worktree isolation" "$(cat "$refactor")" "Codex has no worktree isolation"
assert_contains "research skill maps researcher role agents" "$(cat "$research")" "researcher role agents"
assert_not_contains "research skill drops subagent wording" "$(cat "$research")" "researcher subagents"

begin_test "Codex worktrees skill spawns codex, not claude"

worktrees=$(cat "$HEPHAESTUS_ROOT/.agents/skills/worktrees/SKILL.md")
assert_contains "osascript spawn uses codex" "$worktrees" 'do script "cd <worktree> && codex \"/start-issue <N>\""'
assert_contains "manual fallback uses codex" "$worktrees" 'cd <worktree> && codex "/start-issue <N>"'
assert_contains "summary names Codex sessions" "$worktrees" "spawn a seeded Codex session"

# Repo-wide guard, frontmatter included — the routing `description:` is built
# from the localized first body line, so a reflow that pushes a Claude product
# name past the truncation trips this. Bare "claude" is not a needle:
# `.claude/` paths are legitimate.
leaks=$(grep -rnF -e "Claude Code" -e "&& claude " -e "claude -" -e "--permission-mode" \
  "$HEPHAESTUS_ROOT/.agents/skills/" "$HEPHAESTUS_ROOT/.codex/agents/" 2>/dev/null || true)
assert_eq "no Claude-product leak in any Codex adapter" "" "$leaks"

# ─────────────────────────────────────────────────────────────────────────────

begin_test "verify-codex-load.sh passes when CLI present or skips cleanly"

if verify_output=$(bash "$HEPHAESTUS_ROOT/scripts/verify-codex-load.sh" 2>&1); then
  if command -v codex >/dev/null 2>&1; then
    assert_contains "live load reports success" "$verify_output" "Codex takes the positional-prompt spawn form"
  else
    assert_contains "skips without codex" "$verify_output" "skip: codex not on PATH"
  fi
else
  fail "verify-codex-load.sh exited non-zero" "$verify_output"
fi

# ─────────────────────────────────────────────────────────────────────────────

begin_test "verify-codex-load.sh judges the spawn form and adapter roots"

# A stub `codex` on a scratch PATH makes the checks hermetic: the real CLI is
# absent on CI, and its presence would otherwise decide what gets asserted.
STUB_DIR=$(mktemp -d "${TMPDIR:-/tmp}/heph-codexstub-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2" "$FIXTURE3" "$FIXTURE4" "$STUB_DIR"' EXIT

make_stub() {  # make_stub <usage-line>
  printf '#!/bin/sh\necho "Usage: %s"\n' "$1" > "$STUB_DIR/codex"
  chmod +x "$STUB_DIR/codex"
}

# --require must fail when the CLI is missing, whatever the argument order.
mkdir -p "$STUB_DIR/absent-project"
for order in "flag-first" "path-first"; do
  if [ "$order" = "flag-first" ]; then
    set -- --require "$STUB_DIR/absent-project"
  else
    set -- "$STUB_DIR/absent-project" --require
  fi
  # /usr/bin:/bin keeps dirname/pwd reachable while excluding codex, which
  # installs to /usr/local/bin, a Homebrew prefix, or an nvm bin dir.
  out=$(PATH=/usr/bin:/bin bash "$HEPHAESTUS_ROOT/scripts/verify-codex-load.sh" "$@" 2>&1)
  assert_exit_code "--require fails without codex ($order)" 1 "$?"
  assert_contains  "errors, not skips, without the CLI ($order)" "$out" "ERR: codex not on PATH"
done

# Unknown flags must not be silently reinterpreted as a project path.
out=$(PATH="$STUB_DIR:/usr/bin:/bin" bash "$HEPHAESTUS_ROOT/scripts/verify-codex-load.sh" --requrie 2>&1)
assert_exit_code "rejects an unknown flag" 1 "$?"
assert_contains  "names the unknown flag" "$out" "unknown flag"

# A CLI that dropped the positional prompt breaks /worktrees Step 6 — catch it.
make_stub "codex [OPTIONS] --prompt <PROMPT>"
out=$(PATH="$STUB_DIR:/usr/bin:/bin" bash "$HEPHAESTUS_ROOT/scripts/verify-codex-load.sh" 2>&1)
assert_exit_code "fails when [PROMPT] is gone"  1 "$?"
assert_contains  "names the spawn regression" "$out" "no longer documents a positional [PROMPT]"

# A `--project` install scaffolds only .agents/skills/orient and no
# .codex/agents; the shared set stays in $CODEX_HOME. Must not false-fail.
make_stub "codex [OPTIONS] [PROMPT]"
PROJ="$STUB_DIR/proj"
mkdir -p "$PROJ/.agents/skills/orient"
echo "scaffolded" > "$PROJ/.agents/skills/orient/SKILL.md"
mkdir -p "$STUB_DIR/home"
cp -R "$HEPHAESTUS_ROOT/.agents/skills" "$STUB_DIR/home/skills"
cp -R "$HEPHAESTUS_ROOT/.codex/agents" "$STUB_DIR/home/agents"
out=$(PATH="$STUB_DIR:/usr/bin:/bin" CODEX_HOME="$STUB_DIR/home" \
      bash "$HEPHAESTUS_ROOT/scripts/verify-codex-load.sh" "$PROJ" 2>&1)
proj_rc=$?
assert_exit_code "project-mode install passes" 0 "$proj_rc"
# Naming the resolved roots is the point: it must have fallen past the
# scaffold-only project to $CODEX_HOME, not silently accepted the project.
assert_contains "reports the CODEX_HOME skills root" "$out" "skills:      $STUB_DIR/home/skills"
assert_contains "reports the CODEX_HOME agents root" "$out" "agent roles: $STUB_DIR/home/agents"

# Neither root holding the set is a real failure, and both roots get named.
out=$(PATH="$STUB_DIR:/usr/bin:/bin" CODEX_HOME="$STUB_DIR/empty" \
      bash "$HEPHAESTUS_ROOT/scripts/verify-codex-load.sh" "$PROJ" 2>&1)
assert_exit_code "fails when no root holds the adapters" 1 "$?"
assert_contains  "names the skills roots" "$out" "no Codex skills root"
assert_contains  "names the agents roots" "$out" "no Codex agents root"

# ─────────────────────────────────────────────────────────────────────────────

begin_test "hand-written files in .codex/agents survive the stale sweep"

FIXTURE_OWN=$(mktemp -d "${TMPDIR:-/tmp}/heph-codex-XXXXXX")
copy_fixture "$FIXTURE_OWN"

# No generated-from marker, so the sweep must report it rather than delete it.
echo 'name = "my-own"' > "$FIXTURE_OWN/.codex/agents/my-own.toml"

if own_check=$(bash "$FIXTURE_OWN/scripts/sync-codex-adapters.sh" --check 2>&1); then
  fail "check should flag the unexpected file" "exited 0: $own_check"
else
  assert_contains "check names the file"     "$own_check" "my-own.toml"
  assert_contains "check says non-generated" "$own_check" "unexpected non-generated file"
fi

bash "$FIXTURE_OWN/scripts/sync-codex-adapters.sh" >/dev/null 2>&1
assert_exit_code   "sync exits non-zero" 1 "$?"
assert_file_exists "hand-written role survives sync" "$FIXTURE_OWN/.codex/agents/my-own.toml"
rm -rf "$FIXTURE_OWN"

print_summary
