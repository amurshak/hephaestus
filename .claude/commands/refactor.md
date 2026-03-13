Refactor the target specified in $ARGUMENTS. Run autonomously — do not pause for plan approval.

## Process

### Phase 1: Analysis
1. Read the target file(s) and all files that import/depend on them
2. For large refactors spanning multiple modules, spawn parallel explorer subagents to investigate each module's dependencies and usage patterns simultaneously
3. Measure current state: line count, function count, nesting depth, number of parameters
4. Identify: repeated patterns, unused code, unnecessary abstractions, tight coupling

### Phase 2: Plan
1. Log the refactoring plan (what changes, what's preserved, expected impact) but proceed immediately to implementation — do not wait for approval.
2. Create a feature branch: `git checkout -b refactor/<short-description>` where `<short-description>` is a kebab-case summary derived from $ARGUMENTS.

### Phase 3: Implement
1. Make single, focused changes — one concern per commit
2. For independent refactoring tasks across different files, use parallel coder subagents (in worktrees)
3. Run tests after each change per the project's CLAUDE.md (test command, lint command)
4. If tests fail after a change, fix and re-test before proceeding

### Phase 4: Ship
1. Push the branch: `git push -u origin refactor/<short-description>`
2. Create a PR via `gh pr create` with a body covering: summary of what changed, metrics (lines/complexity before/after), test results, API changes or risks
3. Merge: `gh pr merge --squash --auto` (or leave open if auto-merge can't be enabled)

### Phase 5: Report
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
