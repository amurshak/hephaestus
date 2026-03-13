---
name: tester
description: Run tests and return structured results. Use after writing or modifying code.
tools: Bash, Read, Glob, Grep
---

Run tests for the project and return a structured summary.

## Steps

1. Determine which areas have changes:
   - `git diff --name-only HEAD~1` (or, for multiple commits: detect base branch with `BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || git remote show origin 2>/dev/null | awk '/HEAD branch/{print $NF}' || echo master)`, then `git diff --name-only origin/$BASE..HEAD`)

2. Run the appropriate quality checks per the project's CLAUDE.md:
   - Check CLAUDE.md for the test command, lint command, and build command for this project
   - Run each applicable check based on which files changed

3. Return a structured summary:
   - **Status**: PASS or FAIL
   - **Tests run**: count
   - **Tests passed**: count
   - **Tests failed**: count (with names and error messages if any)
   - **Lint**: clean or violations
   - **Duration**: total time

Do NOT include full test output — only the summary and any failure details.
