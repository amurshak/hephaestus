---
name: finish
requires: none
chains: /update-docs
---
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

4. **Clean up only task-owned resources** — no repository-wide branch sweep. Use the identity retained in step 2; never infer ownership from historical merged PR names. Failed queries or checks preserve resources and must be reported; cleanup failure does not abort breadcrumbs, docs, or the summary.
   - Delete only the task's remote branch when its tip still equals the merged PR head. Preserve dirty checkouts, unpushed/advanced or reused branches, open PR heads, fork heads, base/default branches, and ambiguous ownership. Remote deletion uses an explicit OID lease, so a concurrent advance is rejected. Preserve the local task branch for `/worktrees cleanup`: Git has no operation that atomically verifies both its expected OID and worktree occupancy, so direct local deletion can race another checkout.
   - **Linked worktree** — leave the branch and worktree in place and log `left worktree <path> on <branch> for reaping`. Never self-remove: `git worktree remove .` deletes this session's cwd. A primary session can reap it via `/worktrees cleanup`; finish does not remove any worktree. If another session may check out the branch during cleanup and exclusive ownership cannot be established, defer deletion as well.

   - **Return to the stash checkout** — before branch cleanup, a task with a stash record must move from its clean task branch back to the recorded original branch and HEAD. Validate the immutable record, primary-checkout context, unchanged original branch, and worktree occupancy; Git performs the final occupancy check during checkout. If any check fails, preserve the stash and task branch and report the record; do not switch from an unrelated checkout.

   - **Restore the exact task stash** — after the guarded return above, use only the `task_stash_record` captured by this task's autopilot preflight, never a message search or the top stash. Missing identity or a different checkout/branch/HEAD means leave it and report the record path. Restore only in the original clean primary checkout; linked worktrees defer restoration. Apply by immutable OID with staged state, retain the stash as a recovery copy, and mark the record before attempting restoration so a conflict or interrupted apply cannot be retried blindly. Report conflicts visibly, preserve the index/worktree and stash, and require resolution before any further implementation. Never reset/clean to force restoration or drop/pop a moving stash index.

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
