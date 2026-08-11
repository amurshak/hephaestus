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

# ── Unattended contract ──────────────────────────────────────────────────────
# loop.sh runs `opencode run --auto --command autopilot`. --auto approves
# non-denied permissions; without it an unattended session stalls on the first
# gated write with no TTY to answer. Checked against `opencode run --help`
# because run's flag set is its own, not the top level's.
if ! run_help=$(opencode run --help 2>&1); then
  echo "ERR: opencode run --help failed" >&2
  exit 1
fi
# Word-boundary grep, not substring: a rename to --auto-approve or
# --command-file must fail this check, not satisfy it.
for flag in --auto --command; do
  if ! grep -qE "(^|[[:space:],])${flag}([[:space:],=]|$)" <<< "$run_help"; then
    echo "ERR: opencode run --help no longer documents ${flag}" >&2
    echo "     the opencode entry in loop.sh's dispatch table depends on it to run" >&2
    echo "     unattended — re-measure and update the dispatch table" >&2
    fail=1
  fi
done
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
