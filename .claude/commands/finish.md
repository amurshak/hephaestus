Finish and close issue $ARGUMENTS. Run autonomously.

Steps:

1. **Detect repo**: Run `git remote get-url origin` from current directory.

2. **Verify the PR is merged**:
   - Run `gh pr list --state merged --repo <detected-repo>` and look for the relevant PR
   - If not merged, warn the user and stop — don't close an issue for unmerged work

3. **Close the issue**:
   ```
   gh issue close <#> --repo <detected-repo> --comment "Shipped in PR #<pr-number>."
   ```

4. **Clean up** — delete merged branches automatically:
   - `git branch --merged | grep -v main | grep -v master` to identify stale branches
   - Delete them: `git branch -d <branch>`

5. **Auto-update docs**: Update CHANGELOG.md with a new entry for the shipped work. Commit the doc changes.

6. **Print a one-line summary** of what shipped: feature/fix name, PR number, issue number.

If no issue number is provided in $ARGUMENTS, check recent PRs to infer which issue was just shipped.
