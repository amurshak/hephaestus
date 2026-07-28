Test the current implementation. Issue number (optional): $ARGUMENTS

<!-- requires: tester -->
<!-- chains: none -->
<!-- generated from .ai/workflows/test-issue.md; do not edit directly -->

> **Cursor:** run from the project root that contains `.cursor/`. Delegate to the subagents in `.cursor/agents/`; they share one working tree, so serialize file-modifying tasks.


**Always delegate to subagent(s)** — test output is verbose and should not pollute the main context window.

Steps:

1. **Detect repo**: Run `git remote get-url origin` to identify the target repo for `gh` commands.

2. **Identify changed files**: Run `git diff --name-only` and `git diff --cached --name-only` to see what's affected.

3. **Launch tester subagent(s)**:
   - Check CLAUDE.md to determine the correct test and lint commands for this project
   - Launch one or more tester subagents based on changed areas (parallelize if there are independent test suites)
   - Each tester runs in its own context and returns only a structured summary

4. **Verify acceptance criteria**: If an issue number was provided in $ARGUMENTS, run `gh issue view <#> --repo <detected-repo>` and check each acceptance criterion against the implementation. Report pass/fail per criterion.

5. **Report results** (concise — the subagents already absorbed the verbose output):
   - Tests: pass count, fail count, any error output
   - Lint: clean or list of violations
   - ACs: pass/fail per criterion

If anything fails, identify the root cause and suggest a fix. Do not just report the failure.

### Next steps
- If all tests pass: run `/ship` to create a PR, or `/finish <#>` if already merged
- If tests fail: fix the failures and re-run `/test-issue`
