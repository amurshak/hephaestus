#!/usr/bin/env bash
# test_model_assignment.sh — Verify harness-agnostic model tier assignment.
#
# Agents declare a neutral tier; .ai/models.conf says what each tier means per
# harness. These tests cover tier validation, per-harness rendering, override
# layering, and the determinism guarantee that --check ignores overrides.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/heph-models-XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

copy_fixture() {
  local dest=$1
  mkdir -p "$dest/scripts"
  cp -R "$HEPHAESTUS_ROOT/.ai" "$dest/.ai"
  cp -R "$HEPHAESTUS_ROOT/.claude" "$dest/.claude"
  cp -R "$HEPHAESTUS_ROOT/.opencode" "$dest/.opencode"
  cp -R "$HEPHAESTUS_ROOT/.agents" "$dest/.agents"
  cp -R "$HEPHAESTUS_ROOT/.codex" "$dest/.codex"
  cp "$HEPHAESTUS_ROOT/scripts/models.sh" "$dest/scripts/models.sh"
  cp "$HEPHAESTUS_ROOT/scripts/sync-opencode-adapters.sh" "$dest/scripts/"
  cp "$HEPHAESTUS_ROOT/scripts/sync-codex-adapters.sh" "$dest/scripts/"
}

# ─────────────────────────────────────────────────────────────────────────────
begin_test "Every agent declares a valid model tier"

