# Shared fixture for changelog acceptance checks. Sourced by accept.sh with
# SANDBOX set to the repository under evaluation. Asserts behavior only —
# exit codes and file state — never the wording of a message.
FIX_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/heph-accept-XXXXXX")
trap 'rm -rf "$FIX_ROOT"' EXIT
failures=0
check() { if eval "$2"; then :; else echo "FAIL: $1"; failures=$((failures + 1)); fi; }

make_repo() { # make_repo <dir> [unreleased-body]
  local dest="$1" unreleased="${2:-}"
  mkdir -p "$dest/scripts" "$dest/changelog.d"
  cp "$SANDBOX/scripts/collect-changelog.sh" "$dest/scripts/"
  printf '# changelog.d/\n\nFragment docs.\n' > "$dest/changelog.d/README.md"
  { printf '# Changelog\n\n## Unreleased\n'
    [ -n "$unreleased" ] && printf '\n%s\n' "$unreleased"
    printf '\n## 2.1.0 — 2026-07-28\n\n### Added\n- Older stuff.\n'; } > "$dest/CHANGELOG.md"
  printf '**Feature** (#107): a feature.\n' > "$dest/changelog.d/107.added.md"
  printf '**Fix** (#129): a fix.\n' > "$dest/changelog.d/129.fixed.md"
  git -C "$dest" init -q && git -C "$dest" add -A && git -C "$dest" -c user.name=e -c user.email=e@e commit -qm base
}
fragments() { ls "$1/changelog.d" | grep -vc '^README.md$'; }
finish() { [ "$failures" -eq 0 ] && echo "accepted" || { echo "$failures check(s) failed"; exit 1; }; }
