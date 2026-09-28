#!/usr/bin/env bash
# #206: --preview must render hand-written Unreleased entries the release would publish.
set -uo pipefail; SANDBOX=$1; source "$(dirname "$0")/../../lib/changelog-fixture.sh"
R="$FIX_ROOT/legacy"; make_repo "$R" $'### Added\n- Hand-written legacy entry.'
before=$(cat "$R/CHANGELOG.md")
out=$(cd "$R" && ./scripts/collect-changelog.sh --preview 2.9.0 2>&1); rc=$?
[ "$rc" = 0 ] || out=$(cd "$R" && ./scripts/collect-changelog.sh --preview 2>&1)
check "preview shows the legacy entry" 'grep -q "Hand-written legacy entry" <<<"$out"'
check "preview shows fragment entries" 'grep -q "a feature" <<<"$out" && grep -q "a fix" <<<"$out"'
check "preview changes nothing" '[ "$(cat "$R/CHANGELOG.md")" = "$before" ] && [ "$(fragments "$R")" = 2 ]'
(cd "$R" && ./scripts/collect-changelog.sh 2.9.0 >/dev/null 2>&1)
check "release still publishes the legacy entry once" '[ "$(grep -c "Hand-written legacy entry" "$R/CHANGELOG.md")" = 1 ]'
finish
