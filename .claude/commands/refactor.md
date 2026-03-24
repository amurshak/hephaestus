<!-- requires: coder, reviewer, explorer -->
Refactor the target specified in $ARGUMENTS. Run autonomously — do not pause for plan approval.

## Process

### Phase 1: Analysis
1. **Detect repo**: Run `git remote get-url origin` to identify the target repo.
2. Read the target file(s) and all files that import/depend on them
3. For large refactors spanning multiple modules, spawn parallel explorer subagents to investigate each module's dependencies and usage patterns simultaneously
4. Measure current state: line count, function count, nesting depth, number of parameters
5. Identify: repeated patterns, unused code, unnecessary abstractions, tight coupling

### Phase 2: Plan-Critique Loop
1. Create a feature branch: `git checkout -b refactor/<short-description>` where `<short-description>` is a kebab-case summary derived from $ARGUMENTS.
2. Build a refactoring plan (what changes, what's preserved, expected impact) via TodoWrite.
3. Self-critique the plan (general critique mode): evaluate risks, coupling, test coverage gaps, API contract changes.
4. Refine and re-critique until verdict reaches **SOUND** (max 3 iterations per CLAUDE.md retry limits).
5. If NEEDS REFINEMENT after 3: proceed with best version, document caveats in PR. If RETHINK: file follow-up issue and wind down.

### Phase 3: Implement
1. Make single, focused changes — one concern per commit
2. For independent refactoring tasks across different files, use parallel coder subagents (in worktrees)
3. Run tests after each change per the project's CLAUDE.md (test command, lint command)
4. If tests fail after a change, fix and re-test before proceeding (max 2 test-fix cycles per change)

### Phase 4: Pre-ship Critique

Launch reviewer subagent for code critique before shipping.

- **FAIL**: Fix blocking issues, re-critique (per CLAUDE.md retry limits). If still FAIL: commit progress, create draft PR with `[BLOCKED]` prefix, file follow-up issue.
- **PASS WITH CHANGES**: Fix blocking issues, proceed.
- **PASS**: Proceed.

### Phase 5: Ship
1. Update `CHANGELOG.md` with a summary of the refactoring changes
2. Commit doc changes
3. Push the branch: `git push -u origin refactor/<short-description>`
4. Create a PR via `gh pr create --repo <detected-repo>` with a body covering: summary of what changed, metrics (lines/complexity before/after), test results, API changes or risks
5. Merge: `gh pr merge --squash --auto` (or leave open if auto-merge can't be enabled)

### Phase 6: Report
Output:
- **PR URL**: Link to the merged (or open) PR
- **Summary**: What changed and why
- **Metrics**: Lines of code before/after, complexity before/after
- **Test results**: All passing
- **Risks**: Anything downstream code should know about

## Constraints
- If refactoring changes public API contracts: implement with a deprecation path (keep old signature as a wrapper), flag the API change prominently in the PR body under "API Changes", and file a follow-up issue for removing the deprecated path
- Never refactor without passing tests as a safety net
- One focused change at a time — no big bang rewrites
- If tests don't exist for the target, write characterization tests first
