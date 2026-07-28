#!/usr/bin/env bash
# loop.sh — Run autopilot in fresh sessions on a recurring interval
#
# Each iteration starts a new harness session so context stays clean.
#
# Usage (from the project root where hephaestus is installed):
#   ./.hephaestus/loop.sh                          # every 30 min (Claude)
#   ./.hephaestus/loop.sh 15                       # every 15 min
#   ./.hephaestus/loop.sh 30 /tmp/autopilot.log    # custom log path
#   HEPH_HARNESS=opencode ./.hephaestus/loop.sh 30 # OpenCode instead of Claude
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
HARNESS=${HEPH_HARNESS:-claude}

# Validate interval is a positive integer (must be before arithmetic expansion)
if ! [[ "${INTERVAL_MINUTES}" =~ ^[0-9]+$ ]] || [ "${INTERVAL_MINUTES}" -lt 1 ]; then
  echo "Error: interval must be a positive integer (minutes), got: '${INTERVAL_MINUTES}'" >&2
  exit 1
fi

INTERVAL_SECONDS=$((INTERVAL_MINUTES * 60))

case "${HARNESS}" in
  claude|opencode) ;;
  *)
    echo "Error: HEPH_HARNESS must be 'claude' or 'opencode', got: '${HARNESS}'" >&2
    exit 1
    ;;
esac

# Guard: ensure the selected harness is on PATH
if [ "${HARNESS}" = "claude" ]; then
  if ! command -v claude >/dev/null 2>&1; then
    echo "Error: 'claude' not found on PATH. Ensure the Claude Code CLI is installed and on PATH, or set HEPH_HARNESS=opencode." >&2
    exit 1
  fi
else
  if ! command -v opencode >/dev/null 2>&1; then
    echo "Error: 'opencode' not found on PATH. Ensure the OpenCode CLI is installed and on PATH, or unset HEPH_HARNESS." >&2
    exit 1
  fi
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

SLEEP_PID=""
cleanup() {
  if [ -n "${SLEEP_PID}" ]; then
    kill "${SLEEP_PID}" 2>/dev/null || true
    wait "${SLEEP_PID}" 2>/dev/null || true
  fi
  rm -rf "${LOCK_DIR}"
}
trap 'cleanup; exit' INT TERM
trap 'cleanup' EXIT

echo "Hephaestus autopilot loop"
echo "  Harness  : ${HARNESS}"
echo "  Interval : ${INTERVAL_MINUTES} min"
echo "  Log      : ${LOG_FILE}"
echo "  PID      : $$"
echo "  Lock     : ${LOCK_DIR}"
echo "  Stop     : kill $$"
echo ""

run_session() {
  if [ "${HARNESS}" = "claude" ]; then
    # Tolerate non-zero exit so the loop continues on failure.
    claude --dangerously-skip-permissions -p "/autopilot" 2>&1 | tee -a "${LOG_FILE}"
    return "${PIPESTATUS[0]}"
  fi
  # OpenCode: project-root cwd is required so .opencode/ commands load.
  # --auto approves non-denied permissions for unattended runs.
  opencode run --auto --command autopilot 2>&1 | tee -a "${LOG_FILE}"
  return "${PIPESTATUS[0]}"
}

while true; do
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[${TIMESTAMP}] Starting autopilot session (${HARNESS})..." | tee -a "${LOG_FILE}"

  run_session
  SESSION_EXIT=$?

  if [ "${SESSION_EXIT}" -ne 0 ]; then
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${TIMESTAMP}] Session exited with error (code ${SESSION_EXIT}). Continuing loop." | tee -a "${LOG_FILE}"
  fi

  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[${TIMESTAMP}] Session complete. Next run in ${INTERVAL_MINUTES} min." | tee -a "${LOG_FILE}"
  echo "" | tee -a "${LOG_FILE}"

  sleep "${INTERVAL_SECONDS}" &
  SLEEP_PID=$!
  wait "${SLEEP_PID}"
  SLEEP_PID=""
done
