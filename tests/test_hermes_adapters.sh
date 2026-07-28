#!/usr/bin/env bash
# test_hermes_adapters.sh — Verify Hermes adapters stay in sync with canonical sources.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

SKILLS="$HEPHAESTUS_ROOT/.hermes/skills/hephaestus"
AGENTS="$HEPHAESTUS_ROOT/.hermes/agents"

begin_test "Hermes adapters match workflows and Claude agents"

if output=$(bash "$HEPHAESTUS_ROOT/scripts/sync-hermes-adapters.sh" --check 2>&1); then
  pass "sync-hermes-adapters.sh --check exits 0"
else
  fail "sync-hermes-adapters.sh --check exits non-zero" "$output"
fi

begin_test "Hermes adapter check detects skill drift"

FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/heph-hermes-XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

copy_fixture() {
  local dest=$1
  cp -R "$HEPHAESTUS_ROOT/.ai" "$dest/.ai"
  cp -R "$HEPHAESTUS_ROOT/.claude" "$dest/.claude"
  cp -R "$HEPHAESTUS_ROOT/.hermes" "$dest/.hermes"
  mkdir -p "$dest/scripts"
  cp "$HEPHAESTUS_ROOT/scripts/sync-hermes-adapters.sh" "$dest/scripts/sync-hermes-adapters.sh"
  cp "$HEPHAESTUS_ROOT/scripts/models.sh" "$dest/scripts/models.sh"
}

copy_fixture "$FIXTURE"

sed -i.bak 's/Run the full autonomous pipeline/Run the drifted autonomous pipeline/' \
  "$FIXTURE/.hermes/skills/hephaestus/autopilot/SKILL.md"
rm -f "$FIXTURE/.hermes/skills/hephaestus/autopilot/SKILL.md.bak"

if drift_output=$(bash "$FIXTURE/scripts/sync-hermes-adapters.sh" --check 2>&1); then
  fail "Hermes adapter check should detect skill drift" "exited 0, output: $drift_output"
else
  if echo "$drift_output" | grep -q 'Hermes adapter drift for /autopilot'; then
    pass "Hermes adapter check reports /autopilot drift"
  else
    fail "Hermes adapter check failed without naming /autopilot" "$drift_output"
  fi
fi

begin_test "Hermes adapter check detects stale adapters after source deletion"

