#!/usr/bin/env bash
# run.sh — Run the hephaestus integration test suite
#
# Usage: ./tests/run.sh [test_file...]
#
# Runs all test_*.sh files, or only the specified files.
# Exit code: number of failed test files (0 = all pass).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

FILES_PASSED=0
FILES_FAILED=0
FAILED_FILES=""

echo ""
echo -e "${BOLD}Hephaestus Integration Tests${NC}"
echo "═══════════════════════════════════════"

# Determine which test files to run
if [ $# -gt 0 ]; then
  test_files=("$@")
else
  test_files=("$SCRIPT_DIR"/test_*.sh)
fi

for test_file in "${test_files[@]}"; do
  [ -e "$test_file" ] || continue
  name=$(basename "$test_file")

  echo ""
  echo -e "${BOLD}━━━ $name ━━━${NC}"

  if bash "$test_file"; then
    FILES_PASSED=$((FILES_PASSED + 1))
  else
    FILES_FAILED=$((FILES_FAILED + 1))
    FAILED_FILES="${FAILED_FILES:+$FAILED_FILES, }$name"
  fi
done

total=$((FILES_PASSED + FILES_FAILED))

echo ""
echo "═══════════════════════════════════════"
if [ "$FILES_FAILED" -eq 0 ]; then
  echo -e "${GREEN}All $total test files passed${NC}"
else
  echo -e "${RED}$FILES_FAILED of $total test files had failures${NC}"
  echo -e "${RED}Failed: $FAILED_FILES${NC}"
fi

exit "$FILES_FAILED"
