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
#   nohup ./.hephaestus/loop.sh 30 > autopilot.log 2>&1 &
#   echo $! > autopilot.pid   # save PID to kill later
#
# Stop:
#   kill $(cat autopilot.pid)

set -euo pipefail

INTERVAL_MINUTES=${1:-30}
INTERVAL_SECONDS=$((INTERVAL_MINUTES * 60))
LOG_FILE=${2:-/tmp/hephaestus-autopilot.log}

echo "Hephaestus autopilot loop"
echo "  Interval : ${INTERVAL_MINUTES} min"
echo "  Log      : ${LOG_FILE}"
echo "  PID      : $$"
echo "  Stop     : kill $$"
echo ""

while true; do
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[${TIMESTAMP}] Starting autopilot session..." | tee -a "${LOG_FILE}"

  claude --dangerously-skip-permissions -p "/autopilot" 2>&1 | tee -a "${LOG_FILE}"

  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[${TIMESTAMP}] Session complete. Next run in ${INTERVAL_MINUTES} min." | tee -a "${LOG_FILE}"
  echo "" | tee -a "${LOG_FILE}"

  sleep "${INTERVAL_SECONDS}"
done
