Run the full autonomous pipeline for issue $ARGUMENTS. No human intervention required.

If no issue number is provided, pick the highest-priority open issue from `gh issue list --state open --repo <detected-repo>` (prefer bugs over enhancements, older over newer).

## Pipeline

### Phase 1: Orient
- Run `git status` and `git log --oneline -5` for recent context
- Detect repo via `git remote get-url origin`
- Confirm clean working state before starting

### Phase 2: Start
- Read the issue (`gh issue view`)
- Explore relevant codebase (explorer subagent(s) in parallel)
- Create feature branch: `git checkout -b issue-<number>-<short-description>`

### Phase 3: Plan-Critique Loop
1. **Plan**: Break the issue into concrete implementation steps with TodoWrite
2. **Critique the plan** (general critique mode): Evaluate logic, assumptions, completeness, trade-offs, risks
3. **Refine**: Update the plan to address criticisms
4. **Re-critique**: Evaluate the refined plan
5. **Repeat** until the critique verdict reaches **SOUND** (max 3 iterations — if still RETHINK after 3, stop and ask the user)

### Phase 4: Implement
- Execute the plan using parallel coder subagents for independent tasks
- Sequential implementation for dependent changes
- Commit each logical unit of work separately

### Phase 5: Pre-ship Critique Gate
- Launch reviewer subagent(s) for code critique
- If **FAIL**: fix blocking issues, re-critique (max 3 iterations)
- If **PASS WITH CHANGES**: fix blocking issues, proceed
- If **PASS**: proceed

### Phase 6: Test
- Launch tester subagent(s) for all quality gates per project CLAUDE.md
- Verify acceptance criteria from the issue

If tests fail:
- **Go back to Phase 3** (re-plan with the failure context)
- Max 2 plan-implement-test cycles — if still failing after 2, stop and report to user

### Phase 7: Ship
- Update CHANGELOG.md
- Commit docs
- Push and create merge-ready PR (`gh pr create`)
- Merge the PR (`gh pr merge --squash --auto`)

### Phase 8: Finish
- Close the issue with reference to the PR
- Delete merged branches
- Print one-line summary: issue number, PR number, what shipped

### Phase 9: Update Docs
- Update CLAUDE.md if architecture changed
- Commit doc updates

## Guardrails

- **Stop for**: ambiguous requirements, public API contract changes, 3 failed critique loops, 2 failed plan-implement-test cycles
- **Never**: force-push, rewrite history, create PR with known failures
- Everything else runs autonomously.
