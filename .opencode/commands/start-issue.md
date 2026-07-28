---
description: "Start working on issue $ARGUMENTS. Run autonomously through the full plan-critique-implement cycle."
---
<!-- requires: coder, explorer -->
<!-- chains: /test-issue -->
<!-- generated from .ai/workflows/start-issue.md; do not edit directly -->

> **OpenCode:** start from the project root that contains `.opencode/`. Invoke nested workflows as slash commands (/test-issue) so their full templates load — do not paraphrase. Spawn role agents with the Task tool or @mentions.

Start working on issue $ARGUMENTS. Run autonomously through the full plan-critique-implement cycle.

## Autonomy Rules

- **Resolve ambiguity yourself.** If requirements are unclear, make reasonable assumptions based on codebase context, existing patterns, and the issue description. Document assumptions in commit messages and the eventual PR body. Do NOT stop to ask the user.
- **Recover before escalating.** If an approach fails, try a different one. Only stop if you've exhausted alternatives AND the failure involves irreversible risk.

## Phase 1: Context

1. **Detect repo**: Run `git remote get-url origin` to identify the target repo.

2. **Load context in parallel**:
   - **Read the issue**: `gh issue view <#> --repo <detected-repo>`
   - **Explore codebase** (@explorer agent(s)): Search for relevant files, understand current implementation
   - **Recent history**: `git log --oneline -10`
   - For complex issues, spawn multiple @explorer agents per subsystem

3. **Resolve ambiguities**: If the issue is underspecified:
   - Infer intent from related code, tests, and commit history
   - Choose the simplest interpretation that satisfies the acceptance criteria
   - Log each assumption as a bullet point for later inclusion in the PR body

4. **Create feature branch**: `git checkout -b issue-<number>-<short-description>` where `<short-description>` is a kebab-case summary derived from the issue title.

## Phase 2: Plan-Critique Loop

1. **Plan**: Break the issue into concrete steps with the todo tools. Identify independent tasks for parallel coders.
2. **Self-critique** (general critique mode): Evaluate the plan for logic, assumptions, completeness, trade-offs.
3. **Refine**: Update the plan to address weaknesses.
4. **Re-critique**: Evaluate the refined plan.
5. **Repeat** until verdict reaches **SOUND** (per CLAUDE.md retry limits).

If critique iterations are exhausted:
- **NEEDS REFINEMENT**: Proceed with the best version. The remaining concerns become "Known Limitations" documented in the PR.
- **RETHINK**: Proceed with the most defensible subset of the plan — implement what IS sound, skip what isn't. File a follow-up issue for the unsound parts.

## Phase 3: Implement

- Use parallel @coder Task invocations (serialize file edits — no worktree isolation) for independent changes
- Sequential implementation for dependent changes
- Commit each logical unit separately
- If a task is blocked: try one alternative approach. If still blocked, skip it with a TODO comment and continue.

## Phase 4: Test → `/test-issue <#>`

Run `/test-issue <#>` to execute project quality gates and verify acceptance criteria. The pre-ship code critique is `/ship`'s job — running it here would just duplicate the gate.

If tests fail:
- Analyze the root cause — don't blindly retry
- Go back to Phase 2 with failure context (per CLAUDE.md retry limits)
- If still failing after all retries (per CLAUDE.md): commit progress on the branch, create a draft PR (`--draft`) with `[FAILING]` prefix and failure analysis in the body, file a follow-up issue

Report completion: files changed, test results from `/test-issue`, any assumptions made. Ready for `/ship`.

Key constraints:
- If the project has multiple sub-repos (e.g., backend + frontend), treat each as a separate git repo and commit in the right one
