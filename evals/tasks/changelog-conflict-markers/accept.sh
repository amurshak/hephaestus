#!/usr/bin/env bash
# #209: a fragment with unresolved conflict markers must fail validation and block release.
set -uo pipefail; SANDBOX=$1; source "$(dirname "$0")/../../lib/changelog-fixture.sh"
R="$FIX_ROOT/conflict"; make_repo "$R"
printf '<<<<<<< HEAD\n**Fix** (#129): ours.\n=======\n**Fix** (#129): theirs.\n>>>>>>> branch\n' > "$R/changelog.d/129.fixed.md"
before=$(cat "$R/CHANGELOG.md")
(cd "$R" && ./scripts/collect-changelog.sh --check >/dev/null 2>&1); rc=$?
check "--check rejects conflict markers" '[ "$rc" != 0 ]'
(cd "$R" && ./scripts/collect-changelog.sh 2.9.0 >/dev/null 2>&1); rc=$?
check "release refuses" '[ "$rc" != 0 ]'
check "release writes nothing" '[ "$(cat "$R/CHANGELOG.md")" = "$before" ] && [ "$(fragments "$R")" = 2 ]'
R="$FIX_ROOT/clean"; make_repo "$R"
(cd "$R" && ./scripts/collect-changelog.sh --check >/dev/null 2>&1); rc=$?
check "clean fragments still pass --check" '[ "$rc" = 0 ]'
finish
