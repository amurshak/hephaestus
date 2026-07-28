#!/usr/bin/env bash
# protect-files.sh — PreToolUse hook (Edit|Write): block edits to sensitive paths.
#
# Blocks: .env* files, anything under .git/, and paths that resolve outside the
# project root (guards against ../ traversal). Exit 2 = block with message.
#
# Wire in .claude/settings.json:
#   "hooks": { "PreToolUse": [ { "matcher": "Edit|Write",
#     "hooks": [ { "type": "command", "command": ".claude/hooks/protect-files.sh" } ] } ] }

set -uo pipefail

INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Canonicalize (python3: portable realpath that tolerates not-yet-existing files)
REAL=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$FILE_PATH")
BASE=$(basename "$REAL")

case "$BASE" in
  .env|.env.*)
    echo "Blocked: $BASE is a protected secrets file. Edit it manually if intended." >&2
    exit 2 ;;
esac

case "$REAL" in
  "$PROJECT_ROOT"/.git/*)
    echo "Blocked: direct edits inside .git/ are not allowed." >&2
    exit 2 ;;
  "$PROJECT_ROOT"/*) ;;  # inside the project — fine
  *)
    echo "Blocked: $REAL resolves outside the project root ($PROJECT_ROOT)." >&2
    exit 2 ;;
esac

exit 0
