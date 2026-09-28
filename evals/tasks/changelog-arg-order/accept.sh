#!/usr/bin/env bash
# #183: no argument order or unknown flag may fall through to a real release.
set -uo pipefail; SANDBOX=$1; source "$(dirname "$0")/../../lib/changelog-fixture.sh"
for form in "2.9.0 --preview" "--preview 2.9.0" "2.9.0 --check" "2.9.0 --dry-run" "2.9.0 -n"; do
  R="$FIX_ROOT/$(printf '%s' "$form" | tr -cd '[:alnum:]')"; make_repo "$R"
  before=$(cat "$R/CHANGELOG.md")
  # shellcheck disable=SC2086
  (cd "$R" && ./scripts/collect-changelog.sh $form >/dev/null 2>&1)
  check "'$form' keeps every fragment" '[ "$(fragments "$R")" = 2 ]'
  check "'$form' leaves CHANGELOG.md unchanged" '[ "$(cat "$R/CHANGELOG.md")" = "$before" ]'
done
R="$FIX_ROOT/release"; make_repo "$R"
(cd "$R" && ./scripts/collect-changelog.sh 2.9.0 >/dev/null 2>&1); rc=$?
check "bare <version> still releases" '[ "$rc" = 0 ] && [ "$(fragments "$R")" = 0 ] && grep -q "^## 2.9.0" "$R/CHANGELOG.md"'
finish
