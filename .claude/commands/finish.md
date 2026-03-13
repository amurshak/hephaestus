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

4. **Clean up** — delete merged branches automatically:
   - `git branch --merged | grep -v main | grep -v master` to identify stale branches
   - Delete them: `git branch -d <branch>`
   - Pop any stashes created during this session (matching `autopilot-pre-*` pattern)

5. **Auto-update docs**: Update CHANGELOG.md with a new entry for the shipped work. Commit the doc changes.

6. **Create breadcrumbs for remaining work**:
   - Check if there are any TODO/FIXME comments added during this session's implementation
   - Check if the PR body contains "Known Limitations" or "Assumptions Made"
   - If either exists: create follow-up issues for each significant item via `gh issue create`

7. **Print session summary**:
   - One-line: what shipped (feature/fix name, PR number, issue number)
   - Follow-up issues created (if any, with links)
   - Manual actions needed (if any, e.g., "PR awaiting manual merge")

If no issue number is provided in $ARGUMENTS, check recent PRs to infer which issue was just shipped.
