<!-- requires: none -->
Finish and close issue $ARGUMENTS. Run autonomously.

Steps:

1. **Detect repo**: Run `git remote get-url origin` from current directory.

2. **Verify the PR is merged**:
   - Run `gh pr list --state merged --repo <detected-repo>` and look for the relevant PR
   - If not merged yet but PR exists: check if auto-merge is enabled. If yes, note it in the summary and proceed with cleanup. If no, note that manual merge is needed and proceed with what can be done.
   - If no PR exists at all: this is unexpected — create one via `/ship` flow first, then continue.

3. **Close the issue**:
   ```
   gh issue close <#> --repo <detected-repo> --comment "Shipped in PR #<pr-number>."
   ```

4. **Clean up branches** — sweep aggressively; GitHub's auto-delete only catches branches merged *after* the setting was enabled, so debt accumulates without an active sweep:
   - Switch off the merged branch (squash-merged branches can't be deleted while checked out): `BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo master); git checkout "$BASE"`
   - Delete the PR's local branch (idempotent — `/finish` may re-run): `BR=$(gh pr view <pr-number> --repo <detected-repo> --json headRefName -q '.headRefName'); git show-ref --verify --quiet "refs/heads/$BR" && git branch -D "$BR"` (use `-D` — squash merges leave the tip unreachable, so `-d` refuses)
   - Delete remote branches for *all* merged PRs (handles this PR plus any stranded by prior runs, auto-merge timing, or pre-setting merges):
     ```
     merged=$(gh pr list --state merged --limit 200 --repo <detected-repo> --json headRefName --jq '.[].headRefName' | sort -u)
     remote=$(git ls-remote --heads origin | awk '{print $2}' | sed 's|refs/heads/||' | grep -Ev '^(master|main)$' | sort -u)
     stale=$(comm -12 <(echo "$merged") <(echo "$remote"))
     [ -n "$stale" ] && git push origin --delete $stale
     ```
     Safe because the intersection requires a remote branch *and* a merged PR with that headRef — but if branch names get reused (rare), live work could match. Raise `--limit 200` if your unswept debt is older than the last 200 PRs. On push failure: print the error and continue to step 5; do **not** swallow with `|| true`, and do **not** abort the finish flow.
   - Prune local refs and pop session stash: `git fetch --prune origin; git stash list | grep -q "autopilot-pre" && git stash pop || true`

5. **Create breadcrumbs for remaining work**:
   - Check if there are any TODO/FIXME comments added during this session's implementation
   - Check if the PR body contains "Known Limitations" or "Assumptions Made"
   - If either exists: create follow-up issues for each significant item via `gh issue create`

6. **Retrospective** — briefly capture what the pipeline learned:
   - What failed during this issue's pipeline (critique rejections, test failures, blocked tasks)?
   - What fixed it (alternative approach, simplified scope, skipped non-critical)?
   - Any reusable insight (e.g., "integration tests needed before refactoring auth module")?
   - Add as a comment on the closed issue: `gh issue comment <#> --repo <detected-repo> --body "<retrospective>"`
   - Keep it short — 2-4 sentences. Skip if the pipeline ran cleanly with no failures.

7. **Print session summary** (CHANGELOG is updated by `/ship` — do not update it again here):
   - One-line: what shipped (feature/fix name, PR number, issue number)
   - Follow-up issues created (if any, with links)
   - Manual actions needed (if any, e.g., "PR awaiting manual merge")

If no issue number is provided in $ARGUMENTS, check recent PRs to infer which issue was just shipped.

### Next steps
- Run `/orient` to see what to work on next
- Run `/start-issue <#>` to begin a specific issue
- Run `/create-issue` to plan new work