for agent in "$HEPHAESTUS_ROOT"/.claude/agents/*.md; do
  name=$(basename "$agent" .md)
  tier=$(awk -F': *' '/^---$/ { if (++f == 2) exit; next } f == 1 && $1 == "model" { print $2; exit }' "$agent")
  case "$tier" in
    opus|sonnet|haiku|inherit) pass "$name declares tier '$tier'" ;;
    "") fail "$name declares a model tier" "no model: line in frontmatter" ;;
    *)  fail "$name declares a valid tier" "got '$tier'" ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
begin_test "Tiers are assigned by role cost, not uniformly"

tier_of() {
  awk -F': *' '/^---$/ { if (++f == 2) exit; next } f == 1 && $1 == "model" { print $2; exit }' \
    "$HEPHAESTUS_ROOT/.claude/agents/$1.md"
}

assert_eq "reviewer runs on the strong tier" "opus" "$(tier_of reviewer)"
assert_eq "coder runs on the mid tier" "sonnet" "$(tier_of coder)"
assert_eq "researcher runs on the mid tier" "sonnet" "$(tier_of researcher)"
assert_eq "explorer runs on the cheap tier" "haiku" "$(tier_of explorer)"
assert_eq "tester runs on the cheap tier" "haiku" "$(tier_of tester)"

# ─────────────────────────────────────────────────────────────────────────────
begin_test "OpenCode adapters render the tier as a provider/model id"

assert_contains "reviewer gets the opus model" \
  "$(cat "$HEPHAESTUS_ROOT/.opencode/agents/reviewer.md")" "model: anthropic/claude-opus-5"
assert_contains "coder gets the sonnet model" \
  "$(cat "$HEPHAESTUS_ROOT/.opencode/agents/coder.md")" "model: anthropic/claude-sonnet-5"
assert_contains "explorer gets the haiku model" \
  "$(cat "$HEPHAESTUS_ROOT/.opencode/agents/explorer.md")" "model: anthropic/claude-haiku-4-5-20251001"

# ─────────────────────────────────────────────────────────────────────────────
begin_test "Codex adapters render the tier as reasoning effort"

assert_contains "reviewer gets high effort" \
  "$(cat "$HEPHAESTUS_ROOT/.codex/agents/reviewer.toml")" 'model_reasoning_effort = "high"'
assert_contains "coder gets medium effort" \
  "$(cat "$HEPHAESTUS_ROOT/.codex/agents/coder.toml")" 'model_reasoning_effort = "medium"'
assert_contains "tester gets low effort" \
  "$(cat "$HEPHAESTUS_ROOT/.codex/agents/tester.toml")" 'model_reasoning_effort = "low"'
assert_not_contains "shipped defaults pin no Codex model" \
  "$(cat "$HEPHAESTUS_ROOT/.codex/agents/reviewer.toml")" "model = "

# ─────────────────────────────────────────────────────────────────────────────
begin_test "An invalid tier fails generation instead of emitting a bad adapter"

copy_fixture "$FIXTURE"
sed -i.bak 's/^model: opus$/model: gigantic/' "$FIXTURE/.claude/agents/reviewer.md"
rm -f "$FIXTURE/.claude/agents/reviewer.md.bak"

bad_output=$(bash "$FIXTURE/scripts/sync-opencode-adapters.sh" 2>&1)
assert_exit_code "sync rejects an unknown tier" 1 "$?"
assert_contains "error names the bad tier" "$bad_output" "invalid model tier 'gigantic'"
assert_not_contains "adapter not rewritten with bad tier" \
  "$(cat "$FIXTURE/.opencode/agents/reviewer.md")" "model: gigantic"

# ─────────────────────────────────────────────────────────────────────────────
begin_test "inherit emits nothing, leaving the harness default in place"

FIXTURE2=$(mktemp -d "${TMPDIR:-/tmp}/heph-models-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2"' EXIT
copy_fixture "$FIXTURE2"

sed -i.bak 's/^model: opus$/model: inherit/' "$FIXTURE2/.claude/agents/reviewer.md"
rm -f "$FIXTURE2/.claude/agents/reviewer.md.bak"
bash "$FIXTURE2/scripts/sync-opencode-adapters.sh" >/dev/null 2>&1
bash "$FIXTURE2/scripts/sync-codex-adapters.sh" >/dev/null 2>&1

assert_not_contains "OpenCode adapter has no model line" \
  "$(cat "$FIXTURE2/.opencode/agents/reviewer.md")" "model:"
assert_not_contains "Codex adapter has no reasoning effort" \
  "$(cat "$FIXTURE2/.codex/agents/reviewer.toml")" "model_reasoning_effort"

# ─────────────────────────────────────────────────────────────────────────────
begin_test "Override layers merge per key over the shipped defaults"

FIXTURE3=$(mktemp -d "${TMPDIR:-/tmp}/heph-models-XXXXXX")
trap 'rm -rf "$FIXTURE" "$FIXTURE2" "$FIXTURE3"' EXIT
copy_fixture "$FIXTURE3"

OVERRIDE="$FIXTURE3/override.conf"
cat > "$OVERRIDE" <<'EOF'
# only the opus tier is repointed; every other tier keeps its shipped value
opencode.opus.model = openai/gpt-5.6
codex.opus.model    = gpt-5.6
EOF

override_output=$(HEPHAESTUS_MODELS="$OVERRIDE" bash "$FIXTURE3/scripts/sync-opencode-adapters.sh" 2>&1)
HEPHAESTUS_MODELS="$OVERRIDE" bash "$FIXTURE3/scripts/sync-codex-adapters.sh" >/dev/null 2>&1

assert_contains "sync warns that an override is active" "$override_output" "model map overridden by"
assert_contains "overridden tier uses the override value" \
  "$(cat "$FIXTURE3/.opencode/agents/reviewer.md")" "model: openai/gpt-5.6"
assert_contains "untouched tier keeps the shipped value" \
  "$(cat "$FIXTURE3/.opencode/agents/coder.md")" "model: anthropic/claude-sonnet-5"
assert_contains "Codex override adds a pinned model" \
  "$(cat "$FIXTURE3/.codex/agents/reviewer.toml")" 'model = "gpt-5.6"'
assert_contains "Codex override keeps the shipped effort" \
  "$(cat "$FIXTURE3/.codex/agents/reviewer.toml")" 'model_reasoning_effort = "high"'

# ─────────────────────────────────────────────────────────────────────────────
begin_test "--check ignores overrides so committed adapters stay reproducible"

# The fixture now holds override-generated adapters. --check must compare them
# against the shipped defaults and flag the difference, even with the override
# still exported — otherwise the drift gate would pass or fail per machine.
check_output=$(HEPHAESTUS_MODELS="$OVERRIDE" bash "$FIXTURE3/scripts/sync-opencode-adapters.sh" --check 2>&1)
assert_exit_code "--check flags override-generated adapters as drift" 1 "$?"
assert_contains "--check names the drifted agent" "$check_output" "OpenCode adapter drift for @reviewer"
assert_not_contains "--check does not announce the override" "$check_output" "model map overridden by"

bash "$FIXTURE3/scripts/sync-opencode-adapters.sh" >/dev/null 2>&1
bash "$FIXTURE3/scripts/sync-codex-adapters.sh" >/dev/null 2>&1
if HEPHAESTUS_MODELS="$OVERRIDE" bash "$FIXTURE3/scripts/sync-opencode-adapters.sh" --check >/dev/null 2>&1; then
  pass "--check passes on shipped-default adapters regardless of override"
else
  fail "--check passes on shipped-default adapters regardless of override" "exited non-zero"
fi

# ─────────────────────────────────────────────────────────────────────────────
begin_test "A missing HEPHAESTUS_MODELS path fails loudly"

missing_output=$(HEPHAESTUS_MODELS="$FIXTURE3/nope.conf" bash "$FIXTURE3/scripts/sync-opencode-adapters.sh" 2>&1)
assert_exit_code "sync fails on a missing override file" 1 "$?"
assert_contains "error names the missing path" "$missing_output" "points at a missing file"

print_summary
