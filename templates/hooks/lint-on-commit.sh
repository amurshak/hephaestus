#!/usr/bin/env bash
# lint-on-commit.sh — PreToolUse hook (Bash): run lint before any git commit.
#
# A deterministic backstop for the prose quality gates: if the agent tries to
# commit while lint fails, the commit is blocked (exit 2) with the lint output.
#
# CUSTOMIZE: set LINT_CMD to your project's lint command (the same one in your
# CLAUDE.md "Development Commands"). Leave empty to disable.
LINT_CMD=""            # e.g. "npx eslint ." or "ruff check ." or "golangci-lint run"

# Wire in .claude/settings.json:
#   "hooks": { "PreToolUse": [ { "matcher": "Bash",
#     "hooks": [ { "type": "command", "command": ".claude/hooks/lint-on-commit.sh" } ] } ] }

set -uo pipefail

[ -z "$LINT_CMD" ] && exit 0

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)

# Only gate actual commit invocations
case "$CMD" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

if ! OUTPUT=$(eval "$LINT_CMD" 2>&1); then
  echo "Blocked commit: lint failed. Fix before committing:" >&2
  echo "$OUTPUT" | tail -30 >&2
  exit 2
fi

exit 0
