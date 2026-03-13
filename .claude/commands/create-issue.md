Create a GitHub issue for: $ARGUMENTS

Follow these steps:

1. **Detect repo**: Run `git remote get-url origin` from the current directory to identify the target repo. If `--repo owner/repo` is provided in $ARGUMENTS, use that instead.

2. **Research**: Explore relevant files (use explorer subagent for broad searches) to understand the affected code area. This ensures accurate acceptance criteria.

3. **Draft the issue**:
   - **Title**: Short, imperative ("Fix token refresh race condition")
   - **Problem**: 2-3 sentences describing what's broken or missing and its impact
   - **Acceptance Criteria**: Bulleted checklist of testable conditions for "done"
   - **Technical notes**: Relevant file paths, functions, or architecture context from your research
   - **Labels**: suggest appropriate labels (bug / enhancement / frontend / backend)

4. **Create it**: Run `gh issue create --repo <detected-repo> --title "..." --body "..."` using a heredoc for the body

5. Return the issue URL.

Do not create the issue without first doing the research step — vague issues waste time.
