#!/usr/bin/env bash
# test_finish_docs_rule.sh — Verify /finish docs update skip/run rule.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

required_docs_for_diff() {
  local files="$1"
  local required="CHANGELOG.md"

  if echo "$files" | grep -Eq '^(install|update|uninstall)\.sh$|^\.claude/commands/[^/]+\.md$'; then
    required="$required README.md"
  fi

  if echo "$files" | grep -Eq '^\.claude/(agents|commands)/[^/]+\.md$'; then
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
    if ! echo "$files" | grep -qxF "$doc"; then
      missing="${missing:+$missing }$doc"
    fi
  done

  if [ -n "$missing" ]; then
    echo "run:$missing"
  else
    echo "skip"
  fi
}

begin_test "/finish docs rule requires CHANGELOG for every PR"
assert_eq "code-only PR still runs update-docs without CHANGELOG" \
  "run:CHANGELOG.md" \
  "$(decision_for_diff "loop.sh")"

begin_test "/finish docs rule detects user-facing command docs"
command_diff=$'.claude/commands/finish.md\nCHANGELOG.md\nREADME.md\nCLAUDE.md'
assert_eq "command change with all docs skips update-docs" \
  "skip" \
  "$(decision_for_diff "$command_diff")"

command_missing=$'.claude/commands/finish.md\nCHANGELOG.md'
assert_eq "command change missing README and CLAUDE runs update-docs" \
  "run:CLAUDE.md README.md" \
  "$(decision_for_diff "$command_missing")"

begin_test "/finish docs rule detects installer docs"
installer_diff=$'install.sh\nCHANGELOG.md'
assert_eq "installer change missing README runs update-docs" \
  "run:README.md" \
  "$(decision_for_diff "$installer_diff")"

begin_test "/finish docs rule detects agent pattern docs"
agent_diff=$'.claude/agents/reviewer.md\nCHANGELOG.md'
assert_eq "agent change missing CLAUDE runs update-docs" \
  "run:CLAUDE.md" \
  "$(decision_for_diff "$agent_diff")"

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
