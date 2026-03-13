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

4. **Clean up** — delete the feature branch:
   - Get the PR's head branch name: `gh pr view <pr-number> --repo <detected-repo> --json headRefName -q '.headRefName'`
   - Switch to the default branch first (squash-merged branches cannot be deleted while checked out): `BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || git remote show origin 2>/dev/null | awk '/HEAD branch/{print $NF}' || echo master); git checkout "$BASE"`
   - Delete the feature branch: `git branch -D <branch>` (use `-D` because squash merges leave the branch tip unreachable from the target, so `-d` refuses to delete it)
   - Note: remote branch deletion depends on the repo's "automatically delete head branches" GitHub setting. If that setting is off, the remote branch remains — `git push origin --delete <branch> 2>/dev/null || true` to clean it up.
   - Pop stashes if any exist: `git stash list | grep -q "autopilot-pre" && git stash pop || true`

5. **Create breadcrumbs for remaining work**:
   - Check if there are any TODO/FIXME comments added during this session's implementation
   - Check if the PR body contains "Known Limitations" or "Assumptions Made"
   - If either exists: create follow-up issues for each significant item via `gh issue create`

6. **Print session summary** (CHANGELOG is updated by `/ship` — do not update it again here):
   - One-line: what shipped (feature/fix name, PR number, issue number)
   - Follow-up issues created (if any, with links)
   - Manual actions needed (if any, e.g., "PR awaiting manual merge")

If no issue number is provided in $ARGUMENTS, check recent PRs to infer which issue was just shipped.
