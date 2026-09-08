---
name: finish
description: "Finish and close issue <argument>. Run autonomously. Use for /finish requests."
---
<!-- requires: none -->
<!-- chains: /update-docs -->
<!-- generated from .ai/workflows/finish.md; do not edit directly -->

> **Codex:** this skill is the `/finish` adapter. For chained workflows (/update-docs), invoke the matching generated skill (for example `heph:<workflow>`) when it is available; otherwise read and follow `.agents/skills/<workflow>/SKILL.md`. Use Codex role agents from `.codex/agents/` when the runtime exposes them; otherwise perform the work directly and keep the same structured output.

> Codex does not substitute `$ARGUMENTS` — read it as the arguments given in the user's request.

Finish and close issue $ARGUMENTS. Run autonomously.

Steps:

1. **Detect repo**: Run `git remote get-url origin` from current directory.

2. **Load PR state once, then branch deterministically**:
   - Find the PR for the issue (or use the explicit PR number if provided). If no PR exists, stop finish and run `/ship <#>` first.
   - Read one state payload before cleanup: `gh pr view <pr-number> --repo <detected-repo> --json state,mergedAt,mergeStateStatus,autoMergeRequest,headRefName,headRefOid,baseRefOid,closingIssuesReferences,number,isCrossRepository,baseRefName`
   - Branch from that payload:
     - `state=MERGED` and `mergedAt != null` → proceed with issue close, branch cleanup, breadcrumbs, retrospective, docs check, and summary.
     - `state=OPEN`, `mergeStateStatus=CLEAN`, and `autoMergeRequest != null` → log `auto-merge pending for PR #N`; proceed with cleanup-as-far-as-possible, but do not close the issue and do not delete this PR's branch.
     - `state=OPEN` and `autoMergeRequest = null` → log `manual merge needed for PR #N`; proceed with cleanup-as-far-as-possible, but do not close the issue and do not delete this PR's branch.
     - `state=CLOSED` and `mergedAt = null` → abort finish with `PR #N closed without merge`; do not close the issue, delete branches, run `/update-docs`, or file a shipped retrospective.
   - Retain the resolved repository, PR number, `headRefName`, and `headRefOid` as `task_repo`, `task_pr`, `task_branch`, and `task_head`; retain the origin URL from step 1 as `task_origin`. These identify the task, not a branch name found in historical PRs. Missing or ambiguous identity means preserve resources. Re-read PR identity before each deletion; if it changed, preserve the branch rather than adopting the new identity. Treat every other OPEN state as pending/manual merge too.

3. **Close the issue**:
   - Derive the shipped issue from `closingIssuesReferences`; if it disagrees with `$ARGUMENTS`, use the PR's closing issue and log `using PR closing issue #M instead of requested #N`. If the PR closes no issue and none was provided, skip this step.
   - Check issue state first: `gh issue view <resolved-issue> --repo <detected-repo> --json state`.
   - If already closed, log `issue #N already closed by PR #M` and continue.
   - If open and PR state is merged, close it:
     ```
     gh issue close <resolved-issue> --repo <detected-repo> --comment "Shipped in PR #<pr-number>."
     ```
   - If PR state is not merged, skip issue close and include the pending/manual-merge reason in the session summary.

4. **Clean up only task-owned resources** — no repository-wide branch sweep. Run the block below with the task identity retained in step 2. Never infer ownership from historical merged PR names. Failed queries or checks preserve resources and must be reported; cleanup failure does not abort breadcrumbs, docs, or the summary.
   - Delete only an unoccupied task branch whose tip still equals the merged PR head. Preserve dirty checkouts, unpushed/advanced or reused branches, open PR heads, fork heads, base/default branches, and ambiguous ownership. Do not switch checkouts to make deletion possible. Local deletion compares the old OID atomically; remote deletion uses an explicit OID lease, so a concurrent advance is rejected.
   - **Linked worktree** — leave the branch and worktree in place and log `left worktree <path> on <branch> for reaping`. Never self-remove: `git worktree remove .` deletes this session's cwd. A primary session can reap it via `/worktrees cleanup`; finish does not remove any worktree. If another session may check out the branch during cleanup and exclusive ownership cannot be established, defer deletion as well.

