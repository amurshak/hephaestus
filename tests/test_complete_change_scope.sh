#!/usr/bin/env bash
# Execute the canonical scope commands against tiny Git fixtures, not harnesses.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

scope_section() {
  awk '/^## Task change scope$/ { found=1; next } found && /^#/ { exit } found { print }' "$1"
}

scope_contract=$(scope_section "$HEPHAESTUS_ROOT/.ai/workflows/critique.md")

begin_test "all six standalone entry points share one task scope"
for path in workflows/critique workflows/test-issue workflows/start-issue workflows/ship agents/reviewer agents/tester; do
  assert_eq "$path scope agrees" "$scope_contract" "$(scope_section "$HEPHAESTUS_ROOT/.ai/$path.md")"
done
assert_contains "explicit stacked base has priority" "$scope_contract" 'explicit `--base` (stacked work), the PR base, or confirmed `origin/HEAD`, in that order'
assert_contains "unknown scope cannot auto-pass" "$scope_contract" 'scope incomplete and cannot PASS/auto-pass'
assert_contains "no last-commit fallback" "$scope_contract" 'never a guess or `HEAD~1`'
assert_contains "untracked contents are inspected" "$scope_contract" 'relevant untracked changes'
assert_contains "exclusions are accounted for" "$scope_contract" 'exclusions/reasons, and ambiguity'
assert_contains "unresolved relevance is incomplete" "$scope_contract" 'unresolved relevance makes scope incomplete'
assert_contains "base preserved on refresh" "$scope_contract" 'Retain the base across commits'

begin_test "callers propagate scope into gates and acceptance checks"
critique=$(cat "$HEPHAESTUS_ROOT/.ai/workflows/critique.md")
testing=$(cat "$HEPHAESTUS_ROOT/.ai/workflows/test-issue.md")
starting=$(cat "$HEPHAESTUS_ROOT/.ai/workflows/start-issue.md")
shipping=$(cat "$HEPHAESTUS_ROOT/.ai/workflows/ship.md")
assert_contains "clean code review is explicit" "$critique" 'Code Critique** even on a clean checkout'
assert_contains "empty scope cannot auto-pass" "$critique" 'only if scope is complete and nonempty'
assert_contains "reviewer receives all layers" "$critique" 'Pass the recorded Scope and all change layers to each reviewer'
assert_contains "tester receives all layers" "$testing" 'Pass the recorded Scope and all change layers to each tester'
assert_contains "ACs use same scope" "$testing" 'against every included change layer in that same scope'
assert_contains "start records before committing" "$starting" 'Resolve the task change scope below before implementation'
assert_contains "start passes to tests" "$starting" 'Refresh and pass the recorded Scope to `/test-issue <#>`'
assert_contains "ship explicitly reviews committed work" "$shipping" 'explicitly in Code Critique mode, including on a clean branch'
assert_contains "ship honors stacked PR destination" "$shipping" '--base "<resolved-base-branch>"'
assert_contains "post-gate edits refresh verification" "$shipping" 'repeat affected critique and test gates before pushing'

# This fixture is deliberately independent of the real checkout and user config.
scope_tmp=$(mktemp -d "${TMPDIR:-/tmp}/heph-scope-XXXXXX")
trap 'rm -rf "$scope_tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Scope GIT_AUTHOR_EMAIL=scope@example.test
export GIT_COMMITTER_NAME=Scope GIT_COMMITTER_EMAIL=scope@example.test

git init -q "$scope_tmp/repo" || exit 1
cd "$scope_tmp/repo" || exit 1
git config commit.gpgsign false
git checkout -qb main
printf 'initial\n' > tracked.txt
printf 'remove later\n' > delete.txt
printf 'rename later\n' > old.txt
printf '*.ignored\n' > .gitignore
git add .
git commit -qm initial || exit 1
scope_base=main

resolve_scope() {
  scope_base_oid=$(git rev-parse --verify "${scope_base}^{commit}") &&
  scope_head=$(git rev-parse --verify HEAD) &&
  scope_merge_base=$(git merge-base --all "$scope_base_oid" "$scope_head") &&
  test "$(printf '%s\n' "$scope_merge_base" | wc -l | tr -d ' ')" = 1
}
inventory() {
  {
    git diff --no-renames --name-only -z "$scope_merge_base" "$scope_head" -- &&
    git diff --cached --no-renames --name-only -z "$scope_head" -- &&
    git diff --no-renames --name-only -z -- &&
    git ls-files --others --exclude-standard -z
  } > "$scope_tmp/inventory" || return 1
  while IFS= read -r -d '' path; do printf '%s\n' "$path"; done < "$scope_tmp/inventory" | LC_ALL=C sort -u
}

