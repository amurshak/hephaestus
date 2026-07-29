#!/usr/bin/env bash
# verify-codex-load.sh — Confirm a live Codex CLI still takes the /worktrees
# spawn form, and that the generated adapters sit where Codex reads them.
#
# Two checks, and only the first one is live: Codex exposes no skill-listing
# command, so the adapters can only be checked on disk.
#
#   1. `codex --help` still documents a bare positional prompt. /worktrees
#      Step 6 spawns `codex "/start-issue <N>"`, which seeds a session only
#      while that form holds.
#   2. The generated skills and agent roles are present in a root Codex reads.
#      Either root counts: $CODEX_HOME/{skills,agents} for a user install, the
#      project's .agents/skills and .codex/agents when vendored. A `--project`
#      install scaffolds only .agents/skills/orient and no .codex/agents at all
#      — the shared set stays in $CODEX_HOME — so each root is chosen by whether
#      it actually holds the generated files, never by the directory existing.
#
# Requires `codex` on PATH. Exit 0 when the CLI is absent so the script can stay
# in CI optionally; pass --require to fail instead.
#
# Usage (from hephaestus root or an installed project):
#   bash scripts/verify-codex-load.sh
#   bash scripts/verify-codex-load.sh --require /path/to/project

set -uo pipefail

REQUIRE=0
PROJECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --require) REQUIRE=1 ;;
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

if ! command -v codex >/dev/null 2>&1; then
  if [ "$REQUIRE" -eq 1 ]; then
    echo "ERR: codex not on PATH" >&2
    exit 1
  fi
  echo "skip: codex not on PATH"
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

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"

# ── Skills ───────────────────────────────────────────────────────────────────
if SKILLS_DIR=$(resolve_root "start-issue/SKILL.md" \
      "$ROOT/.agents/skills" "$CODEX_HOME_DIR/skills"); then
  for skill in autopilot start-issue ship finish critique; do
    if [ ! -f "$SKILLS_DIR/$skill/SKILL.md" ]; then
      echo "ERR: missing Codex skill $SKILLS_DIR/$skill/SKILL.md" >&2
      fail=1
    elif ! grep -q "generated from .ai/workflows/$skill.md" "$SKILLS_DIR/$skill/SKILL.md"; then
      echo "ERR: Codex skill $skill is not generated from .ai/workflows/$skill.md" >&2
      fail=1
    fi
  done
else
  echo "ERR: no Codex skills root holds the generated skills — looked in" >&2
  echo "     $ROOT/.agents/skills and $CODEX_HOME_DIR/skills" >&2
  fail=1
fi

# ── Agent roles ──────────────────────────────────────────────────────────────
if AGENTS_DIR=$(resolve_root "coder.toml" \
      "$ROOT/.codex/agents" "$CODEX_HOME_DIR/agents"); then
  for agent in coder explorer reviewer tester researcher; do
    if [ ! -f "$AGENTS_DIR/$agent.toml" ]; then
      echo "ERR: missing Codex agent role $AGENTS_DIR/$agent.toml" >&2
      fail=1
    elif ! grep -q "generated from .claude/agents/$agent.md" "$AGENTS_DIR/$agent.toml"; then
      echo "ERR: Codex agent role $agent is not generated from .claude/agents/$agent.md" >&2
      fail=1
    fi
  done
else
  echo "ERR: no Codex agents root holds the generated roles — looked in" >&2
  echo "     $ROOT/.codex/agents and $CODEX_HOME_DIR/agents" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "✓ Codex takes the positional-prompt spawn form; skills and agent roles in place"
