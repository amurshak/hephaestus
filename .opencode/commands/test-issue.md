---
description: "Test the current implementation. Issue number (optional): $ARGUMENTS"
---
<!-- requires: tester -->
<!-- chains: none -->
<!-- generated from .ai/workflows/test-issue.md; do not edit directly -->

> **OpenCode:** start from the project root that contains `.opencode/`. Spawn role agents with the Task tool or @mentions when required.

Test the current implementation. Issue number (optional): $ARGUMENTS

Run gate commands directly with tools, keeping exit status and an evidence record (below) for each. Delegate to @tester agent(s) when output is long or needs interpretation, or for an independent acceptance check.

Steps:

1. **Detect repo**: Run `git remote get-url origin` to identify the target repo for `gh` commands.

2. **Identify changed files**: Resolve the task change scope below, including clean committed work.

3. **Run the gates**:
   - Check CLAUDE.md to determine the correct test and lint commands for this project
   - Reuse a covering evidence record; run the rest, in parallel where suites are independent
   - Pass the recorded Scope and all change layers to each tester you launch; each returns a structured summary for that scope

4. **Verify acceptance criteria**: If an issue number was provided in $ARGUMENTS, run `gh issue view <#> --repo <detected-repo>` and check each acceptance criterion against every included change layer in that same scope, reading relevant untracked contents too. Report each as met, unmet, or unverified, and required unless the issue marks it optional.

5. **Report results** (concise — summarize, don't paste output):
   - Scope: base and merge-base OIDs, HEAD, included paths, exclusions, ambiguity
   - Evidence: one record per gate — command, outcome, revision, and pass/fail counts or error output
   - ACs: met / unmet / unverified per criterion
   - **Outcome**: PASS only if every gate passed and every required criterion is met; otherwise name each unmet criterion and each failing or BLOCKED gate

If anything fails, identify the root cause and suggest a fix. Do not just report the failure.

## Task change scope

Use a supplied Scope; otherwise base it on explicit `--base` (stacked work), the PR base, or confirmed `origin/HEAD`, in that order—never a guess or `HEAD~1`. Scope is the unique merge-base-to-HEAD diff plus separate staged, unstaged, and relevant untracked changes (`git diff --no-renames`, `git diff --cached HEAD`, `git diff`, `git ls-files --others --exclude-standard`; inventory with `--name-only -z`). Report/pass root, base/merge-base/HEAD OIDs, included paths, exclusions/reasons, and ambiguity. A missing/conflicting base, multiple merge-bases, failed inspection, or unresolved relevance makes scope incomplete and cannot PASS/auto-pass. Retain the base across commits; repeat affected gates if it changes. Include deletions and both rename paths; never mutate files to inspect them.

## Evidence records

Each check yields one record: check, scope, command or method, outcome, and revision — HEAD OID and clean or dirty tree — plus any environment it depends on (tool versions, services, credentials). Outcome is passed, failed, blocked (could not run), not run, or not applicable. Required gates are the critique plus the project's Development Commands, and only passed satisfies one; a gate the project does not define is not applicable, and any other check is optional. A record covers the delivered state while nothing it reads has changed: code, dependencies, configuration, environment, or — for doc checks — the docs. A dirty-tree record covers only if its dirty paths are outside what the check reads. Reuse a covering record, including one handed over by another command; rerun the rest, and rerun when unsure what a check reads. Keep exit status and failure output; never report a check that did not run as passed.

### Next steps
- If all tests pass: run `/ship` to create a PR, or `/finish <#>` if already merged
- If tests fail: fix the failures and re-run `/test-issue`
