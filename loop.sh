#!/usr/bin/env bash
# loop.sh — Run autopilot in fresh sessions on a recurring interval
#
# Each iteration starts a new harness session so context stays clean.
#
# Run from the project root; the script itself lives in the hephaestus clone:
#   ~/.hephaestus/loop.sh                          # every 30 min (Claude)
#   ~/.hephaestus/loop.sh 15                       # every 15 min
#   ~/.hephaestus/loop.sh 30 /tmp/autopilot.log    # custom log path
#   HEPH_HARNESS=codex ~/.hephaestus/loop.sh 30    # claude|codex|cursor|hermes|opencode
#   HEPH_NO_PREFLIGHT=1 ~/.hephaestus/loop.sh      # skip the startup flag check
#
# Background (unattended):
#   nohup ~/.hephaestus/loop.sh 30 /tmp/autopilot.log &
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

# ── Harness dispatch ─────────────────────────────────────────────────────────
# One entry per harness: the binary to find on PATH, and the argv that runs
# /autopilot to completion with no TTY and no approval prompt. Each is the
# harness's own headless mode — deliberately not the TUI-seeding form /worktrees
# uses to spawn visible sessions, because an interactive session never exits, so
# the loop would never reach its sleep.
SUPPORTED_HARNESSES="claude codex cursor hermes opencode"

case "${HARNESS}" in
  claude)
    HARNESS_BIN=claude
    HARNESS_ARGV=(--dangerously-skip-permissions -p "/autopilot")
    ;;
  codex)
    # `codex exec` is the non-interactive mode. It has no --ask-for-approval —
    # without a TTY there is nobody to ask — so the sandbox is the only gate,
    # and it must be opened or `git push`/`gh` fail on blocked network.
    HARNESS_BIN=codex
    HARNESS_ARGV=(exec --dangerously-bypass-approvals-and-sandbox "/autopilot")
    ;;
  cursor)
    # -p is both the non-interactive mode and what dispatches the slash command:
    # the TUI owns the dispatcher, so a bare positional prompt reaches the model
    # as literal text. --force approves tool calls; --trust answers the
    # workspace-trust prompt, which would otherwise block with no TTY to take it.
    HARNESS_BIN=cursor-agent
    HARNESS_ARGV=(-p --force --trust "/autopilot")
    ;;
  hermes)
    # -q is single-query (non-interactive) mode, which bypasses the slash
    # dispatcher — so -s preloads the skill instead of sending /autopilot as
    # text. --yolo bypasses command approval; --accept-hooks is a separate gate
    # for shell hooks declared in config.yaml.
    #
    # The query carries its own guard because this is the one harness that can
    # fail silently: Hermes has no project-local skill discovery, and a -s that
    # resolves to nothing does not abort — it starts the session with no skill
    # loaded. Unguarded, that would leave a fully-approved agent looping in a
    # git repo on nothing but a one-line instruction. Wire the project's
    # .hermes/skills through skills.external_dirs or HERMES_HOME.
    HARNESS_BIN=hermes
    HARNESS_ARGV=(chat -s hephaestus/autopilot -q "Run the autopilot skill. If the autopilot skill is not loaded, stop and report that." --yolo --accept-hooks)
    ;;
  opencode)
    # --auto approves non-denied permissions for unattended runs.
    HARNESS_BIN=opencode
    HARNESS_ARGV=(run --auto --command autopilot)
    ;;
  *)
    echo "Error: HEPH_HARNESS must be one of: ${SUPPORTED_HARNESSES// /, }, got: '${HARNESS}'" >&2
    exit 1
    ;;
esac

# Guard: ensure the selected harness is on PATH. Name the binary that is missing
# (which is not always the harness name) and every harness that is not it.
if ! command -v "${HARNESS_BIN}" >/dev/null 2>&1; then
  ALTERNATIVES=""
  for h in ${SUPPORTED_HARNESSES}; do
    [ "$h" = "${HARNESS}" ] || ALTERNATIVES="${ALTERNATIVES}${ALTERNATIVES:+, }$h"
  done
  echo "Error: '${HARNESS_BIN}' not found on PATH. Install the ${HARNESS} CLI and put it on PATH, or set HEPH_HARNESS to one of: ${ALTERNATIVES}." >&2
  exit 1
fi

# Preflight: confirm the harness still documents every flag the dispatch table
# passes it, before taking the lock or entering the loop. A renamed approval
# flag does not fail like a missing binary — the harness starts, prompts, and
# hangs with no TTY to answer — so discovering it on iteration 1 means a silent,
# unbounded stall. One help invocation at startup; nothing per-iteration.
#
# The flags are read from HARNESS_ARGV itself, so there is no second copy to
# drift, and a leading subcommand (exec/chat/run) selects that subcommand's
# help — the flag sets differ from the top level. Help text is the honest
# ceiling here (cf. the Hermes config-parsing preflight rejected in #191); a
# harness that hides a working flag from its help can be waved through with
# HEPH_NO_PREFLIGHT=1.
if [ -z "${HEPH_NO_PREFLIGHT:-}" ]; then
  HELP_ARGV=(--help)
  case "${HARNESS_ARGV[0]}" in
    -*) ;;
    *) HELP_ARGV=("${HARNESS_ARGV[0]}" --help) ;;
  esac
  if ! HELP_TEXT=$("${HARNESS_BIN}" "${HELP_ARGV[@]}" </dev/null 2>&1) || [ -z "${HELP_TEXT}" ]; then
    echo "Error: '${HARNESS_BIN} ${HELP_ARGV[*]}' failed, so the unattended flags cannot be verified." >&2
    echo "       Fix the ${HARNESS} install, or skip this check with HEPH_NO_PREFLIGHT=1." >&2
    exit 1
  fi
  for flag in "${HARNESS_ARGV[@]}"; do
    case "${flag}" in -*) ;; *) continue ;; esac
    if ! grep -qE "(^|[[:space:],])${flag}([[:space:],=]|$)" <<< "${HELP_TEXT}"; then
      echo "Error: '${HARNESS_BIN} ${HELP_ARGV[*]}' no longer documents ${flag}." >&2
      echo "       The ${HARNESS} entry in loop.sh's dispatch table depends on it to run" >&2
      echo "       unattended — a session invoked without it can block on a prompt with no" >&2
      echo "       TTY to answer. Re-measure the CLI and update the dispatch table, or skip" >&2
      echo "       this check with HEPH_NO_PREFLIGHT=1 if the flag works but is undocumented." >&2
      exit 1
    fi
  done
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
echo "  Command  : ${HARNESS_BIN} ${HARNESS_ARGV[*]}"
echo "  Interval : ${INTERVAL_MINUTES} min"
echo "  Log      : ${LOG_FILE}"
echo "  PID      : $$"
echo "  Lock     : ${LOCK_DIR}"
echo "  Stop     : kill $$"
echo ""

run_session() {
  # </dev/null: nothing here may block on stdin. `codex exec` in particular
  # reads it whenever one is attached, which would hang the loop indefinitely.
  # Tolerate non-zero exit so the loop continues on failure.
  "${HARNESS_BIN}" "${HARNESS_ARGV[@]}" </dev/null 2>&1 | tee -a "${LOG_FILE}"
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
