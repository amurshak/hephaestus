<!-- requires: coder, reviewer, tester, explorer -->
Start working on issue $ARGUMENTS. Run autonomously through the full plan-critique-implement cycle.

## Autonomy Rules

- **Resolve ambiguity yourself.** If requirements are unclear, make reasonable assumptions based on codebase context, existing patterns, and the issue description. Document assumptions in commit messages and the eventual PR body. Do NOT stop to ask the user.
- **Recover before escalating.** If an approach fails, try a different one. Only stop if you've exhausted alternatives AND the failure involves irreversible risk.

## Phase 1: Context

1. **Detect repo**: Run `git remote get-url origin` to identify the target repo.

2. **Load context in parallel**:
   - **Read the issue**: `gh issue view <#> --repo <detected-repo>`
   - **Explore codebase** (explorer subagent(s)): Search for relevant files, understand current implementation
   - **Recent history**: `git log --oneline -10`
   - For complex issues, spawn multiple explorer subagents per subsystem

3. **Resolve ambiguities**: If the issue is underspecified:
   - Infer intent from related code, tests, and commit history
   - Choose the simplest interpretation that satisfies the acceptance criteria
   - Log each assumption as a bullet point for later inclusion in the PR body

4. **Create feature branch**: `git checkout -b issue-<number>-<short-description>` where `<short-description>` is a kebab-case summary derived from the issue title.

## Phase 2: Plan-Critique Loop

1. **Plan**: Break the issue into concrete steps with TodoWrite. Identify independent tasks for parallel coders.
2. **Self-critique** (general critique mode): Evaluate the plan for logic, assumptions, completeness, trade-offs.
3. **Refine**: Update the plan to address weaknesses.
4. **Re-critique**: Evaluate the refined plan.
5. **Repeat** until verdict reaches **SOUND** (max 3 iterations).

If after 3 iterations:
- **NEEDS REFINEMENT**: Proceed with the best version. The remaining concerns become "Known Limitations" documented in the PR.
- **RETHINK**: Proceed with the most defensible subset of the plan — implement what IS sound, skip what isn't. File a follow-up issue for the unsound parts.

## Phase 3: Implement

- Use parallel coder subagents (in worktrees) for independent changes
- Sequential implementation for dependent changes
- Commit each logical unit separately
- If a task is blocked: try one alternative approach. If still blocked, skip it with a TODO comment and continue.

## Phase 4: Pre-ship critique

Launch reviewer subagent for code critique before running tests.

- **FAIL**: Fix blocking issues, re-critique (max 3 iterations). If still FAIL after 3: commit progress, create draft PR with `[BLOCKED]` prefix, file follow-up issue.
- **PASS WITH CHANGES**: Fix blocking issues, proceed.
- **PASS**: Proceed.

## Phase 5: Test

1. **Test** (tester subagent): Run full test suite per project CLAUDE.md
2. If tests fail:
   - Analyze the root cause — don't blindly retry
   - Go back to Phase 2 with failure context (max 2 cycles)
   - If still failing after 2 cycles: commit progress on the branch, create a draft PR (`--draft`) with `[FAILING]` prefix and failure analysis in the body, file a follow-up issue

Report completion: files changed, test results, critique verdict, any assumptions made. Ready for `/ship`.

Key constraints:
- If the project has multiple sub-repos (e.g., backend + frontend), treat each as a separate git repo and commit in the right one
