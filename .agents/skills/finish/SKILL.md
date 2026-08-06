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

4. **Clean up branches** — sweep aggressively; GitHub's auto-delete only catches branches merged *after* the setting was enabled, so debt accumulates without an active sweep. Local cleanup depends on the checkout context, so resolve it first: `[ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ]` is the primary checkout; otherwise this session runs in a linked worktree.
   - **Primary checkout** — switch off the merged branch (squash-merged branches can't be deleted while checked out): `BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo master); git checkout "$BASE"`. Then delete the PR's local branch only when PR state is merged (idempotent — `/finish` may re-run): `BR=$(gh pr view <pr-number> --repo <detected-repo> --json headRefName -q '.headRefName'); git show-ref --verify --quiet "refs/heads/$BR" && git branch -D "$BR"` (use `-D` — squash merges leave the tip unreachable, so `-d` refuses)
   - **Linked worktree** — skip both, and never self-remove. `git checkout "$BASE"` fails (`already used by worktree`), `git branch -D` refuses the branch its worktree occupies, and `git worktree remove .` *succeeds* by deleting this session's cwd, killing the run before the retrospective and summary. Leave the branch and worktree in place and log `left worktree <path> on <branch> for reaping`; a primary session reaps it via `/worktrees cleanup`, which `/orient` chains.
   - Delete remote branches for *all* merged PRs (handles this PR plus any stranded by prior runs, auto-merge timing, or pre-setting merges):
     ```
     merged=$(gh pr list --state merged --limit 200 --repo <detected-repo> --json headRefName --jq '.[].headRefName' | sort -u)
     remote=$(git ls-remote --heads origin | awk '{print $2}' | sed 's|refs/heads/||' | grep -Ev '^(master|main)$' | sort -u)
     stale=$(comm -12 <(echo "$merged") <(echo "$remote"))
     [ -n "$stale" ] && git push origin --delete $stale
     ```
     Safe because the intersection requires a remote branch *and* a merged PR with that headRef — but if branch names get reused (rare), live work could match. For an open PR state, exclude the current PR's `headRefName` from `stale` before pushing deletes. Raise `--limit 200` if your unswept debt is older than the last 200 PRs. On push failure: print the error and continue to step 5; do **not** swallow with `|| true`, and do **not** abort the finish flow.
   - Prune local refs: `git fetch --prune origin`. Pop the session stash in the primary checkout only — the stash ref lives in the common git dir, so a worktree popping `autopilot-pre` would apply the primary session's changes into the wrong tree: `git stash list | grep -q "autopilot-pre" && git stash pop || true`

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
