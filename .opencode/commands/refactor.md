---
description: "Refactor the target specified in $ARGUMENTS. Run autonomously — do not pause for plan approval."
---
<!-- requires: coder, explorer -->
<!-- chains: /ship, /finish -->
<!-- generated from .ai/workflows/refactor.md; do not edit directly -->

> **OpenCode:** start from the project root that contains `.opencode/`. Invoke nested workflows as slash commands (/ship, /finish) so their full templates load — do not paraphrase. Spawn role agents with the Task tool or @mentions.

Refactor the target specified in $ARGUMENTS. Run autonomously — do not pause for plan approval.

## Process

### Phase 1: Analysis
1. **Detect repo**: Run `git remote get-url origin` to identify the target repo.
2. Read the target file(s) and all files that import/depend on them
3. For large refactors spanning multiple modules, spawn parallel @explorer agents to investigate each module's dependencies and usage patterns simultaneously
4. Measure current state: line count, function count, nesting depth, number of parameters
5. Identify: repeated patterns, unused code, unnecessary abstractions, tight coupling

### Phase 2: Plan-Critique Loop
1. Create a feature branch: `git checkout -b refactor/<short-description>` where `<short-description>` is a kebab-case summary derived from $ARGUMENTS.
2. Build a refactoring plan (what changes, what's preserved, expected impact) via the todo tools.
3. Self-critique the plan (general critique mode): evaluate risks, coupling, test coverage gaps, API contract changes.
4. Refine and re-critique until verdict reaches **SOUND** (max 3 iterations).
5. If NEEDS REFINEMENT after 3 iterations: proceed with best version, document caveats in PR. If RETHINK: file follow-up issue and wind down.

### Phase 3: Implement
1. Make single, focused changes — one concern per commit
2. For independent refactoring tasks across different files, use parallel @coder Task invocations (serialize file edits — no worktree isolation)
3. Run tests after each change per the project's CLAUDE.md (test command, lint command)
4. If tests fail after a change, fix and re-test before proceeding (max 2 cycles)

### Phase 4: Ship → `/ship`

Run `/ship`. It runs the pre-push critique gate, all quality gates, updates CHANGELOG, pushes the branch, creates the PR, and auto-merges.

When `/ship` builds the PR body, populate the Summary bullets with the refactoring metrics (lines/complexity before/after), API changes (if any) under Known Limitations, and downstream risks.

### Phase 5: Finish → `/finish`

Run `/finish` (no issue number — refactors typically don't map to a tracked issue, and `/finish` handles the no-issue case by skipping the close step). It deletes branches, runs `/update-docs` to sync docs, captures a retrospective, and prints the session summary.

### Phase 6: Report
Output as the final session line:
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

### Next steps
- Run `/finish <#>` after merge to close the issue and clean up branches
- Or run `/orient` to see what to work on next
