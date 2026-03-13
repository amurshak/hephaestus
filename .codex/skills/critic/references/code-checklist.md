# Code Checklist

## Required Inputs

- Full diff and staged diff.
- Full content of changed files.
- Relevant tests and call sites.

## Blocking Patterns

- Functional regressions.
- Security vulnerabilities.
- Data loss or corruption paths.
- Broken tests or untested risky behavior.
- Violations of explicit project constraints.

## Non-blocking Patterns

- Readability improvements.
- Minor refactors.
- Naming consistency.
- Optional performance polish.

## Output Contract

- Keep findings specific and actionable.
- Include file paths and impact.
- End with one verdict: `PASS`, `PASS WITH CHANGES`, or `FAIL`.
