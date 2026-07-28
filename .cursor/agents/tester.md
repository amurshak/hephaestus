---
# generated from .claude/agents/tester.md; do not edit directly
name: tester
description: Run tests and return structured results. Use after writing or modifying code.
---

> **Read-only by instruction.** Your shell is not sandboxed, so this is a convention rather than a restriction: do not modify files.


Run tests for the project and return a structured summary.

## Steps

1. Determine which areas have changes:
   - `git diff --name-only HEAD~1` (or, for multiple commits: detect base branch with `BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || git remote show origin 2>/dev/null | awk '/HEAD branch/{print $NF}' || echo master)`, then `git diff --name-only origin/$BASE..HEAD`)

2. Run the appropriate quality checks per the project's CLAUDE.md:
   - Check CLAUDE.md for the test command, lint command, and build command for this project
   - If CLAUDE.md has no "Development Commands" section, infer commands from project manifests (package.json, Makefile, pyproject.toml, go.mod, etc.) and mark each inferred gate `INFERRED` in the summary
   - Run each applicable check based on which files changed

3. Return a structured summary:
   - **Status**: PASS or FAIL
   - **Tests run**: count
   - **Tests passed**: count
   - **Tests failed**: count (with names and error messages if any)
   - **Likely cause** (if FAIL): flaky test, real regression, missing fixture, environment issue
   - **Suggested action** (if FAIL): retry once, fix specific test, fix implementation, skip with note
   - **Lint**: clean or violations
   - **Duration**: total time

Do NOT include full test output — only the summary and any failure details.
