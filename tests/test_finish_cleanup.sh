#!/usr/bin/env bash
# Exercise cleanup safeguards with real Git operations in tiny repositories.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/heph-cleanup-tests.XXXXXX")
trap 'cd "$HEPHAESTUS_ROOT"; rm -rf "$TEST_ROOT"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TEST_ROOT/gitconfig"
git config --global user.name 'Cleanup Test'
git config --global user.email cleanup@example.invalid
git config --global init.defaultBranch main
REAL_GIT=$(command -v git)

# The workflow is prose, so this executable model drives real Git operations;
# contract assertions keep its guards aligned with the shipped instructions.
source "$SCRIPT_DIR/fixtures/finish_cleanup_recipes.sh"
finish_md=$(cat "$HEPHAESTUS_ROOT/.ai/workflows/finish.md")
autopilot_md=$(cat "$HEPHAESTUS_ROOT/.ai/workflows/autopilot.md")

begin_test 'Workflow and executable cleanup model share the safety contract'
assert_contains 'finish removes the historical sweep' "$finish_md" 'no repository-wide branch sweep'
assert_contains 'finish pins PR identity' "$finish_md" 'task_repo`, `task_pr`, `task_branch`, and `task_head`'
assert_contains 'finish requires exact tips' "$finish_md" 'tip still equals the merged PR head'
assert_contains 'finish uses an OID lease' "$finish_md" 'explicit OID lease'
assert_contains 'finish preserves local branch' "$finish_md" 'Preserve the local task branch for `/worktrees cleanup`'
assert_contains 'finish restores immutable stash OID' "$finish_md" 'Apply by immutable OID with staged state'
assert_contains 'finish prevents blind conflict retry' "$finish_md" 'cannot be retried blindly'
assert_contains 'autopilot captures untracked work' "$autopilot_md" '`git stash push --include-untracked'
assert_contains 'autopilot retains exact record' "$autopilot_md" 'retain its path for `/finish` and wind-down'
assert_contains 'autopilot stops on uncertain capture' "$autopilot_md" 'Capture failure stops implementation'

fixture_number=0
fresh() {
  fixture_number=$((fixture_number + 1))
  fixture="$TEST_ROOT/$fixture_number"
  mkdir -p "$fixture/tmp"
  export TMPDIR="$fixture/tmp"
  git init --bare -q "$fixture/remote.git"
  git init -q "$fixture/repo"
  cd "$fixture/repo"
  printf 'base\n' > tracked
  printf 'collision\n' > .gitignore
  git add tracked .gitignore
  git commit -qm base
  git remote add origin "$fixture/remote.git"
  git push -q -u origin main
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  task_repo=amurshak/hephaestus task_pr=221 task_branch=issue-221
  task_origin="$fixture/remote.git"
  task_head=$(git rev-parse HEAD)
  git branch "$task_branch"
  git push -q origin "$task_branch"
  payload=$(printf '%s\tMERGED\t2026-01-01\t%s\t%s\tfalse\tmain' "$task_pr" "$task_branch" "$task_head")
  open_count=0 query_failure=0
  unset task_stash_record
}
gh() {
  [ "$query_failure" = 0 ] || return 1
  case "$1 $2" in
    'pr view') printf '%s\n' "$payload" ;;
    'pr list') printf '%s\n' "$open_count" ;;
    *) return 1 ;;
  esac
}
local_tip() { git for-each-ref --format='%(objectname)' "refs/heads/$task_branch"; }
remote_tip() { git --git-dir="$fixture/remote.git" for-each-ref --format='%(objectname)' "refs/heads/$task_branch"; }
preserved() {
  finish_task_branch > "$fixture/output" 2>&1
  assert_eq "$1: local retained" "$task_head" "$(local_tip)"
  assert_eq "$1: remote retained" "$task_head" "$(remote_tip)"
}
new_commit() { printf 'advance\n' | git commit-tree "$task_head^{tree}" -p "$task_head"; }

begin_test 'Only the resolved task branch is deleted, and cleanup is repeatable'
fresh
git branch historical
git push -q origin historical
finish_task_branch > "$fixture/output" 2>&1
assert_eq 'task local branch retained for safe reaping' "$task_head" "$(local_tip)"
assert_eq 'task remote branch removed' '' "$(remote_tip)"
assert_eq 'historical local branch retained' "$task_head" "$(git rev-parse historical)"
assert_eq 'historical remote branch retained' "$task_head" "$(git --git-dir="$fixture/remote.git" rev-parse historical)"
finish_task_branch > "$fixture/output" 2>&1
assert_eq 'repeat cleanup leaves checkout unchanged' "$task_head" "$(git rev-parse HEAD)"

