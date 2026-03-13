Refactor the target specified in $ARGUMENTS. Run autonomously — do not pause for plan approval.

## Process

### Phase 1: Analysis
1. Read the target file(s) and all files that import/depend on them
2. For large refactors spanning multiple modules, spawn parallel explorer subagents to investigate each module's dependencies and usage patterns simultaneously
3. Measure current state: line count, function count, nesting depth, number of parameters
4. Identify: repeated patterns, unused code, unnecessary abstractions, tight coupling

### Phase 2: Plan
Log the refactoring plan (what changes, what's preserved, expected impact) but proceed immediately to implementation — do not wait for approval.

### Phase 3: Implement
1. Make single, focused changes — one concern per commit
2. For independent refactoring tasks across different files, use parallel coder subagents (in worktrees)
3. Run tests after each change per the project's CLAUDE.md (test command, lint command)
4. If tests fail after a change, fix and re-test before proceeding

### Phase 4: Report
Output:
- **Summary**: What changed and why
- **Metrics**: Lines of code before/after, complexity before/after
- **Test results**: All passing
- **Risks**: Anything that downstream code should know about

## Constraints
- Never change public API contracts without explicit approval (this is the one exception to autonomous operation)
- Never refactor without passing tests as a safety net
- One focused change at a time — no big bang rewrites
- If tests don't exist for the target, write characterization tests first
