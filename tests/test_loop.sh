#!/usr/bin/env bash
# test_loop.sh — Integration tests for loop.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

LOOP_SH="$HEPHAESTUS_ROOT/loop.sh"

# ── Helpers ──────────────────────────────────────────────────────────────────

# The harness dispatch table under test: harness|binary|argv…
# Each row is the headless form loop.sh must invoke — the harness's own
# non-interactive mode, not the TUI-seeding form /worktrees spawns.
#
# The argv is the COMPLETE, ORDERED expected argument vector, asserted whole.
# Asserting token presence instead would be near-worthless here: order is the
# invariant that matters most. `-q --accept-hooks` makes Hermes swallow the
# hooks flag as its query text, and `--dangerously-bypass-approvals-and-sandbox
# /autopilot exec` demotes Codex's subcommand to a positional — both are
# argv-token-identical to the correct forms, and both would ship silently.
HARNESS_CASES=(
  "claude|claude|--dangerously-skip-permissions|-p|/autopilot"
  "codex|codex|exec|--dangerously-bypass-approvals-and-sandbox|/autopilot"
  "cursor|cursor-agent|-p|--force|--trust|/autopilot"
  "hermes|hermes|chat|-s|hephaestus/autopilot|-q|Run the autopilot skill. If the autopilot skill is not loaded, stop and report that.|--yolo|--accept-hooks"
  "opencode|opencode|run|--auto|--command|autopilot"
)

# Every unattended flag from every dispatch row, space-separated so the
# preflight's word-boundary grep matches each one. A mock prints the whole set
# on --help — the preflight only asks for its own harness's flags, so the
# surplus is harmless and one line serves all five mocks.
ALL_UNATTENDED_FLAGS="--dangerously-skip-permissions -p --dangerously-bypass-approvals-and-sandbox --force --trust -s -q --yolo --accept-hooks --auto --command"

# Create a temp dir holding a mock harness binary that records its argv, one
# argument per line, to $ARGS_FILE and exits immediately. A --help call is the
# preflight, not the session: it answers with the flag list, records its argv
# separately to $HELP_ARGS_FILE, and must never touch $ARGS_FILE — the tests
# use a non-empty $ARGS_FILE as the signal that the real session dispatched.
setup_mock_harness() {
  MOCK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/heph-loop-test-XXXXXX")
  ARGS_FILE="$MOCK_DIR/last-args"
  HELP_ARGS_FILE="$MOCK_DIR/help-args"
  # Embed the absolute paths directly — no sed, no placeholders.
  {
    echo '#!/usr/bin/env bash'
    echo 'for a in "$@"; do'
    echo '  if [ "$a" = "--help" ]; then'
    echo "    printf '%s\\n' \"\$@\" > \"$HELP_ARGS_FILE\""
    echo "    echo \"${2-$ALL_UNATTENDED_FLAGS}\""
    echo '    exit 0'
    echo '  fi'
    echo 'done'
    echo "printf '%s\\n' \"\$@\" > \"$ARGS_FILE\""
    echo 'exit 0'
  } > "$MOCK_DIR/$1"
  chmod +x "$MOCK_DIR/$1"
}

# Back-compat alias for the lockfile/banner tests, which only need a harness
# that exits cleanly and default to claude.
setup_mock_claude() { setup_mock_harness claude; }

