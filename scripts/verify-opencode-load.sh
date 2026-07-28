#!/usr/bin/env bash
# verify-opencode-load.sh — Confirm OpenCode loads hephaestus adapters from cwd.
#
# Requires `opencode` on PATH. Exit 0 permanently when the CLI is absent so the
# script can stay in CI optionally; pass --require to fail instead.
#
# Usage (from hephaestus root or an installed project):
#   bash scripts/verify-opencode-load.sh
#   bash scripts/verify-opencode-load.sh --require

set -uo pipefail

REQUIRE=0
if [ "${1:-}" = "--require" ]; then
  REQUIRE=1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

if ! command -v opencode >/dev/null 2>&1; then
  if [ "$REQUIRE" -eq 1 ]; then
    echo "ERR: opencode not on PATH" >&2
    exit 1
  fi
  echo "skip: opencode not on PATH"
  exit 0
fi

export XDG_DATA_HOME="${XDG_DATA_HOME:-${TMPDIR:-/tmp}/hephaestus-opencode-data}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${TMPDIR:-/tmp}/hephaestus-opencode-cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${TMPDIR:-/tmp}/hephaestus-opencode-config}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" 2>/dev/null || true

if ! cfg=$(opencode debug config 2>/dev/null); then
  echo "ERR: opencode debug config failed" >&2
  exit 1
fi

fail=0
for cmd in autopilot ship finish start-issue critique; do
  case "$cfg" in
    *\"$cmd\"*) ;;
    *)
    echo "ERR: OpenCode config missing command $cmd" >&2
    fail=1
    ;;
  esac
done

for agent in coder explorer reviewer tester researcher; do
  if [ ! -f ".opencode/agents/$agent.md" ]; then
    echo "ERR: missing OpenCode agent adapter .opencode/agents/$agent.md" >&2
    fail=1
  elif ! grep -q "generated from .claude/agents/$agent.md" ".opencode/agents/$agent.md"; then
    echo "ERR: OpenCode agent adapter $agent is not generated from .claude/agents/$agent.md" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "✓ OpenCode loads hephaestus commands and agent adapters"
