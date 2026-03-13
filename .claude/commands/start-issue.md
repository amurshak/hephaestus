Start working on issue $ARGUMENTS. Run autonomously through the full plan-critique-implement cycle.

## Phase 1: Context

1. **Detect repo**: Run `git remote get-url origin` to identify the target repo.

2. **Load context in parallel**:
   - **Read the issue**: `gh issue view <#> --repo <detected-repo>`
   - **Explore codebase** (explorer subagent(s)): Search for relevant files, understand current implementation
   - **Recent history**: `git log --oneline -5`
   - For complex issues, spawn multiple explorer subagents per subsystem

## Phase 2: Plan-Critique Loop

1. **Plan**: Break the issue into concrete steps with TodoWrite. Identify independent tasks for parallel coders.
2. **Self-critique** (general critique mode): Evaluate the plan for logic, assumptions, completeness, trade-offs.
3. **Refine**: Update the plan to address weaknesses.
4. **Re-critique**: Evaluate the refined plan.
5. **Repeat** until verdict reaches **SOUND** (max 3 iterations).

## Phase 3: Implement

- Use parallel coder subagents (in worktrees) for independent changes
- Sequential implementation for dependent changes
- Commit each logical unit separately

## Phase 4: Auto-verify

1. **Test** (tester subagent): Run full test suite per project CLAUDE.md
2. **Code critique** (reviewer subagent): Check for blocking issues
3. If either fails: go back to Phase 2 with failure context (max 2 cycles)

Report completion: files changed, test results, critique verdict. Ready for `/ship`.

Key constraints:
- Never add Claude attribution to commits
- If the project has multiple sub-repos (e.g., backend + frontend), treat each as a separate git repo and commit in the right one