<!-- task-branch-cleanup -->
```bash
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
  if [ -n "$local_tip" ]; then
    verify_task || { preserve 'local deletion recheck failed'; return; }
    git update-ref -d "refs/heads/$task_branch" "$task_head" || {
      preserve 'local deletion failed'; return 1;
    }
  fi
)
finish_task_branch
```

   - **Restore the exact task stash** — use only the `task_stash_record` captured by this task's autopilot preflight, never a message search or the top stash. Missing identity or a different checkout/branch/HEAD means leave it and report the record path. Restore only in the original clean primary checkout; linked worktrees defer restoration. Apply by immutable OID with staged state, retain the stash as a recovery copy, and mark the record before attempting restoration so a conflict or interrupted apply cannot be retried blindly. Report conflicts visibly, preserve the index/worktree and stash, and require resolution before any further implementation. Never reset/clean to force restoration or drop/pop a moving stash index.

<!-- task-stash-restore -->
```bash
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
restore_task_stash
```

5. **Create breadcrumbs for remaining work**:
   - Check if there are any TODO/FIXME comments added during this session's implementation
   - Check if the PR body contains "Known Limitations" or "Assumptions Made"
   - If either exists: create follow-up issues for each significant item via `gh issue create`

6. **Retrospective** — briefly capture what the pipeline learned:
   - What failed during this issue's pipeline (critique rejections, test failures, blocked tasks)?
   - What fixed it (alternative approach, simplified scope, skipped non-critical)?
   - Any reusable insight (e.g., "integration tests needed before refactoring auth module")?
   - **Critic calibration**: check for post-merge corrections to this PR's files (`git log --oneline -20 -- <files>` since merge, plus open issues referencing them). If fixes landed for problems the pre-ship critique should have caught, add a line `Critique calibration: false-negative — <what was missed>`; if the critique blocked on something that proved fine, `false-positive — <what>`; otherwise `accurate`. Calibration lives in issue comments (repo-as-memory), searchable via `gh search issues "Critique calibration"`.
   - Add as a comment on the closed issue: `gh issue comment <#> --repo <detected-repo> --body "<retrospective>"`
   - Keep it short — 2-4 sentences plus the calibration line. Skip only if the pipeline ran cleanly AND no post-merge corrections exist.

7. **Update docs** — decide mechanically from the PR diff; do not use model judgment.
   - Determine the changed files: `BASE_SHA=$(gh pr view <pr-number> --repo <detected-repo> --json baseRefOid -q '.baseRefOid'); HEAD_SHA=$(gh pr view <pr-number> --repo <detected-repo> --json headRefOid -q '.headRefOid'); git diff "$BASE_SHA..$HEAD_SHA" --name-only`
   - Build the required docs set from the changed files. These are the defaults; a project may override them with its own trigger list in a "Docs Requirements" section of its CLAUDE.md, which wins whole — read it before applying any default:
     - A changelog record is required for every PR, no exceptions: a `changelog.d/*.md` fragment where that directory exists, otherwise `CHANGELOG.md`.
     - `README.md` is required when the PR touches user-facing entry points — installers, CLI scripts, or command definitions.
     - `CLAUDE.md` is required when the PR changes conventions or capabilities the agent relies on — agent or command definitions.
   - If every required doc file is present in the PR diff, skip `/update-docs` and log `skipped /update-docs: docs updated in PR #N (auto-detected)` in the session summary.
   - If any required doc file is missing, run `/update-docs` and log `ran /update-docs: missing <files> in PR #N (auto-detected)` in the session summary.
   - The skip/run decision must be deterministic from `git diff "$BASE_SHA..$HEAD_SHA" --name-only`; no prose assessment like "docs surface covered" is sufficient.

8. **Print session summary** (CHANGELOG is updated by `/ship` and re-checked by `/update-docs` — do not update it again here):
   - One-line: what shipped (feature/fix name, PR number, issue number)
   - Follow-up issues created (if any, with links)
   - Manual actions needed (if any, e.g., "PR awaiting manual merge")
   - When running in a linked worktree: the path and branch left for reaping, and that a primary session collects it. This is the end of the pipeline inside a worktree — do not chain further work.

If no issue number is provided in $ARGUMENTS, check recent PRs to infer which issue was just shipped.

### Next steps
- Run `/orient` to see what to work on next
- Run `/start-issue <#>` to begin a specific issue
- Run `/create-issue` to plan new work