# Recorded argv canonicalized to |a|b|c| so it can be compared whole against a
# table row. Delimited rather than space-joined because Hermes's query argument
# contains spaces, which a space-joined string could not tell from two arguments.
recorded_argv() {
  printf '|%s' "$(tr '\n' '|' < "$ARGS_FILE" 2>/dev/null || echo missing)"
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

begin_test "PATH guard names the missing binary and the other harnesses"
# A PATH with no harness on it, so every case below hits the guard.
for case_row in "${HARNESS_CASES[@]}"; do
  IFS='|' read -r harness binary _ <<< "$case_row"

  output=$(env PATH="/usr/bin:/bin" HEPH_HARNESS="$harness" bash "$LOOP_SH" 1 2>&1)
  exit_code=$?
  assert_eq       "$harness: exits non-zero"          1 "$exit_code"
  assert_contains "$harness: names the binary"        "$output" "'$binary' not found on PATH"

  # The remediation must offer the other four and never the one just rejected.
  # Match on the list alone: the harness name also appears in "Install the
  # <harness> CLI" earlier in the same message.
  alternatives=${output##*one of: }
  assert_not_contains "$harness: alternatives exclude itself" "$alternatives" "$harness"
  for other_row in "${HARNESS_CASES[@]}"; do
    IFS='|' read -r other _ <<< "$other_row"
    [ "$other" = "$harness" ] && continue
    assert_contains "$harness: alternatives offer $other" "$alternatives" "$other"
  done
done

# ─────────────────────────────────────────────────────────────────────────────

begin_test "default harness is claude when HEPH_HARNESS is unset"
output=$(env PATH="/usr/bin:/bin" bash "$LOOP_SH" 1 2>&1)
exit_code=$?
assert_eq   "exits non-zero"            1 "$exit_code"
assert_contains "guards the claude CLI"  "$output" "'claude' not found on PATH"

# ─────────────────────────────────────────────────────────────────────────────

begin_test "rejects unknown HEPH_HARNESS and lists every supported one"
setup_mock_claude
output=$(env PATH="$MOCK_DIR:$PATH" HEPH_HARNESS=gemini bash "$LOOP_SH" 1 2>&1)
exit_code=$?
assert_eq   "exits non-zero"               1 "$exit_code"
assert_contains "error mentions HEPH_HARNESS" "$output" "HEPH_HARNESS"
for case_row in "${HARNESS_CASES[@]}"; do
  IFS='|' read -r harness _ <<< "$case_row"
  assert_contains "error lists $harness" "$output" "$harness"
done
teardown_mock

# ─────────────────────────────────────────────────────────────────────────────

begin_test "creates lockfile and writes PID"
setup_mock_claude

# Determine expected lock dir (same hash algorithm as loop.sh)
EXPECTED_HASH=$(printf '%s' "$(pwd)" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12)
EXPECTED_LOCK="/tmp/hephaestus-${EXPECTED_HASH}.lock"

# Ensure no stale lock — loop.sh refuses to start against one
rm -rf "$EXPECTED_LOCK" 2>/dev/null || true

# Run loop.sh in background with mock claude on PATH.
# It will run one session (mock exits instantly), then sleep.
env PATH="$MOCK_DIR:$PATH" bash "$LOOP_SH" 1 /dev/null &
LOOP_PID=$!

# loop.sh writes the PID immediately after taking the lock, so a non-empty
# pid file is the readiness signal for all three assertions below.
wait_for 10 '[ -s "$EXPECTED_LOCK/pid" ]'

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
wait_for 10 '[ -s "$EXPECTED_LOCK/pid" ]'

# Verify lock exists, then kill
assert_dir_exists "lock exists before kill" "$EXPECTED_LOCK"
kill_loop "$LOOP_PID"
wait_for 10 '[ ! -e "$EXPECTED_LOCK" ]'

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
wait_for 10 '[ -s "$EXPECTED_LOCK/pid" ]'

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
# "Stop" is the banner's last line — waiting for it means every asserted line landed.
wait_for 10 'grep -qF "Stop     : kill" "$BANNER_FILE"'

BANNER=$(cat "$BANNER_FILE")

assert_contains "banner shows 30 min interval"  "$BANNER" "Interval : 30 min"
assert_contains "banner shows default harness"  "$BANNER" "Harness  : claude"
assert_contains "banner shows default log path"  "$BANNER" "/tmp/hephaestus-autopilot.log"

kill_loop "$LOOP_PID"
rm -f "$BANNER_FILE"
teardown_mock

# ─────────────────────────────────────────────────────────────────────────────

begin_test "every harness dispatches its documented headless form"
for case_row in "${HARNESS_CASES[@]}"; do
  IFS='|' read -r harness binary expected_argv <<< "$case_row"

  setup_mock_harness "$binary"

  EXPECTED_HASH=$(printf '%s' "$(pwd)" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12)
  EXPECTED_LOCK="/tmp/hephaestus-${EXPECTED_HASH}.lock"
  rm -rf "$EXPECTED_LOCK" 2>/dev/null || true

  BANNER_FILE=$(mktemp "${TMPDIR:-/tmp}/heph-banner-XXXXXX")
  env PATH="$MOCK_DIR:$PATH" HEPH_HARNESS="$harness" bash "$LOOP_SH" 1 /dev/null \
    > "$BANNER_FILE" 2>&1 &
  LOOP_PID=$!
  # The session runs after the banner and before the sleep, so a non-empty args
  # file means both the banner and the dispatch have landed.
  wait_for 10 '[ -s "$ARGS_FILE" ]'

  BANNER=$(cat "$BANNER_FILE")
  assert_contains "$harness: banner names the harness" "$BANNER" "Harness  : $harness"
  assert_contains "$harness: banner echoes the command" "$BANNER" "Command  : $binary "

  assert_eq "$harness: argv matches exactly, in order" \
    "|$expected_argv|" "$(recorded_argv)"

  # The preflight must consult the help of what actually runs: the subcommand's
  # (exec/chat/run) when the entry leads with one — the flag sets differ from
  # the top level — and the binary's own otherwise.
  expected_help="--help"
  first_tok=${expected_argv%%|*}
  case "$first_tok" in -*) ;; *) expected_help="$first_tok|--help" ;; esac
  assert_eq "$harness: preflight asked the right help" \
    "|$expected_help|" "$(printf '|%s' "$(tr '\n' '|' < "$HELP_ARGS_FILE" 2>/dev/null || echo missing)")"

  kill_loop "$LOOP_PID"
  rm -f "$BANNER_FILE"
  teardown_mock
