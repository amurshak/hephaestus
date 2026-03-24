#!/usr/bin/env bash
# loop.sh — Run autopilot in fresh Claude sessions on a recurring interval
#
# Each iteration starts a new Claude session, ensuring you always get the
# latest Claude capabilities and a clean context window.
#
# Usage (from the project root where hephaestus is installed):
#   ./.hephaestus/loop.sh                          # every 30 min
#   ./.hephaestus/loop.sh 15                       # every 15 min
#   ./.hephaestus/loop.sh 30 /tmp/autopilot.log    # custom log path
#
# Background (unattended):
#   nohup ./.hephaestus/loop.sh 30 /tmp/autopilot.log &
#   echo $! > autopilot.pid   # save PID to kill later
#
# Stop:
#   kill $(cat autopilot.pid)

set -uo pipefail

INTERVAL_MINUTES=${1:-30}
LOG_FILE=${2:-/tmp/hephaestus-autopilot.log}

# Validate interval is a positive integer (must be before arithmetic expansion)
if ! [[ "${INTERVAL_MINUTES}" =~ ^[0-9]+$ ]] || [ "${INTERVAL_MINUTES}" -lt 1 ]; then
  echo "Error: interval must be a positive integer (minutes), got: '${INTERVAL_MINUTES}'" >&2
  exit 1
fi

INTERVAL_SECONDS=$((INTERVAL_MINUTES * 60))

# Guard: ensure claude is on PATH (may not be set in headless/nohup environments)
if ! command -v claude >/dev/null 2>&1; then
  echo "Error: 'claude' not found on PATH. Ensure the Claude Code CLI is installed and on PATH." >&2
  exit 1
fi

# Lockfile: prevent concurrent instances from conflicting.
# Use project-scoped name and mkdir for atomic lock (avoids TOCTOU race).
# Hash the full path (not just basename) to avoid collisions between
# identically-named directories under different parents.
LOCK_DIR="/tmp/hephaestus-$(printf '%s' "$(pwd)" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12).lock"
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  LOCK_PID=$(cat "${LOCK_DIR}/pid" 2>/dev/null || echo "unknown")
  echo "Error: Another loop.sh instance is running for this project (PID ${LOCK_PID})." >&2
  echo "       Remove lock manually if the process is gone: rm -rf '${LOCK_DIR}'" >&2
  exit 1
fi
echo $$ > "${LOCK_DIR}/pid"
trap 'rm -rf "${LOCK_DIR}"; exit' INT TERM EXIT

echo "Hephaestus autopilot loop"
echo "  Interval : ${INTERVAL_MINUTES} min"
echo "  Log      : ${LOG_FILE}"
echo "  PID      : $$"
echo "  Lock     : ${LOCK_DIR}"
echo "  Stop     : kill $$"
echo ""

while true; do
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[${TIMESTAMP}] Starting autopilot session..." | tee -a "${LOG_FILE}"

  # Run claude; tolerate non-zero exit so the loop continues on failure.
  # Use PIPESTATUS[0] to capture claude's exit code, not tee's.
  claude --dangerously-skip-permissions -p "/autopilot" 2>&1 | tee -a "${LOG_FILE}"
  CLAUDE_EXIT="${PIPESTATUS[0]}"

  if [ "${CLAUDE_EXIT}" -ne 0 ]; then
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${TIMESTAMP}] Session exited with error (code ${CLAUDE_EXIT}). Continuing loop." | tee -a "${LOG_FILE}"
  fi

  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[${TIMESTAMP}] Session complete. Next run in ${INTERVAL_MINUTES} min." | tee -a "${LOG_FILE}"
  echo "" | tee -a "${LOG_FILE}"

  sleep "${INTERVAL_SECONDS}"
done
