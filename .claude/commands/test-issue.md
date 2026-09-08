<!-- requires: tester -->
<!-- chains: none -->
<!-- generated from .ai/workflows/test-issue.md; do not edit directly -->

Test the current implementation. Issue number (optional): $ARGUMENTS

**Always delegate to subagent(s)** — test output is verbose and should not pollute the main context window.

Steps:

1. **Detect repo**: Run `git remote get-url origin` to identify the target repo for `gh` commands.

2. **Identify changed files**: Resolve the task change scope below, including clean committed work.

3. **Launch tester subagent(s)**:
   - Check CLAUDE.md to determine the correct test and lint commands for this project
   - Launch one or more tester subagents based on changed areas (parallelize if there are independent test suites)
   - Pass the recorded Scope and all change layers to each tester; each returns a structured summary for that scope

4. **Verify acceptance criteria**: If an issue number was provided in $ARGUMENTS, run `gh issue view <#> --repo <detected-repo>` and check each acceptance criterion against every included change layer in that same scope, reading relevant untracked contents too. Report pass/fail per criterion.

5. **Report results** (concise — the subagents already absorbed the verbose output):
   - Scope: base and merge-base OIDs, HEAD, included paths, exclusions, ambiguity
   - Tests: pass count, fail count, any error output
   - Lint: clean or list of violations
   - ACs: pass/fail per criterion

If anything fails, identify the root cause and suggest a fix. Do not just report the failure.

## Task change scope

Use a supplied Scope; otherwise base it on explicit `--base` (stacked work), the PR base, or confirmed `origin/HEAD`, in that order—never a guess or `HEAD~1`. Scope is the unique merge-base-to-HEAD diff plus separate staged, unstaged, and relevant untracked changes (`git diff --no-renames`, `git diff --cached HEAD`, `git diff`, `git ls-files --others --exclude-standard`; inventory with `--name-only -z`). Report/pass root, base/merge-base/HEAD OIDs, included paths, exclusions/reasons, and ambiguity. A missing/conflicting base, multiple merge-bases, failed inspection, or unresolved relevance makes scope incomplete and cannot PASS/auto-pass. Retain the base across commits; repeat affected gates if it changes. Include deletions and both rename paths; never mutate files to inspect them.

### Next steps
- If all tests pass: run `/ship` to create a PR, or `/finish <#>` if already merged
- If tests fail: fix the failures and re-run `/test-issue`