done

# ─────────────────────────────────────────────────────────────────────────────

begin_test "preflight fails loudly when the harness drops an unattended flag"
# A dropped approval flag does not fail like a missing binary — the harness
# starts, prompts, and hangs with no TTY to answer. The preflight must turn
# that into a loud startup error, before the lock and before any session.
setup_mock_harness cursor-agent "-p --force"

EXPECTED_HASH=$(printf '%s' "$(pwd)" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12)
EXPECTED_LOCK="/tmp/hephaestus-${EXPECTED_HASH}.lock"
rm -rf "$EXPECTED_LOCK" 2>/dev/null || true

output=$(env PATH="$MOCK_DIR:$PATH" HEPH_HARNESS=cursor bash "$LOOP_SH" 1 /dev/null 2>&1)
exit_code=$?
assert_eq       "exits non-zero"                 1 "$exit_code"
assert_contains "names the missing flag"         "$output" "no longer documents --trust"
assert_contains "points at the dispatch table"   "$output" "dispatch table"
assert_file_not_exists "no session dispatched"   "$ARGS_FILE"
assert_file_not_exists "no lock left behind"     "$EXPECTED_LOCK"

# =0 must not disable the check: every doc says =1, and an env var somebody
# exported as 0 to mean "off is off" would otherwise silently skip it.
output=$(env PATH="$MOCK_DIR:$PATH" HEPH_HARNESS=cursor HEPH_NO_PREFLIGHT=0 \
  bash "$LOOP_SH" 1 /dev/null 2>&1)
assert_eq "HEPH_NO_PREFLIGHT=0 still preflights" 1 "$?"
teardown_mock

# ─────────────────────────────────────────────────────────────────────────────

begin_test "preflight reports a help call that fails or prints nothing"
# A help that exits non-zero (or hangs into the timeout) leaves nothing to
# verify against; the loop must say so and stop, not proceed unverified.
setup_mock_harness claude
printf '#!/usr/bin/env bash\n[ "$1" = "--help" ] && exit 3\nexit 0\n' > "$MOCK_DIR/claude"
chmod +x "$MOCK_DIR/claude"

output=$(env PATH="$MOCK_DIR:$PATH" bash "$LOOP_SH" 1 /dev/null 2>&1)
assert_eq       "exits non-zero"        1 "$?"
assert_contains "names the failed help" "$output" "failed or printed nothing"

