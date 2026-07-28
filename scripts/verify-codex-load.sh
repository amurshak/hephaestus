#!/usr/bin/env bash
# verify-codex-load.sh — Confirm a live Codex CLI loads hephaestus adapters and
# still accepts the /worktrees Step 6 spawn form.
#
# Codex exposes no skill-listing command, so this settles the two things only a
# live CLI can: that `codex [OPTIONS] [PROMPT]` still takes a bare positional
# prompt (Step 6 spawns `codex "/start-issue <N>"`, which seeds a session only
# while that form holds), and that the generated skills sit in a root Codex
# reads — $CODEX_HOME/skills for a user install, <project>/.agents/skills for a
# project install.
#
# Requires `codex` on PATH. Exit 0 when the CLI is absent so the script can stay
# in CI optionally; pass --require to fail instead.
#
# Usage (from hephaestus root or an installed project):
#   bash scripts/verify-codex-load.sh
#   bash scripts/verify-codex-load.sh --require /path/to/project

set -uo pipefail

REQUIRE=0
if [ "${1:-}" = "--require" ]; then
  REQUIRE=1
  shift
fi

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -n "${1:-}" ]; then
  ROOT="$(cd "$1" && pwd)" || exit 1
else
  ROOT="$SRC"
fi
cd "$ROOT" || exit 1

if ! command -v codex >/dev/null 2>&1; then
  if [ "$REQUIRE" -eq 1 ]; then
    echo "ERR: codex not on PATH" >&2
    exit 1
  fi
  echo "skip: codex not on PATH"
  exit 0
fi

fail=0

# ── Spawn contract ───────────────────────────────────────────────────────────
if ! help=$(codex --help 2>&1); then
  echo "ERR: codex --help failed" >&2
  exit 1
fi
case "$help" in
  *"codex [OPTIONS] [PROMPT]"*) ;;
  *)
    echo "ERR: codex --help no longer documents a positional [PROMPT]" >&2
    echo "     /worktrees Step 6 seeds spawned sessions with one — update the" >&2
    echo "     spawn rules in scripts/sync-codex-adapters.sh and regenerate" >&2
    fail=1
    ;;
esac

# ── Skills ───────────────────────────────────────────────────────────────────
CODEX_SKILLS="${CODEX_HOME:-$HOME/.codex}/skills"
if [ -d "$ROOT/.agents/skills" ]; then
  SKILLS_DIR="$ROOT/.agents/skills"
elif [ -d "$CODEX_SKILLS" ]; then
  SKILLS_DIR="$CODEX_SKILLS"
else
  echo "ERR: no Codex skills root — expected $ROOT/.agents/skills or $CODEX_SKILLS" >&2
  exit 1
fi

for skill in autopilot start-issue ship finish critique; do
  if [ ! -f "$SKILLS_DIR/$skill/SKILL.md" ]; then
    echo "ERR: missing Codex skill $SKILLS_DIR/$skill/SKILL.md" >&2
    fail=1
  elif ! grep -q "generated from .ai/workflows/$skill.md" "$SKILLS_DIR/$skill/SKILL.md"; then
    echo "ERR: Codex skill $skill is not generated from .ai/workflows/$skill.md" >&2
    fail=1
  fi
done

# ── Agent roles ──────────────────────────────────────────────────────────────
for agent in coder explorer reviewer tester researcher; do
  if [ ! -f "$ROOT/.codex/agents/$agent.toml" ]; then
    echo "ERR: missing Codex agent role $ROOT/.codex/agents/$agent.toml" >&2
    fail=1
  elif ! grep -q "generated from .claude/agents/$agent.md" "$ROOT/.codex/agents/$agent.toml"; then
    echo "ERR: Codex agent role $agent is not generated from .claude/agents/$agent.md" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "✓ Codex takes the positional-prompt spawn form and loads hephaestus skills and agent roles"