begin_test 'Dirty, occupied, and uncertain branches survive'
for scenario in tracked untracked current other_worktree linked missing changed_pr changed_head changed_branch open closed fork open_head query_failure origin_changed pushurl_changed; do
  fresh
  case "$scenario" in
    tracked) printf 'user edit\n' >> tracked ;;
    untracked) printf 'user file\n' > untracked ;;
    current) git checkout -q "$task_branch" ;;
    other_worktree) git worktree add -q "$fixture/other" "$task_branch" ;;
    linked) git worktree add -q "$fixture/other" "$task_branch"; cd "$fixture/other" ;;
    missing) task_repo= ;;
    changed_pr) payload=${payload/221/222} ;;
    changed_head) payload=${payload/$task_head/0000000000000000000000000000000000000000} ;;
    changed_branch) payload=${payload/issue-221/issue-222} ;;
    open) payload=${payload/MERGED/OPEN} ;;
    closed) payload=${payload/MERGED/CLOSED} ;;
    fork) payload=${payload/false/true} ;;
    open_head) open_count=1 ;;
    query_failure) query_failure=1 ;;
    origin_changed) task_origin="$fixture/different.git" ;;
    pushurl_changed) git remote set-url --push origin "$fixture/./remote.git" ;;
  esac
  preserved "$scenario"
  case "$scenario" in
    tracked) assert_contains 'tracked edit retained' "$(cat tracked)" 'user edit' ;;
    untracked) assert_eq 'untracked contents retained' 'user file' "$(cat untracked)" ;;
    linked) assert_dir_exists 'linked checkout remains' "$fixture/other" ;;
  esac
done

begin_test 'PR identity is revalidated before each deletion'
fresh
printf '0\n' > "$fixture/queries"
gh() {
  case "$1 $2" in
    'pr view')
      calls=$(cat "$fixture/queries")
      calls=$((calls + 1))
      printf '%s\n' "$calls" > "$fixture/queries"
      if [ "$calls" -ge 2 ]; then printf '%s\n' "${payload/MERGED/OPEN}"
      else printf '%s\n' "$payload"; fi ;;
    'pr list') printf '0\n' ;;
    *) return 1 ;;
  esac
}
finish_task_branch > "$fixture/output" 2>&1
assert_eq 'revalidation preserves local branch' "$task_head" "$(local_tip)"
assert_eq 'revalidation preserves remote before push' "$task_head" "$(remote_tip)"
gh() {
  [ "$query_failure" = 0 ] || return 1
  case "$1 $2" in
    'pr view') printf '%s\n' "$payload" ;;
    'pr list') printf '%s\n' "$open_count" ;;
    *) return 1 ;;
  esac
}

begin_test 'Advanced and reused branch names preserve unpublished work'
for side in local remote; do
  fresh
  advanced=$(new_commit)
  if [ "$side" = local ]; then git update-ref "refs/heads/$task_branch" "$advanced"
  else git --git-dir="$fixture/remote.git" fetch -q "$fixture/repo" "$advanced"; git --git-dir="$fixture/remote.git" update-ref "refs/heads/$task_branch" "$advanced"; fi
  finish_task_branch > "$fixture/output" 2>&1
  if [ "$side" = local ]; then
    assert_eq 'unpushed local advance retained' "$advanced" "$(local_tip)"
    assert_eq 'remote preserved when local advanced' "$task_head" "$(remote_tip)"
  else
    assert_eq 'reused remote advance retained' "$advanced" "$(remote_tip)"
    assert_eq 'local preserved when remote advanced' "$task_head" "$(local_tip)"
  fi
done

begin_test 'Concurrent remote advances reject the deletion lease'
fresh
advanced=$(new_commit)
"$REAL_GIT" --git-dir="$fixture/remote.git" fetch -q "$fixture/repo" "$advanced"
git() {
  if [ "${1:-}" = push ]; then
    "$REAL_GIT" --git-dir="$fixture/remote.git" update-ref "refs/heads/$task_branch" "$advanced"
  fi
  "$REAL_GIT" "$@"
}
result=0
finish_task_branch > "$fixture/output" 2>&1 || result=$?
unset -f git
assert_exit_code 'remote race reports failure' 1 "$result"
assert_eq 'remote lease preserves concurrent advance' "$advanced" "$(remote_tip)"
assert_eq 'remote failure preserves local branch' "$task_head" "$(local_tip)"
git worktree add -q "$fixture/late-worktree" "$task_branch"
assert_dir_exists 'retained local branch remains safe for a later checkout' "$fixture/late-worktree"

begin_test 'Normal autopilot lifecycle returns to the original checkout and restores work'
fresh
printf 'task user work\n' > tracked
printf 'task untracked\n' > task-file
capture_task_stash > "$fixture/capture-output"
owned=$(sed -n '5p' "$task_stash_record")
git checkout -q "$task_branch"
return_to_task_stash_checkout > "$fixture/output" 2>&1
assert_eq 'returns to original branch' refs/heads/main "$(git symbolic-ref HEAD)"
assert_eq 'returns to original HEAD' "$task_head" "$(git rev-parse HEAD)"
finish_task_branch >> "$fixture/output" 2>&1
assert_eq 'normal cleanup removes exact remote task branch' '' "$(remote_tip)"
assert_eq 'normal cleanup retains local task branch for reaping' "$task_head" "$(local_tip)"
restore_task_stash >> "$fixture/output" 2>&1
assert_eq 'normal lifecycle restores tracked work' 'task user work' "$(cat tracked)"
assert_eq 'normal lifecycle restores untracked work' 'task untracked' "$(cat task-file)"
assert_contains 'normal lifecycle retains exact recovery stash' "$(git stash list --format=%H)" "$owned"