begin_test "staged-only work is visible"
printf 'staged\n' >> tracked.txt
git add tracked.txt
resolve_scope || exit 1
assert_eq "staged path included" 'tracked.txt' "$(inventory)"

begin_test "untracked task files are visible without staging user files"
git restore --source=HEAD --staged --worktree tracked.txt
printf 'task\n' > 'task file.txt'
printf 'cache\n' > cache.ignored
resolve_scope || exit 1
assert_eq "untracked spaced path included; ignored cache excluded" 'task file.txt' "$(inventory)"
assert_eq "inspection leaves file untracked" '?? "task file.txt"' "$(git status --short)"
rm 'task file.txt' cache.ignored

begin_test "clean branch includes multiple implementation commits"
git checkout -qb task
printf 'one\n' > first.txt
git add first.txt
git commit -qm first
printf 'two\n' > second.txt
git add second.txt
git commit -qm second
resolve_scope || exit 1
assert_eq "checkout is clean" '' "$(git status --porcelain)"
assert_eq "both implementation commits included" $'first.txt\nsecond.txt' "$(inventory)"

begin_test "merge-base excludes subsequent changes on the base branch"
git checkout -q main
printf 'upstream only\n' > upstream.txt
git add upstream.txt
git commit -qm upstream
git checkout -q task
resolve_scope || exit 1
assert_eq "diverged base adds no unrelated deletion" $'first.txt\nsecond.txt' "$(inventory)"
assert_not_contains "committed patch excludes upstream" "$(git diff "$scope_merge_base" "$scope_head" --)" 'upstream.txt'

begin_test "mixed layers preserve reversals, deletions, renames, and untracked paths"
printf 'staged\n' >> tracked.txt
git add tracked.txt
git show HEAD:tracked.txt > tracked.txt
rm delete.txt
git mv old.txt renamed.txt
printf 'task\n' > 'task file.txt'
resolve_scope || exit 1
assert_eq "every layer and both rename paths included" \
  $'delete.txt\nfirst.txt\nold.txt\nrenamed.txt\nsecond.txt\ntask file.txt\ntracked.txt' "$(inventory)"
assert_not_contains "net diff would miss reversed staged edit" "$(git diff HEAD --name-only)" 'tracked.txt'
assert_contains "staged patch remains reviewable" "$(git diff --cached "$scope_head" --)" '+staged'
assert_contains "unstaged reversal remains reviewable" "$(git diff --)" '-staged'

begin_test "explicit stacked base excludes parent work"
# A new fixture checkout keeps the mixed task's local files untouched.
git clone -q --no-hardlinks "$scope_tmp/repo" "$scope_tmp/stack" 2>/dev/null || exit 1
cd "$scope_tmp/stack" || exit 1
git config commit.gpgsign false
git checkout -qb child
printf 'child\n' > child.txt
git add child.txt
git commit -qm child
scope_base=origin/task
resolve_scope || exit 1
assert_eq "only child task is reviewed" 'child.txt' "$(inventory)"
pinned_base=$scope_base_oid
printf 'child two\n' > child-two.txt
git add child-two.txt
git commit -qm child-two
scope_base=$pinned_base
resolve_scope || exit 1
assert_eq "refresh retains whole child task" $'child-two.txt\nchild.txt' "$(inventory)"

begin_test "unresolvable or ambiguous bases cannot fall back to last commit"
scope_base=missing-parent
resolve_scope 2>/dev/null
assert_eq "missing explicit base fails" '128' "$?"
# Build unrelated history and a criss-cross DAG without merges or extra checkouts.
tree=$(git rev-parse 'HEAD^{tree}')
unrelated=$(printf 'unrelated\n' | git commit-tree "$tree")
scope_base=$unrelated
resolve_scope 2>/dev/null
assert_eq "unrelated base fails" '1' "$?"
root=$(git rev-list --max-parents=0 HEAD)
left=$(printf 'left\n' | git commit-tree "$tree" -p "$root")
right=$(printf 'right\n' | git commit-tree "$tree" -p "$root")
merge_left=$(printf 'merge left\n' | git commit-tree "$tree" -p "$left" -p "$right")
merge_right=$(printf 'merge right\n' | git commit-tree "$tree" -p "$right" -p "$left")
git checkout -q --detach "$merge_left"
scope_base=$merge_right
resolve_scope
assert_eq "multiple merge-bases fail" '1' "$?"

print_summary
