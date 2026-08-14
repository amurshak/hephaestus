---
name: create-issue
description: "Create a GitHub issue for: <argument>"
platforms: [linux, macos, windows]
metadata:
  hermes:
    category: hephaestus
    tags: [hephaestus, delivery, create-issue]
    requires_toolsets: [terminal]
    related_skills: []
---
<!-- requires: explorer -->
<!-- chains: none -->
<!-- generated from .ai/workflows/create-issue.md; do not edit directly -->

> **Hermes:** this skill is the `/create-issue` adapter.
> Where a step below names a role (explorer), you **must** call `delegate_task` for it rather than doing that step yourself — measured: orchestrators otherwise inline the whole workflow and never delegate. Each role's toolsets, cap and prompt are in `.hermes/agents/<role>.md`. A delegate inherits **none** of your conversation, and the cwd it does inherit is frozen at session **launch** — confidently stale if you work in a worktree — so give `context` absolute paths plus every constraint and prior finding it needs. Delegates get no per-child worktree, so parallel ones share one working tree: serialize file-modifying work.

> Hermes does not substitute `$ARGUMENTS` — read it as the arguments given in the user's request.

Create a GitHub issue for: $ARGUMENTS

Follow these steps:

1. **Detect repo**: Run `git remote get-url origin` from the current directory to identify the target repo. If `--repo owner/repo` is provided in $ARGUMENTS, use that instead.

2. **Research**: Explore relevant files (use explorer delegate for broad searches) to understand the affected code area. This ensures accurate acceptance criteria.

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
