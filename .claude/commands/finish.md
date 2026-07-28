<!-- requires: none -->
<!-- chains: /update-docs -->
<!-- generated from .ai/workflows/finish.md; do not edit directly -->

Finish and close issue $ARGUMENTS. Run autonomously.

Steps:

1. **Detect repo**: Run `git remote get-url origin` from current directory.

2. **Load PR state once, then branch deterministically**:
   - Find the PR for the issue (or use the explicit PR number if provided). If no PR exists, stop finish and run `/ship <#>` first.
   - Read one state payload before cleanup: `gh pr view <pr-number> --repo <detected-repo> --json state,mergedAt,mergeStateStatus,autoMergeRequest,headRefName,headRefOid,baseRefOid,closingIssuesReferences`
   - Branch from that payload:
     - `state=MERGED` and `mergedAt != null` → proceed with issue close, branch cleanup, breadcrumbs, retrospective, docs check, and summary.
     - `state=OPEN`, `mergeStateStatus=CLEAN`, and `autoMergeRequest != null` → log `auto-merge pending for PR #N`; proceed with cleanup-as-far-as-possible, but do not close the issue and do not delete or sweep this PR's branch.
     - `state=OPEN` and `autoMergeRequest = null` → log `manual merge needed for PR #N`; proceed with cleanup-as-far-as-possible, but do not close the issue and do not delete or sweep this PR's branch.
     - `state=CLOSED` and `mergedAt = null` → abort finish with `PR #N closed without merge`; do not close the issue, delete branches, run `/update-docs`, or file a shipped retrospective.
   - If cleanup later needs `headRefName`, re-read the same PR field immediately before deletion and use the latest value. If it changed since the first payload, log `PR #N head branch changed during finish: <old> -> <new>` and use the latest value.

3. **Close the issue**:
   - Derive the shipped issue from `closingIssuesReferences`; if it disagrees with `$ARGUMENTS`, use the PR's closing issue and log `using PR closing issue #M instead of requested #N`. If the PR closes no issue and none was provided, skip this step.
   - Check issue state first: `gh issue view <resolved-issue> --repo <detected-repo> --json state`.
   - If already closed, log `issue #N already closed by PR #M` and continue.
   - If open and PR state is merged, close it:
     ```
     gh issue close <resolved-issue> --repo <detected-repo> --comment "Shipped in PR #<pr-number>."
     ```
   - If PR state is not merged, skip issue close and include the pending/manual-merge reason in the session summary.

4. **Clean up branches** — sweep aggressively; GitHub's auto-delete only catches branches merged *after* the setting was enabled, so debt accumulates without an active sweep:
   - Switch off the merged branch (squash-merged branches can't be deleted while checked out): `BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo master); git checkout "$BASE"`
   - Delete the PR's local branch only when PR state is merged (idempotent — `/finish` may re-run): `BR=$(gh pr view <pr-number> --repo <detected-repo> --json headRefName -q '.headRefName'); git show-ref --verify --quiet "refs/heads/$BR" && git branch -D "$BR"` (use `-D` — squash merges leave the tip unreachable, so `-d` refuses)
   - Delete remote branches for *all* merged PRs (handles this PR plus any stranded by prior runs, auto-merge timing, or pre-setting merges):
     ```
     merged=$(gh pr list --state merged --limit 200 --repo <detected-repo> --json headRefName --jq '.[].headRefName' | sort -u)
     remote=$(git ls-remote --heads origin | awk '{print $2}' | sed 's|refs/heads/||' | grep -Ev '^(master|main)$' | sort -u)
     stale=$(comm -12 <(echo "$merged") <(echo "$remote"))
     [ -n "$stale" ] && git push origin --delete $stale
     ```
     Safe because the intersection requires a remote branch *and* a merged PR with that headRef — but if branch names get reused (rare), live work could match. For an open PR state, exclude the current PR's `headRefName` from `stale` before pushing deletes. Raise `--limit 200` if your unswept debt is older than the last 200 PRs. On push failure: print the error and continue to step 5; do **not** swallow with `|| true`, and do **not** abort the finish flow.
   - Prune local refs and pop session stash: `git fetch --prune origin; git stash list | grep -q "autopilot-pre" && git stash pop || true`

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
   - Build the required docs set from the changed files. These are the defaults; a project may override them with its own trigger list in a "Docs Requirements" section of its CLAUDE.md:
     - `CHANGELOG.md` is required for every PR, no exceptions.
     - `README.md` is required when the PR touches user-facing entry points — installers, CLI scripts, or command definitions (in this repo: `install.sh`, `update.sh`, `uninstall.sh`, `.claude/commands/*.md`).
     - `CLAUDE.md` is required when the PR changes conventions or capabilities the agent relies on — agent or command definitions (in this repo: `.claude/agents/*.md`, `.claude/commands/*.md`).
   - If every required doc file is present in the PR diff, skip `/update-docs` and log `skipped /update-docs: docs updated in PR #N (auto-detected)` in the session summary.
   - If any required doc file is missing, run `/update-docs` and log `ran /update-docs: missing <files> in PR #N (auto-detected)` in the session summary.
   - The skip/run decision must be deterministic from `git diff "$BASE_SHA..$HEAD_SHA" --name-only`; no prose assessment like "docs surface covered" is sufficient.

8. **Print session summary** (CHANGELOG is updated by `/ship` and re-checked by `/update-docs` — do not update it again here):
   - One-line: what shipped (feature/fix name, PR number, issue number)
   - Follow-up issues created (if any, with links)
   - Manual actions needed (if any, e.g., "PR awaiting manual merge")

If no issue number is provided in $ARGUMENTS, check recent PRs to infer which issue was just shipped.

### Next steps
- Run `/orient` to see what to work on next
- Run `/start-issue <#>` to begin a specific issue
- Run `/create-issue` to plan new work
