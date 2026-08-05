#!/usr/bin/env bash
# verify-cursor-load.sh — Confirm a live cursor-agent still takes the /worktrees
# spawn form, and that the generated adapters sit where Cursor reads them.
#
# Two checks, and only the first one is live: cursor-agent exposes no
# command-listing subcommand, so the adapters can only be checked on disk.
#
#   1. `cursor-agent --help` still documents a bare positional prompt.
#      /worktrees Step 6 spawns `cursor-agent "<prompt>"`, which seeds a session
#      only while that form holds.
#   2. The generated commands, subagents, and project rule are present in a root
#      Cursor reads. Either root counts: $CURSOR_HOME/{commands,agents,rules}
#      for a user install, the project's .cursor/* when vendored. A `--project`
#      install scaffolds only .cursor/commands/orient.md and no .cursor/agents
#      at all — the shared set stays in $CURSOR_HOME — so each root is chosen by
#      whether it actually holds the generated files, never by the directory
#      existing.
#
# What this cannot check: whether a leading-slash positional prompt is
# intercepted as a command or reaches the model as literal text. That routing
# question needs an authenticated model round-trip; it was settled by
# measurement and the result is recorded in the spawn rules of
# scripts/sync-cursor-adapters.sh.
#
# Requires `cursor-agent` on PATH. Exit 0 when the CLI is absent so the script
# can stay in CI optionally; pass --require to fail instead.
#
# Usage (from hephaestus root or an installed project):
#   bash scripts/verify-cursor-load.sh
#   bash scripts/verify-cursor-load.sh --require /path/to/project

set -uo pipefail

REQUIRE=0
PROJECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --require) REQUIRE=1 ;;
    -*) echo "Error: unknown flag '$1'" >&2; exit 1 ;;
    *) PROJECT=$1 ;;
  esac
  shift
done

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -n "$PROJECT" ]; then
  ROOT="$(cd "$PROJECT" && pwd)" || exit 1
else
  ROOT="$SRC"
fi

if ! command -v cursor-agent >/dev/null 2>&1; then
  if [ "$REQUIRE" -eq 1 ]; then
    echo "ERR: cursor-agent not on PATH" >&2
    exit 1
  fi
  echo "skip: cursor-agent not on PATH"
  exit 0
fi

fail=0

# resolve_root <probe-relative-path> <candidate>... → first candidate holding it
resolve_root() {
  local probe=$1 root
  shift
  for root in "$@"; do
    if [ -f "$root/$probe" ]; then
      printf '%s' "$root"
      return 0
    fi
  done
  return 1
}

# ── Spawn contract ───────────────────────────────────────────────────────────
if ! help=$(cursor-agent --help 2>&1); then
  echo "ERR: cursor-agent --help failed" >&2
  exit 1
fi
# The program name in the usage line follows how the CLI was invoked, so match
# only the positional itself. `[prompt` covers both `[prompt]` and `[prompt...]`
# and still fails if the CLI moves to a `--prompt <PROMPT>` flag.
case "$help" in
  *"[prompt"*) ;;
  *)
    echo "ERR: cursor-agent --help no longer documents a positional prompt" >&2
    echo "     /worktrees Step 6 seeds spawned sessions with one — update the" >&2
    echo "     spawn rules in scripts/sync-cursor-adapters.sh and regenerate" >&2
    fail=1
    ;;
esac

CURSOR_HOME_DIR="${CURSOR_HOME:-$HOME/.cursor}"

# ── Commands ─────────────────────────────────────────────────────────────────
if COMMANDS_DIR=$(resolve_root "start-issue.md" \
      "$ROOT/.cursor/commands" "$CURSOR_HOME_DIR/commands"); then
  for cmd in autopilot start-issue ship finish critique; do
    if [ ! -f "$COMMANDS_DIR/$cmd.md" ]; then
      echo "ERR: missing Cursor command $COMMANDS_DIR/$cmd.md" >&2
      fail=1
    elif ! grep -q "generated from .ai/workflows/$cmd.md" "$COMMANDS_DIR/$cmd.md"; then
      echo "ERR: Cursor command $cmd is not generated from .ai/workflows/$cmd.md" >&2
      fail=1
    fi
  done
else
  echo "ERR: no Cursor commands root holds the generated commands — looked in" >&2
  echo "     $ROOT/.cursor/commands and $CURSOR_HOME_DIR/commands" >&2
  fail=1
fi

# ── Subagents ────────────────────────────────────────────────────────────────
if AGENTS_DIR=$(resolve_root "coder.md" \
      "$ROOT/.cursor/agents" "$CURSOR_HOME_DIR/agents"); then
  for agent in coder explorer reviewer tester researcher; do
    if [ ! -f "$AGENTS_DIR/$agent.md" ]; then
      echo "ERR: missing Cursor subagent $AGENTS_DIR/$agent.md" >&2
      fail=1
    elif ! grep -q "generated from .claude/agents/$agent.md" "$AGENTS_DIR/$agent.md"; then
      echo "ERR: Cursor subagent $agent is not generated from .claude/agents/$agent.md" >&2
      fail=1
    fi
  done
else
  echo "ERR: no Cursor agents root holds the generated subagents — looked in" >&2
  echo "     $ROOT/.cursor/agents and $CURSOR_HOME_DIR/agents" >&2
  fail=1
fi

# ── Project rule ─────────────────────────────────────────────────────────────
# A project's own .mdc rules live alongside ours, so probe for our file by name.
if RULES_DIR=$(resolve_root "hephaestus.mdc" \
      "$ROOT/.cursor/rules" "$CURSOR_HOME_DIR/rules"); then
  if ! grep -q "generated from .ai/workflows/ and .claude/agents/" "$RULES_DIR/hephaestus.mdc"; then
    echo "ERR: Cursor rule hephaestus.mdc is not generated from .ai/workflows/ and .claude/agents/" >&2
    fail=1
  elif ! grep -q "alwaysApply: true" "$RULES_DIR/hephaestus.mdc"; then
    echo "ERR: Cursor rule hephaestus.mdc no longer always applies" >&2
    fail=1
  fi
else
  echo "ERR: no Cursor rules root holds hephaestus.mdc — looked in" >&2
  echo "     $ROOT/.cursor/rules and $CURSOR_HOME_DIR/rules" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

# Name the roots: the fallback is silent, and which one answered decides
# whether a drifted copy in the other root would be what Cursor actually loads.
echo "✓ Cursor takes the positional-prompt spawn form"
echo "  commands:  $COMMANDS_DIR"
echo "  subagents: $AGENTS_DIR"
echo "  rule:      $RULES_DIR/hephaestus.mdc"
