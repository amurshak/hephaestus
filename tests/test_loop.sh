#!/usr/bin/env bash
# test_loop.sh — Integration tests for loop.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

LOOP_SH="$HEPHAESTUS_ROOT/loop.sh"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Create a temporary directory with a mock `claude` on PATH that exits immediately.
setup_mock_claude() {
  MOCK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/heph-loop-test-XXXXXX")
  cat > "$MOCK_DIR/claude" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
  chmod +x "$MOCK_DIR/claude"
}

teardown_mock() {
  rm -rf "${MOCK_DIR:-}" 2>/dev/null || true
}

# Kill a background loop.sh and its children (sleep, tee, etc.).
# Sending SIGTERM to bash queues the signal until the foreground child (sleep)
# finishes. Killing children first unblocks bash so the trap fires promptly.
kill_loop() {
  local pid=$1
  kill "$pid" 2>/dev/null
  sleep 0.1
  pkill -P "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

trap teardown_mock EXIT

# ─────────────────────────────────────────────────────────────────────────────

begin_test "rejects non-numeric interval"
output=$(bash "$LOOP_SH" "abc" 2>&1)
exit_code=$?
assert_eq   "exits non-zero"              1 "$exit_code"
assert_contains "error mentions interval"  "$output" "positive integer"

# ─────────────────────────────────────────────────────────────────────────────

begin_test "rejects zero interval"
output=$(bash "$LOOP_SH" 0 2>&1)
exit_code=$?
assert_eq   "exits non-zero"              1 "$exit_code"
assert_contains "error mentions interval"  "$output" "positive integer"

# ─────────────────────────────────────────────────────────────────────────────

begin_test "rejects negative interval (treated as non-numeric)"
output=$(bash "$LOOP_SH" "-5" 2>&1)
exit_code=$?
assert_eq   "exits non-zero"              1 "$exit_code"
assert_contains "error mentions interval"  "$output" "positive integer"

# ─────────────────────────────────────────────────────────────────────────────

begin_test "fails when claude is not on PATH"
# Use empty PATH so claude won't be found (keep basic utils via env -i)
output=$(env PATH="/usr/bin:/bin" bash "$LOOP_SH" 1 2>&1)
exit_code=$?
assert_eq   "exits non-zero"              1 "$exit_code"
assert_contains "error mentions claude"    "$output" "claude"

# ─────────────────────────────────────────────────────────────────────────────

begin_test "fails when HEPH_HARNESS=opencode and opencode missing"
output=$(env PATH="/usr/bin:/bin" HEPH_HARNESS=opencode bash "$LOOP_SH" 1 2>&1)
exit_code=$?
assert_eq   "exits non-zero"                1 "$exit_code"
assert_contains "error mentions opencode"   "$output" "opencode"

# ─────────────────────────────────────────────────────────────────────────────

begin_test "rejects unknown HEPH_HARNESS"
setup_mock_claude
output=$(env PATH="$MOCK_DIR:$PATH" HEPH_HARNESS=gemini bash "$LOOP_SH" 1 2>&1)
exit_code=$?
assert_eq   "exits non-zero"               1 "$exit_code"
assert_contains "error mentions HEPH_HARNESS" "$output" "HEPH_HARNESS"
teardown_mock

# ─────────────────────────────────────────────────────────────────────────────

begin_test "creates lockfile and writes PID"
setup_mock_claude

# Run loop.sh in background with mock claude on PATH.
# It will run one session (mock exits instantly), then sleep.
env PATH="$MOCK_DIR:$PATH" bash "$LOOP_SH" 1 /dev/null &
LOOP_PID=$!

# Wait briefly for startup
sleep 1

# Determine expected lock dir (same hash algorithm as loop.sh)
EXPECTED_HASH=$(printf '%s' "$(pwd)" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12)
EXPECTED_LOCK="/tmp/hephaestus-${EXPECTED_HASH}.lock"

assert_dir_exists  "lockfile directory created"       "$EXPECTED_LOCK"
assert_file_exists "PID file exists inside lock"      "$EXPECTED_LOCK/pid"

RECORDED_PID=$(cat "$EXPECTED_LOCK/pid" 2>/dev/null || echo "missing")
assert_eq "PID file contains loop PID"  "$LOOP_PID" "$RECORDED_PID"

# Clean up
kill_loop "$LOOP_PID"
teardown_mock

# ─────────────────────────────────────────────────────────────────────────────

begin_test "lockfile is cleaned up on exit"
setup_mock_claude

EXPECTED_HASH=$(printf '%s' "$(pwd)" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12)
EXPECTED_LOCK="/tmp/hephaestus-${EXPECTED_HASH}.lock"

# Ensure no stale lock
rm -rf "$EXPECTED_LOCK" 2>/dev/null || true

env PATH="$MOCK_DIR:$PATH" bash "$LOOP_SH" 1 /dev/null &
LOOP_PID=$!
sleep 1

# Verify lock exists, then kill
assert_dir_exists "lock exists before kill" "$EXPECTED_LOCK"
kill_loop "$LOOP_PID"
sleep 0.5

assert_file_not_exists "lock cleaned up after kill" "$EXPECTED_LOCK"

teardown_mock

# ─────────────────────────────────────────────────────────────────────────────

begin_test "prevents concurrent instances"
setup_mock_claude

EXPECTED_HASH=$(printf '%s' "$(pwd)" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12)
EXPECTED_LOCK="/tmp/hephaestus-${EXPECTED_HASH}.lock"

# Ensure no stale lock
rm -rf "$EXPECTED_LOCK" 2>/dev/null || true

# Start first instance
env PATH="$MOCK_DIR:$PATH" bash "$LOOP_SH" 1 /dev/null &
LOOP_PID=$!
sleep 1

# Try to start second instance — should fail
output=$(env PATH="$MOCK_DIR:$PATH" bash "$LOOP_SH" 1 /dev/null 2>&1)
exit_code=$?
assert_eq       "second instance exits non-zero"     1 "$exit_code"
assert_contains "error mentions running instance"    "$output" "Another loop.sh instance"

# Clean up
kill_loop "$LOOP_PID"
teardown_mock

# ─────────────────────────────────────────────────────────────────────────────

begin_test "lockfile is unique per full path (not just basename)"
# Two directories with the same basename but different parents
TMPBASE=$(mktemp -d "${TMPDIR:-/tmp}/heph-path-test-XXXXXX")
mkdir -p "$TMPBASE/parent-a/myproject"
mkdir -p "$TMPBASE/parent-b/myproject"

HASH_A=$(printf '%s' "$TMPBASE/parent-a/myproject" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12)
HASH_B=$(printf '%s' "$TMPBASE/parent-b/myproject" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12)

assert_not_contains "different full paths produce different lock hashes" \
  "$HASH_A" "$HASH_B"

rm -rf "$TMPBASE"

# ─────────────────────────────────────────────────────────────────────────────

begin_test "defaults: 30 min interval and standard log path"
setup_mock_claude

EXPECTED_HASH=$(printf '%s' "$(pwd)" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12)
EXPECTED_LOCK="/tmp/hephaestus-${EXPECTED_HASH}.lock"
rm -rf "$EXPECTED_LOCK" 2>/dev/null || true

# Run with no args (defaults). Capture startup banner.
# Use a temp file because we need both background and output capture.
BANNER_FILE=$(mktemp "${TMPDIR:-/tmp}/heph-banner-XXXXXX")
env PATH="$MOCK_DIR:$PATH" bash "$LOOP_SH" > "$BANNER_FILE" 2>&1 &
LOOP_PID=$!
sleep 1

BANNER=$(cat "$BANNER_FILE")

assert_contains "banner shows 30 min interval"  "$BANNER" "Interval : 30 min"
assert_contains "banner shows default harness"  "$BANNER" "Harness  : claude"
assert_contains "banner shows default log path"  "$BANNER" "/tmp/hephaestus-autopilot.log"

kill_loop "$LOOP_PID"
rm -f "$BANNER_FILE"
teardown_mock

# ─────────────────────────────────────────────────────────────────────────────

begin_test "OpenCode harness runs mock opencode autopilot command"
MOCK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/heph-loop-test-XXXXXX")
ARGS_FILE="$MOCK_DIR/last-args"
# Write mock with absolute args path embedded (no sed / placeholders).
{
  echo '#!/usr/bin/env bash'
  echo "printf '%s\\n' \"\$@\" > \"$ARGS_FILE\""
  echo 'exit 0'
} > "$MOCK_DIR/opencode"
chmod +x "$MOCK_DIR/opencode"

EXPECTED_HASH=$(printf '%s' "$(pwd)" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12)
EXPECTED_LOCK="/tmp/hephaestus-${EXPECTED_HASH}.lock"
rm -rf "$EXPECTED_LOCK" 2>/dev/null || true

BANNER_FILE=$(mktemp "${TMPDIR:-/tmp}/heph-banner-XXXXXX")
env PATH="$MOCK_DIR:$PATH" HEPH_HARNESS=opencode bash "$LOOP_SH" 1 /dev/null > "$BANNER_FILE" 2>&1 &
LOOP_PID=$!
# Wait until mock is invoked (session happens before sleep)
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$ARGS_FILE" ] && break
  sleep 0.2
done

BANNER=$(cat "$BANNER_FILE")
assert_contains "banner shows opencode harness" "$BANNER" "Harness  : opencode"

ARGS=$(tr '\n' ' ' < "$ARGS_FILE" 2>/dev/null || echo missing)
assert_contains "invokes opencode run" "$ARGS" "run"
assert_contains "uses --command autopilot" "$ARGS" "autopilot"
assert_contains "auto-approves permissions" "$ARGS" "--auto"

kill_loop "$LOOP_PID"
rm -f "$BANNER_FILE"
rm -rf "$MOCK_DIR"

# ─────────────────────────────────────────────────────────────────────────────

print_summary