# Exit 0 with empty output is the same dead end and takes the same branch.
printf '#!/usr/bin/env bash\nexit 0\n' > "$MOCK_DIR/claude"
chmod +x "$MOCK_DIR/claude"
output=$(env PATH="$MOCK_DIR:$PATH" bash "$LOOP_SH" 1 /dev/null 2>&1)
assert_eq       "empty help exits non-zero" 1 "$?"
assert_contains "names the empty help"      "$output" "failed or printed nothing"
teardown_mock

# ─────────────────────────────────────────────────────────────────────────────

begin_test "HEPH_NO_PREFLIGHT=1 waves an undocumented flag through"
# The escape hatch for a harness whose flag works but is hidden from its help:
# the same broken help output must not stop the loop when the user opts out.
setup_mock_harness cursor-agent "-p --force"

EXPECTED_HASH=$(printf '%s' "$(pwd)" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12)
EXPECTED_LOCK="/tmp/hephaestus-${EXPECTED_HASH}.lock"
rm -rf "$EXPECTED_LOCK" 2>/dev/null || true

env PATH="$MOCK_DIR:$PATH" HEPH_HARNESS=cursor HEPH_NO_PREFLIGHT=1 \
  bash "$LOOP_SH" 1 /dev/null > /dev/null 2>&1 &
LOOP_PID=$!
wait_for 10 '[ -s "$ARGS_FILE" ]'
assert_eq "session dispatched despite the broken help" \
  "|-p|--force|--trust|/autopilot|" "$(recorded_argv)"
kill_loop "$LOOP_PID"
teardown_mock

# ─────────────────────────────────────────────────────────────────────────────

begin_test "the session cannot block on stdin"
# `codex exec` reads stdin whenever one is attached, so loop.sh runs the harness
# with </dev/null. Proving that needs a stdin that would otherwise never reach
# EOF — inherit the test runner's and the check passes vacuously under CI, where
# stdin is already closed. So: hand loop.sh a FIFO held open by a writer that
# sends nothing, and give the mock a `cat` that returns only at EOF. With the
# redirect the mock records its argv at once; without it, it blocks forever and
# wait_for times out.
MOCK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/heph-loop-test-XXXXXX")
ARGS_FILE="$MOCK_DIR/last-args"
{
  echo '#!/usr/bin/env bash'
  # Answer the preflight without touching $ARGS_FILE: a non-empty args file is
  # this test's proof that the *session* ran, and the preflight must not fake it.
  echo "[ \"\$1\" = \"--help\" ] && { echo \"$ALL_UNATTENDED_FLAGS\"; exit 0; }"
  echo 'cat > /dev/null'
  echo "printf '%s\\n' \"\$@\" > \"$ARGS_FILE\""
  echo 'exit 0'
} > "$MOCK_DIR/claude"
chmod +x "$MOCK_DIR/claude"

STDIN_FIFO="$MOCK_DIR/stdin"
mkfifo "$STDIN_FIFO"
# Holds the write end open without writing, so the FIFO never signals EOF.
sleep 30 > "$STDIN_FIFO" &
HOLDER_PID=$!

EXPECTED_HASH=$(printf '%s' "$(pwd)" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12)
EXPECTED_LOCK="/tmp/hephaestus-${EXPECTED_HASH}.lock"
rm -rf "$EXPECTED_LOCK" 2>/dev/null || true

env PATH="$MOCK_DIR:$PATH" bash "$LOOP_SH" 1 /dev/null \
  < "$STDIN_FIFO" > /dev/null 2>&1 &
LOOP_PID=$!

wait_for 10 '[ -s "$ARGS_FILE" ]'
assert_file_exists "harness ran instead of hanging on an open stdin" "$ARGS_FILE"

kill_loop "$LOOP_PID"
kill "$HOLDER_PID" 2>/dev/null || true
wait "$HOLDER_PID" 2>/dev/null || true
teardown_mock

# ─────────────────────────────────────────────────────────────────────────────

print_summary

