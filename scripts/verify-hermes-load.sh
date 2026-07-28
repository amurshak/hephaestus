#!/usr/bin/env bash
# verify-hermes-load.sh — Confirm Hermes discovers hephaestus skills.
#
# Hermes has no project-local skill discovery: it reads ~/.hermes/skills plus
# whatever `skills.external_dirs` names. So this checks the wiring, not just the
# files, and prints the exact YAML to add when the wiring is missing.
#
# Requires `hermes` on PATH. Exit 0 when the CLI is absent so the script can stay
# in CI optionally; pass --require to fail instead.
#
# Usage (from hephaestus root or an installed project):
#   bash scripts/verify-hermes-load.sh
#   bash .hephaestus/scripts/verify-hermes-load.sh
#   bash scripts/verify-hermes-load.sh --require /path/to/project

set -uo pipefail

REQUIRE=0
if [ "${1:-}" = "--require" ]; then
  REQUIRE=1
  shift
fi

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Verify the *project's* skills, not the submodule's. Run from an installed
# project the script lives at <project>/.hephaestus/scripts/, and it is
# <project>/.hermes/skills that install.sh links and tells the user to wire —
# the submodule copy has no project-specific orient. Prefer the directory the
# user ran from, since `cd`-resolving the script path follows a symlinked
# .hephaestus back into the shared checkout. An explicit argument wins.
if [ -n "${1:-}" ]; then
  ROOT="$(cd "$1" && pwd)" || exit 1
elif [ -d "$PWD/.hermes/skills" ]; then
  ROOT="$PWD"
elif [ "$(basename "$SRC")" = ".hephaestus" ]; then
  ROOT="$(cd "$SRC/.." && pwd)"
else
  ROOT="$SRC"
fi
cd "$ROOT" || exit 1
SKILLS_DIR="$ROOT/.hermes/skills"

if ! command -v hermes >/dev/null 2>&1; then
  if [ "$REQUIRE" -eq 1 ]; then
    echo "ERR: hermes not on PATH" >&2
    exit 1
  fi
  echo "skip: hermes not on PATH"
  exit 0
fi

fail=0

# ── Delegate briefs ──────────────────────────────────────────────────────────
for agent in coder explorer reviewer tester researcher; do
  if [ ! -f ".hermes/agents/$agent.md" ]; then
    echo "ERR: missing Hermes delegate brief .hermes/agents/$agent.md" >&2
    fail=1
  elif ! grep -q "generated from .claude/agents/$agent.md" ".hermes/agents/$agent.md"; then
    echo "ERR: Hermes delegate brief $agent is not generated from .claude/agents/$agent.md" >&2
    fail=1
  fi
done

# ── Discovery wiring ─────────────────────────────────────────────────────────
# Wired either by skills.external_dirs naming this project's .hermes/skills, or
# by HERMES_HOME pointing at this project's .hermes (whose skills/ is native).
wired=0
if [ "${HERMES_HOME:-}" = "$ROOT/.hermes" ]; then
  wired=1
  echo "  ✓ HERMES_HOME points at $ROOT/.hermes"
elif cfg_path=$(hermes config path 2>/dev/null) && [ -f "$cfg_path" ]; then
  if grep -qF "$SKILLS_DIR" "$cfg_path"; then
    wired=1
    echo "  ✓ skills.external_dirs names $SKILLS_DIR"
  fi
fi

if [ "$wired" -eq 0 ]; then
  echo "ERR: Hermes is not wired to this project's skills." >&2
  echo "     Add to $(hermes config path 2>/dev/null || echo '~/.hermes/config.yaml') under the top-level \`skills:\` key:" >&2
  echo "" >&2
  echo "       skills:" >&2
  echo "         external_dirs:" >&2
  echo "           - $SKILLS_DIR" >&2
  echo "" >&2
  echo "     Or start Hermes with HERMES_HOME=$ROOT/.hermes for a project-scoped profile." >&2
  exit 1
fi

# ── Live skill listing ───────────────────────────────────────────────────────
if ! listing=$(hermes skills list 2>/dev/null); then
  echo "ERR: hermes skills list failed" >&2
  exit 1
fi

for skill in autopilot start-issue ship finish critique; do
  case "$listing" in
    *"$skill"*) ;;
    *)
      echo "ERR: Hermes skill listing missing $skill" >&2
      fail=1
      ;;
  esac
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "✓ Hermes loads hephaestus skills and delegate briefs"