begin_test 'Capture and restore exact stash with staged and untracked work'
fresh
printf 'older\n' > tracked
git stash push -qm older
older=$(git rev-parse refs/stash)
printf 'staged\n' > tracked
git add tracked
printf 'unstaged\n' >> tracked
printf 'task untracked\n' > task-file
# Insert an unrelated stash after push but before capture reads the stash list.
git() {
  "$REAL_GIT" "$@" || return
  if [ "${1:-} ${2:-}" = 'stash push' ]; then
    printf 'newer\n' > tracked
    "$REAL_GIT" stash push -qm newer || return
  fi
}
capture_task_stash > "$fixture/capture-output"
unset -f git
record=$task_stash_record
owned=$(sed -n '5p' "$record")
assert_eq 'capture cleans checkout' '' "$(git status --porcelain)"
newer=$(git rev-parse refs/stash)
stashes_before=$(git stash list --format=%H)
restore_task_stash > "$fixture/output" 2>&1
assert_eq 'restored staged content' staged "$(git show :tracked)"
assert_eq 'restored unstaged content' "$(printf 'staged\nunstaged')" "$(cat tracked)"
assert_eq 'restored untracked file' 'task untracked' "$(cat task-file)"
assert_eq 'all stash recovery entries retained in order' "$stashes_before" "$(git stash list --format=%H)"
assert_contains 'older stash remains' "$stashes_before" "$older"
assert_contains 'task stash identified below unrelated top' "$stashes_before" "$owned"
assert_eq 'newer stash remains top' "$newer" "$(git rev-parse refs/stash)"
assert_eq 'record marked restored' restored "$(sed -n '6p' "$record")"
before=$(git status --porcelain)
restore_task_stash > "$fixture/output" 2>&1
assert_eq 'repeat restore does not change index or worktree' "$before" "$(git status --porcelain)"

begin_test 'Missing identity or checkout changes defer stash restoration'
for scenario in absent checkout head branch dirty; do
  fresh
  printf 'task change\n' > tracked
  capture_task_stash > "$fixture/capture-output"
  record=$task_stash_record
  stashes_before=$(git stash list --format=%H)
  case "$scenario" in
    absent) unset task_stash_record ;;
    checkout) git worktree add -q --detach "$fixture/other" HEAD; cd "$fixture/other" ;;
    head) git commit --allow-empty -qm advance ;;
    branch) git checkout -q "$task_branch" ;;
    dirty) printf 'other change\n' > tracked ;;
  esac
  before=$(git status --porcelain)
  restore_task_stash > "$fixture/output" 2>&1
  assert_eq "$scenario: stash entries untouched" "$stashes_before" "$(git stash list --format=%H)"
  assert_eq "$scenario: index and worktree untouched" "$before" "$(git status --porcelain)"
  assert_eq "$scenario: record stays captured" captured "$(sed -n '6p' "$record")"
done

begin_test 'Real stash apply failure retains recovery and prevents blind retry'
fresh
# Force an ignored file into the stash as an untracked file, then recreate it
# ignored. Status stays clean but Git refuses to overwrite it during apply.
printf 'stashed file\n' > collision
# The tracked ignore rule is temporarily absent for capture, then restored by
# stash itself; HEAD remains unchanged throughout this scenario.
printf '' > .gitignore
capture_task_stash > "$fixture/capture-output"
printf 'existing ignored user file\n' > collision
assert_eq 'ignored collision keeps checkout clean' '' "$(git status --porcelain)"
stashes_before=$(git stash list --format=%H)
result=0
restore_task_stash > "$fixture/output" 2>&1 || result=$?
assert_exit_code 'real apply failure is visible' 1 "$result"
assert_eq 'failed apply retains HEAD' "$task_head" "$(git rev-parse HEAD)"
assert_eq 'failed apply preserves collision contents' 'existing ignored user file' "$(cat collision)"
assert_eq 'failed apply retains recovery stash' "$stashes_before" "$(git stash list --format=%H)"
assert_eq 'failed apply leaves applying marker' applying "$(sed -n '6p' "$task_stash_record")"
before=$(git status --porcelain)
result=0
restore_task_stash > "$fixture/output" 2>&1 || result=$?
assert_exit_code 'blind retry is rejected' 1 "$result"
assert_eq 'retry leaves partial restoration untouched' "$before" "$(git status --porcelain)"
assert_contains 'retry explains inspection required' "$(cat "$fixture/output")" 'prior apply needs inspection'

print_summary