FIXTURE2=$(mktemp -d "${TMPDIR:-/tmp}/heph-hermes-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2"' EXIT

copy_fixture "$FIXTURE2"

rm "$FIXTURE2/.ai/workflows/research.md"
rm "$FIXTURE2/.claude/agents/tester.md"

if stale_output=$(bash "$FIXTURE2/scripts/sync-hermes-adapters.sh" --check 2>&1); then
  fail "Hermes check should detect orphaned adapters" "exited 0, output: $stale_output"
else
  assert_contains "check names stale skill dir" "$stale_output" ".hermes/skills/hephaestus/research"
  assert_contains "check names stale agent adapter" "$stale_output" ".hermes/agents/tester.md"
fi

sync_output=$(bash "$FIXTURE2/scripts/sync-hermes-adapters.sh" 2>&1)
assert_contains "sync reports stale skill removal" "$sync_output" "removed stale Hermes skill"
assert_file_not_exists "sync removes orphaned skill" "$FIXTURE2/.hermes/skills/hephaestus/research/SKILL.md"
assert_file_not_exists "sync removes orphaned agent adapter" "$FIXTURE2/.hermes/agents/tester.md"

sed -i.bak '/^name:/d' "$FIXTURE2/.claude/agents/coder.md"
bash "$FIXTURE2/scripts/sync-hermes-adapters.sh" >/dev/null 2>&1
assert_exit_code "sync fails on unparseable source" 1 "$?"
assert_file_exists "sync keeps adapter of unparseable source" "$FIXTURE2/.hermes/agents/coder.md"

begin_test "Hermes sync never deletes non-generated skill dirs"

FIXTURE3=$(mktemp -d "${TMPDIR:-/tmp}/heph-hermes-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2" "$FIXTURE3"' EXIT

copy_fixture "$FIXTURE3"

mkdir -p "$FIXTURE3/.hermes/skills/hephaestus/hand-rolled"
printf -- '---\nname: hand-rolled\ndescription: user-owned skill\n---\nDo things.\n' \
  > "$FIXTURE3/.hermes/skills/hephaestus/hand-rolled/SKILL.md"

if foreign_output=$(bash "$FIXTURE3/scripts/sync-hermes-adapters.sh" 2>&1); then
  fail "sync should exit non-zero on non-generated skill dir" "exited 0, output: $foreign_output"
else
  assert_contains "sync flags non-generated dir" "$foreign_output" "non-generated dir"
fi
assert_file_exists "non-generated skill dir preserved" "$FIXTURE3/.hermes/skills/hephaestus/hand-rolled/SKILL.md"

begin_test "Hermes skills carry Hermes frontmatter"

ship="$SKILLS/ship/SKILL.md"
start="$SKILLS/start-issue/SKILL.md"
orient="$SKILLS/orient/SKILL.md"

assert_contains "ship skill has name" "$(cat "$ship")" "name: ship"
assert_contains "ship skill declares category" "$(cat "$ship")" "category: hephaestus"
assert_contains "ship skill declares platforms" "$(cat "$ship")" "platforms: [linux, macos, windows]"
assert_contains "ship skill requires terminal toolset" "$(cat "$ship")" "requires_toolsets: [terminal]"
assert_contains "ship skill declares requires" "$(cat "$ship")" "<!-- requires: tester -->"
assert_contains "ship skill names its source" "$(cat "$ship")" "generated from .ai/workflows/ship.md"
assert_not_contains "ship description drops \$ARGUMENTS placeholder" "$(grep '^description' "$ship")" "ARGUMENTS"
assert_contains "ship skill notes missing substitution" "$(cat "$ship")" 'Hermes does not substitute `$ARGUMENTS`'
assert_not_contains "argument note only when body uses \$ARGUMENTS" "$(cat "$orient")" 'Hermes does not substitute'
assert_not_contains "generated skills carry no version field" "$(cat "$ship")" "version:"

# Hermes recommends descriptions ≤60 characters; the generator trims to fit.
for skill_md in "$SKILLS"/*/SKILL.md; do
  desc=$(grep -m1 '^description:' "$skill_md" | sed 's/^description: *"//; s/"$//')
  if [ "${#desc}" -le 61 ]; then
    pass "$(basename "$(dirname "$skill_md")") description fits Hermes cap (${#desc})"
  else
    fail "$(basename "$(dirname "$skill_md")") description too long" "${#desc} chars: $desc"
  fi
done

begin_test "Hermes skills map chains to related_skills"

assert_contains "start-issue relates to test-issue" "$(cat "$start")" "related_skills: [test-issue]"
assert_contains "autopilot relates to its whole chain" "$(cat "$SKILLS/autopilot/SKILL.md")" "related_skills: [start-issue, ship, finish]"
assert_contains "orient declares no related skills" "$(cat "$orient")" "related_skills: []"

begin_test "Hermes skills use Hermes dialect and delegation notes"

refactor="$SKILLS/refactor/SKILL.md"
research="$SKILLS/research/SKILL.md"

assert_contains "start skill has Hermes callout" "$(cat "$start")" "**Hermes:**"
assert_contains "start skill names delegate_task" "$(cat "$start")" 'delegate_task'
assert_contains "start skill warns context is not inherited" "$(cat "$start")" "inherits **none** of your conversation"
assert_contains "start skill points at delegate briefs" "$(cat "$start")" '.hermes/agents/<role>.md'
assert_contains "start skill chain note names nested skill" "$(cat "$start")" "/test-issue"
assert_contains "start skill maps todo tool" "$(cat "$start")" "the todo tool"
assert_not_contains "start skill drops TodoWrite" "$(cat "$start")" "TodoWrite"
assert_contains "start skill maps coder delegates" "$(cat "$start")" "coder delegates"
assert_not_contains "start skill drops worktree subagent wording" "$(cat "$start")" "coder subagents (in worktrees)"
assert_contains "refactor skill warns no per-child worktree" "$(cat "$refactor")" "no per-child worktree"
# Verified against Hermes v0.15.1: delegate_task builds the child from a fresh
# conversation and passes only a workspace *hint* in its system prompt — cwd is
# not inherited, so the orchestrator must hand over absolute paths.
assert_contains "refactor skill says cwd is not inherited" "$(cat "$refactor")" "not your working directory"
assert_contains "refactor skill demands absolute paths" "$(cat "$refactor")" "absolute paths"
assert_contains "research skill maps researcher delegates" "$(cat "$research")" "researcher delegates"
assert_not_contains "research skill drops subagent wording" "$(cat "$research")" "researcher subagents"
assert_not_contains "orient skill has no delegation note" "$(cat "$orient")" "Delegate to \`delegate_task\`"

begin_test "Hermes delegate briefs map toolsets and constraints"

coder="$AGENTS/coder.md"
reviewer="$AGENTS/reviewer.md"
researcher="$AGENTS/researcher.md"

assert_contains "coder gets terminal and file toolsets" "$(cat "$coder")" '["terminal", "file"]'
assert_contains "coder brief names its source" "$(cat "$coder")" "generated from .claude/agents/coder.md"
assert_contains "coder delegates as leaf" "$(cat "$coder")" 'role: "leaf"'
assert_contains "coder warns about missing worktree isolation" "$(cat "$coder")" "**No worktree isolation**"
assert_not_contains "coder is not marked read-only" "$(cat "$coder")" "**Read-only**"
assert_contains "coder carries the shared prompt" "$(cat "$coder")" "Only modify files directly related to your assigned task"
assert_contains "reviewer is marked read-only" "$(cat "$reviewer")" "**Read-only**"
assert_not_contains "reviewer has no isolation warning" "$(cat "$reviewer")" "No worktree isolation"
assert_contains "researcher gets web toolset" "$(cat "$researcher")" '["file", "web"]'
assert_contains "researcher is marked read-only" "$(cat "$researcher")" "**Read-only**"
# Verified against Hermes v0.15.1 (tools/delegate_tool.py): requested child
# toolsets are intersected with the parent's and anything missing is dropped
# silently — a researcher delegate in a session without `web` loses web_search
# with no error, so the brief must say so rather than claim plain "narrowing".
assert_contains "brief warns toolsets are intersected" "$(cat "$researcher")" "intersected with yours, silently"
assert_contains "brief warns the drop is silent" "$(cat "$coder")" "dropped with no error"
assert_contains "brief says cwd is not inherited" "$(cat "$coder")" "**No inherited cwd**"

begin_test "Hermes delegate briefs render model tiers from models.conf"

assert_contains "coder renders sonnet tier" "$(cat "$coder")" 'tier**: `sonnet` → `anthropic/claude-sonnet-5`'
assert_contains "reviewer renders opus tier" "$(cat "$reviewer")" 'tier**: `opus` → `anthropic/claude-opus-5`'
assert_contains "tester renders haiku tier" "$(cat "$AGENTS/tester.md")" 'tier**: `haiku` → `anthropic/claude-haiku-4-5-20251001`'
assert_contains "tier note flags the global delegation.model" "$(cat "$coder")" "one global \`delegation.model\`"

begin_test "Hermes adapters exist for every workflow and agent role"

for wf in "$HEPHAESTUS_ROOT"/.ai/workflows/*.md; do
  name=$(basename "$wf" .md)
  assert_file_exists "skill for /$name" "$SKILLS/$name/SKILL.md"
done
for ag in "$HEPHAESTUS_ROOT"/.claude/agents/*.md; do
  name=$(basename "$ag" .md)
  assert_file_exists "delegate brief for @$name" "$AGENTS/$name.md"
done

begin_test "Hermes worktrees skill spawns hermes, not claude"

worktrees=$(cat "$SKILLS/worktrees/SKILL.md")
# Verified against Hermes v0.15.1: `hermes chat -q` calls cli.chat() directly
# (cli.py:15733) and never reaches process_command(), so a leading-slash prompt
# is NOT dispatched as a skill — it arrives at the model as literal text. The
# spawn therefore preloads the skill with `-s` (which errors loudly on an
# unknown skill) instead of relying on `/start-issue` resolving.
assert_contains "osascript spawn uses hermes" "$worktrees" 'do script "cd <worktree> && hermes chat -s hephaestus/start-issue -q \"Run the start-issue workflow for issue <N>.\""'
assert_contains "manual fallback uses hermes" "$worktrees" 'cd <worktree> && hermes chat -s hephaestus/start-issue -q "Run the start-issue workflow for issue <N>."'
assert_not_contains "spawn never passes a bare slash command to -q" "$worktrees" '-q \"/start-issue'
assert_not_contains "manual fallback never passes a bare slash command" "$worktrees" '-q "/start-issue'
assert_contains "spawn explains why -s is required" "$worktrees" "never dispatched in \`-q\` mode"
assert_contains "summary names Hermes sessions" "$worktrees" "spawn a seeded Hermes session"

# Repo-wide guard, frontmatter included — the `description:` is built from the
# localized first body line, so a reflow that pushes a Claude product name past
# the truncation trips this. Bare "claude" is not a needle: `.claude/` paths are
# legitimate, and models.conf maps tiers to anthropic/claude-* model ids.
leaks=$(grep -rnF -e "Claude Code" -e "&& claude " -e "--permission-mode" \
  "$SKILLS" "$AGENTS" 2>/dev/null || true)
assert_eq "no Claude-product leak in any Hermes adapter" "" "$leaks"

begin_test "verify-hermes-load.sh resolves the project, not the submodule"

# Regression guard: run as `bash .hephaestus/scripts/verify-hermes-load.sh` — the
# exact command install.sh prints — the script must check <project>/.hermes/skills,
# not the submodule's own copy. The submodule copy has no project-specific orient,
# so wiring it would silently shadow the scaffold.
FIXTURE4=$(mktemp -d "${TMPDIR:-/tmp}/heph-hermes-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2" "$FIXTURE3" "$FIXTURE4"' EXIT

PROJ="$FIXTURE4/proj"
mkdir -p "$PROJ/.hermes/skills/hephaestus" "$PROJ/.hermes/agents"
PROJ=$(cd "$PROJ" && pwd)   # canonicalize: $TMPDIR may carry a trailing slash
ln -s "$HEPHAESTUS_ROOT" "$PROJ/.hephaestus"
for a in coder explorer reviewer tester researcher; do
  cp "$AGENTS/$a.md" "$PROJ/.hermes/agents/$a.md"
done
# The verifier checks the identifier `/worktrees` spawns with
# (`hermes chat -s hephaestus/start-issue`), so the fixture carries the skill
# at that path exactly as an install would.
mkdir -p "$PROJ/.hermes/skills/hephaestus/start-issue"
cp "$SKILLS/start-issue/SKILL.md" "$PROJ/.hermes/skills/hephaestus/start-issue/SKILL.md"

# Stub `hermes` so the check runs without a real install. `config path` points at
# a config wired to the PROJECT skills dir — what install.sh tells the user to add.
mkdir -p "$FIXTURE4/bin"
printf 'skills:\n  external_dirs:\n    - %s/.hermes/skills\n' "$PROJ" > "$FIXTURE4/config.yaml"
cat > "$FIXTURE4/bin/hermes" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "config path") echo "$FIXTURE4/config.yaml" ;;
  "skills list") echo "autopilot start-issue ship finish critique" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$FIXTURE4/bin/hermes"

verify_out=$(cd "$PROJ" && PATH="$FIXTURE4/bin:$PATH" bash .hephaestus/scripts/verify-hermes-load.sh 2>&1)
verify_rc=$?
assert_exit_code "verifier passes on a correctly wired install" 0 "$verify_rc"
assert_contains "verifier names the project skills dir" "$verify_out" "$PROJ/.hermes/skills"
assert_not_contains "verifier never names the submodule skills dir" "$verify_out" ".hephaestus/.hermes/skills"

# Unwired project: must fail with the PROJECT path in the remediation.
printf 'skills:\n  external_dirs: []\n' > "$FIXTURE4/config.yaml"
unwired_out=$(cd "$PROJ" && PATH="$FIXTURE4/bin:$PATH" bash .hephaestus/scripts/verify-hermes-load.sh 2>&1)
assert_exit_code "verifier fails when unwired" 1 "$?"
assert_contains "remediation names the project skills dir" "$unwired_out" "$PROJ/.hermes/skills"
assert_not_contains "remediation never names the submodule dir" "$unwired_out" ".hephaestus/.hermes/skills"

# ─────────────────────────────────────────────────────────────────────────────

begin_test "hand-written files in .hermes/agents survive the stale sweep"

FIXTURE_OWN=$(mktemp -d "${TMPDIR:-/tmp}/heph-hermes-XXXXXX")
copy_fixture "$FIXTURE_OWN"

# The case from the issue: a personal note dropped in the delegate-brief dir.
echo 'my notes' > "$FIXTURE_OWN/.hermes/agents/my-notes.md"

if own_check=$(bash "$FIXTURE_OWN/scripts/sync-hermes-adapters.sh" --check 2>&1); then
  fail "check should flag the unexpected file" "exited 0: $own_check"
else
  assert_contains "check names the file"     "$own_check" "my-notes.md"
  assert_contains "check says non-generated" "$own_check" "unexpected non-generated file"
fi

bash "$FIXTURE_OWN/scripts/sync-hermes-adapters.sh" >/dev/null 2>&1
assert_exit_code   "sync exits non-zero" 1 "$?"
assert_file_exists "hand-written note survives sync" "$FIXTURE_OWN/.hermes/agents/my-notes.md"
rm -rf "$FIXTURE_OWN"

print_summary
