#!/usr/bin/env bash
# test_finish_docs_rule.sh — Verify /finish docs update skip/run rule.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Models this repo's "## Docs Requirements" override in CLAUDE.md, which wins
# whole over finish.md's defaults. Generated adapters (.claude/commands/ and the
# other harness dirs) trigger nothing: they regenerate on every workflow change,
# so triggering README from them made README required on essentially every PR —
# a contention hotspot rather than a documentation rule.
required_docs_for_diff() {
  local files="$1"
  local required="changelog.d/"

  if echo "$files" | grep -Eq '^(install|update|uninstall)\.sh$|^\.ai/workflows/[^/]+\.md$|^\.ai/conventions\.md$'; then
    required="$required README.md"
  fi

  if echo "$files" | grep -Eq '^\.claude/agents/[^/]+\.md$|^scripts/'; then
    required="$required CLAUDE.md"
  fi

  printf '%s\n' $required | sort -u | tr '\n' ' ' | sed 's/ $//'
}

decision_for_diff() {
  local files="$1"
  local required
  required=$(required_docs_for_diff "$files")

  local missing=""
  for doc in $required; do
    # A trailing slash means "any file under this directory" — the changelog
    # fragment is one file per PR, so its name is never known in advance.
    if [ "${doc%/}" != "$doc" ]; then
      echo "$files" | grep -qF -- "$doc" || missing="${missing:+$missing }$doc"
    elif ! echo "$files" | grep -qxF "$doc"; then
      missing="${missing:+$missing }$doc"
    fi
  done

  if [ -n "$missing" ]; then
    echo "run:$missing"
  else
    echo "skip"
  fi
}

begin_test "/finish docs rule requires a changelog fragment for every PR"
assert_eq "code-only PR still runs update-docs without a fragment" \
  "run:changelog.d/" \
  "$(decision_for_diff "loop.sh")"

begin_test "/finish docs rule detects consumer-surface changes"
workflow_diff=$'.ai/workflows/finish.md\nchangelog.d/42.changed.md\nREADME.md'
assert_eq "workflow change with README and fragment skips update-docs" \
  "skip" \
  "$(decision_for_diff "$workflow_diff")"

workflow_missing=$'.ai/workflows/finish.md\nchangelog.d/42.changed.md'
assert_eq "workflow change missing README runs update-docs" \
  "run:README.md" \
  "$(decision_for_diff "$workflow_missing")"

spec_diff=$'.ai/conventions.md\nchangelog.d/42.changed.md'
assert_eq "conventions change missing README runs update-docs" \
  "run:README.md" \
  "$(decision_for_diff "$spec_diff")"

begin_test "/finish docs rule detects installer docs"
installer_diff=$'install.sh\nchangelog.d/42.changed.md'
assert_eq "installer change missing README runs update-docs" \
  "run:README.md" \
  "$(decision_for_diff "$installer_diff")"

begin_test "/finish docs rule detects contributor-surface changes"
agent_diff=$'.claude/agents/reviewer.md\nchangelog.d/42.changed.md'
assert_eq "agent change missing CLAUDE runs update-docs" \
  "run:CLAUDE.md" \
  "$(decision_for_diff "$agent_diff")"

script_diff=$'scripts/sync-cursor-adapters.sh\nchangelog.d/42.changed.md'
assert_eq "generator change missing CLAUDE runs update-docs" \
  "run:CLAUDE.md" \
  "$(decision_for_diff "$script_diff")"

both_missing=$'install.sh\n.claude/agents/coder.md'
assert_eq "change missing every required doc lists them all" \
  "run:changelog.d/ CLAUDE.md README.md" \
  "$(decision_for_diff "$both_missing")"

begin_test "/finish docs rule ignores generated adapters"
# The regression the split fixed: adapters regenerate on every workflow change,
# so requiring README from them pinned doc-touching work at one issue per wave.
adapter_diff=$'.claude/commands/finish.md\n.cursor/commands/finish.md\nchangelog.d/42.changed.md'
assert_eq "adapter-only change requires no README or CLAUDE" \
  "skip" \
  "$(decision_for_diff "$adapter_diff")"

begin_test "finish.md documents deterministic logging"
finish_md=$(cat "$HEPHAESTUS_ROOT/.claude/commands/finish.md")
assert_contains "mentions git diff source of truth" "$finish_md" \
  'git diff "$BASE_SHA..$HEAD_SHA" --name-only'
assert_contains "documents auto-detected skip log" "$finish_md" \
  "skipped /update-docs: docs updated in PR #N (auto-detected)"
assert_contains "documents auto-detected run log" "$finish_md" \
  "ran /update-docs: missing <files> in PR #N (auto-detected)"
assert_contains "forbids model judgment" "$finish_md" \
  "do not use model judgment"

print_summary
