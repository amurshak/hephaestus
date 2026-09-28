#!/usr/bin/env bash
# #205: a locally modified fragment must not survive a release that reports success.
set -uo pipefail; SANDBOX=$1; source "$(dirname "$0")/../../lib/changelog-fixture.sh"
R="$FIX_ROOT/modified"; make_repo "$R"
printf '**Fix** (#129): an edited fix.\n' > "$R/changelog.d/129.fixed.md"
(cd "$R" && ./scripts/collect-changelog.sh 2.9.0 >/dev/null 2>&1); rc=$?
if [ "$rc" = 0 ]; then
  check "a successful release consumes every fragment" '[ "$(fragments "$R")" = 0 ]'
  check "the edited entry is published once" '[ "$(grep -c "an edited fix" "$R/CHANGELOG.md")" = 1 ]'
else
  check "a refused release changes nothing" '[ "$(fragments "$R")" = 2 ] && ! grep -q "^## 2.9.0" "$R/CHANGELOG.md"'
fi
R="$FIX_ROOT/clean"; make_repo "$R"
(cd "$R" && ./scripts/collect-changelog.sh 2.9.0 >/dev/null 2>&1); rc=$?
check "an unmodified release still succeeds" '[ "$rc" = 0 ] && [ "$(fragments "$R")" = 0 ]'
finish
