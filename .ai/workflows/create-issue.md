---
name: create-issue
requires: explorer
chains: none
---
Create a GitHub issue for: $ARGUMENTS

Follow these steps:

1. **Detect repo**: Run `git remote get-url origin` from the current directory to identify the target repo. If `--repo owner/repo` is provided in $ARGUMENTS, use that instead.

2. **Research**: Explore relevant files (use explorer subagent for broad searches) to understand the affected code area. This ensures accurate acceptance criteria.

3. **Draft the issue**:
   - **Title**: Short, imperative ("Fix token refresh race condition")
   - **Problem**: 2-3 sentences describing what's broken or missing and its impact
   - **Acceptance Criteria**: Bulleted checklist of testable conditions for "done"
   - **Technical notes**: Relevant file paths, functions, or architecture context from your research
   - **Labels**: determine appropriate labels (bug / enhancement / frontend / backend). Run `gh label list --repo <detected-repo>` first — only use labels that actually exist in the repo.

4. **Create it**: Run `gh issue create` with `--label` for each applicable label. Use a heredoc for the body:
   ```
   gh issue create --repo <detected-repo> --title "..." --label bug --label backend --body "$(cat <<'EOF'
   ...
   EOF
   )"
   ```
   Omit `--label` entirely if no matching labels exist in the repo.

5. Return the issue URL.

Do not create the issue without first doing the research step — vague issues waste time.

### Next steps
- Run `/start-issue <#>` to begin working on the issue
- Or run `/autopilot <#>` for fully autonomous implementation
