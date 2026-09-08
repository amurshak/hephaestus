#!/usr/bin/env bash
# Extracted executable models for tests/test_finish_cleanup.sh.
capture_task_stash() {
  task_stash_record=
  local dirty stash_tree stash_gitdir stash_branch stash_head stash_oid
  dirty=$(git status --porcelain --untracked-files=all) || return
  [ -n "$dirty" ] || return 0
  stash_tree=$(pwd -P) || return
  stash_gitdir=$(git rev-parse --absolute-git-dir) || return
  stash_branch=$(git symbolic-ref -q HEAD) || { echo 'preserve dirty detached checkout'; return 1; }
  stash_head=$(git rev-parse HEAD) || return
  task_stash_record=$(mktemp "${TMPDIR:-/tmp}/heph-task-stash.XXXXXX") || return
  git stash push --include-untracked -m "$task_stash_record" || return
  stash_oid=$(git stash list --format='%H %gs' | awk -v marker=": $task_stash_record" \
    'substr($0, length($0)-length(marker)+1) == marker {print $1}') || return
  case "$stash_oid" in ''|*[!0-9a-f]*) echo 'stash identity uncertain; preserve and stop'; return 1 ;; esac
  printf '%s\n' "$stash_tree" "$stash_gitdir" "$stash_branch" "$stash_head" \
    "$stash_oid" captured > "$task_stash_record" || return
  printf 'task stash record: %s\n' "$task_stash_record"
}
return_to_task_stash_checkout() (
  preserve() { printf 'preserved task stash checkout: %s\n' "$*"; }
  [ -n "${task_stash_record:-}" ] || return
  {
    IFS= read -r stash_tree && IFS= read -r stash_gitdir &&
    IFS= read -r stash_branch && IFS= read -r stash_head &&
    IFS= read -r stash_oid && IFS= read -r stash_state
  } < "$task_stash_record" || { preserve 'incomplete record'; return 1; }
  [ "$stash_state" = captured ] || { preserve 'record needs inspection'; return 1; }
  [ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ] &&
    [ "$(git rev-parse --absolute-git-dir)" = "$stash_gitdir" ] || {
    preserve "original primary checkout required ($task_stash_record)"; return;
  }
  current_branch=$(git symbolic-ref -q HEAD) || {
    preserve 'detached or uncertain checkout'; return;
  }
  if [ "$current_branch" = "$stash_branch" ] && [ "$(git rev-parse HEAD)" = "$stash_head" ]; then
    return
  fi
  [ -n "${task_branch:-}" ] && [ "$current_branch" = "refs/heads/$task_branch" ] || {
    preserve 'unrelated checkout'; return;
  }
  dirty=$(git status --porcelain --untracked-files=all) || return
  [ -z "$dirty" ] || { preserve 'task checkout dirty'; return; }
  git check-ref-format "$stash_branch" || { preserve 'invalid original branch'; return 1; }
  [ "$(git rev-parse --verify "$stash_branch")" = "$stash_head" ] || {
    preserve 'original branch advanced'; return;
  }
  original_branch=${stash_branch#refs/heads/}
  worktrees=$(git worktree list --porcelain) || return
  ! grep -qxF "branch $stash_branch" <<< "$worktrees" || {
    preserve 'original branch occupied'; return;
  }
  git checkout "$original_branch" || {
    preserve "checkout failed ($task_stash_record)"; return 1;
  }
)
finish_task_branch() (
  preserve() { printf 'preserved task branch: %s\n' "$*"; }
  [ -n "${task_repo:-}" ] && [ -n "${task_origin:-}" ] && [ -n "${task_pr:-}" ] &&
    [ -n "${task_branch:-}" ] && [ -n "${task_head:-}" ] || {
    preserve 'missing task identity'; return;
  }
  git check-ref-format "refs/heads/$task_branch" || return
  git cat-file -e "$task_head^{commit}" || return
  [ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ] || {
    preserve 'linked worktree; left for reaping'; return;
  }
  verify_task() {
    payload=$(gh pr view "$task_pr" --repo "$task_repo" \
      --json number,state,mergedAt,headRefName,headRefOid,isCrossRepository,baseRefName \
      --jq '[.number,.state,.mergedAt,.headRefName,.headRefOid,.isCrossRepository,.baseRefName] | @tsv') || return 1
    IFS="$(printf '\t')" read -r pr state merged branch head fork base <<< "$payload"
    [ "$pr" = "$task_pr" ] && [ "$state" = MERGED ] &&
      [ -n "$merged" ] && [ "$merged" != null ] &&
      [ "$branch" = "$task_branch" ] && [ "$head" = "$task_head" ] &&
      [ "$fork" = false ] && [ -n "$base" ] || return 1
    case "$task_branch" in main|master|"$base") return 1 ;; esac
    default_ref=$(git symbolic-ref refs/remotes/origin/HEAD) || return 1
    [ "$default_ref" != "refs/remotes/origin/$task_branch" ] || return 1
    [ "$(git remote get-url origin)" = "$task_origin" ] &&
      [ "$(git remote get-url --push --all origin)" = "$task_origin" ] || return 1
    open_prs=$(gh pr list --repo "$task_repo" --state open --head "$task_branch" \
      --limit 1 --json number --jq 'length') || return 1
    [ "$open_prs" = 0 ] || return 1
    dirty=$(git status --porcelain --untracked-files=all) || return 1
    [ -z "$dirty" ] || return 1
    worktrees=$(git worktree list --porcelain) || return 1
    ! grep -qxF "branch refs/heads/$task_branch" <<< "$worktrees"
  }
  verify_task || { preserve 'identity changed, active, dirty, or uncertain'; return; }
  local_tip=$(git for-each-ref --format='%(objectname)' "refs/heads/$task_branch") || return
  remote_tip=$(git ls-remote --heads origin "refs/heads/$task_branch") || return
  remote_tip=${remote_tip%%[[:space:]]*}
  if { [ -n "$local_tip" ] && [ "$local_tip" != "$task_head" ]; } ||
     { [ -n "$remote_tip" ] && [ "$remote_tip" != "$task_head" ]; }; then
    preserve 'tip changed (reused or unpushed work)'; return
  fi
  if [ -n "$remote_tip" ]; then
    verify_task || { preserve 'remote deletion recheck failed'; return; }
    git push --force-with-lease="refs/heads/$task_branch:$task_head" \
      origin ":refs/heads/$task_branch" || { preserve 'remote deletion failed'; return 1; }
  fi
  git for-each-ref --format='preserved local task branch: %(refname:short)' \
    "refs/heads/$task_branch"
)
restore_task_stash() (
  [ -n "${task_stash_record:-}" ] || { echo 'no task stash recorded'; return; }
  {
    IFS= read -r stash_tree && IFS= read -r stash_gitdir &&
    IFS= read -r stash_branch && IFS= read -r stash_head &&
    IFS= read -r stash_oid && IFS= read -r stash_state
  } < "$task_stash_record" || { echo 'preserved stash: incomplete record'; return 1; }
  [ "$stash_state" != restored ] || { echo 'task stash already restored; recovery copy retained'; return; }
  [ "$stash_state" = captured ] || { echo 'preserved stash: prior apply needs inspection'; return 1; }
  [ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ] &&
    [ "$(pwd -P)" = "$stash_tree" ] &&
    [ "$(git rev-parse --absolute-git-dir)" = "$stash_gitdir" ] &&
    [ "$(git symbolic-ref -q HEAD)" = "$stash_branch" ] &&
    [ "$(git rev-parse HEAD)" = "$stash_head" ] || {
    echo "preserved stash $stash_oid: original primary checkout required ($task_stash_record)"; return;
  }
  dirty=$(git status --porcelain --untracked-files=all) || return
  [ -z "$dirty" ] || { echo "preserved stash $stash_oid: checkout dirty"; return; }
  stashes=$(git stash list --format=%H) || return
  grep -qxF "$stash_oid" <<< "$stashes" || { echo 'preserved stash: recorded OID missing'; return 1; }
  mark_stash() {
    printf '%s\n' "$stash_tree" "$stash_gitdir" "$stash_branch" "$stash_head" \
      "$stash_oid" "$1" > "$task_stash_record"
  }
  mark_stash applying || return
  if git stash apply --index "$stash_oid"; then
    mark_stash restored || return
    echo "restored task stash $stash_oid; recovery copy retained"
  else
    echo "task stash $stash_oid restoration failed; resolve without retry/reset ($task_stash_record)" >&2
    return 1
  fi
)
