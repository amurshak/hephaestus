# Trace and Eval Gates

## Trace Gate (required before ship)

Create and report one run identifier for each issue workflow:
- `run_id`: `<issue-or-task>-<YYYYMMDD>-<HHMM>`

Capture this structured trace summary:
- user goal
- plan version and critique verdict
- files changed
- tool/test commands run
- failures and remediations
- final ship decision

## Handoff Gate

For each delegated role (`explorer`, `coder`, `tester`, `reviewer`, `researcher`), record:
- input task statement
- output summary
- unresolved risks

Do not ship if unresolved blocking risks exist in reviewer/tester outputs.

## Eval Gate (required before ship)

Run a minimal regression checklist:
1. Acceptance criteria mapping:
- every criterion marked `pass` or `fail` with evidence.

2. Tool-use quality:
- no missing required tool runs for quality gates per project CLAUDE.md.

3. Safety/compliance:
- no protected-file edits without explicit override.
- no known failing lint/tests at PR creation.

## Post-ship Retrospective

Add one short note to persistent memory:
- what failed initially
- what fixed it
- what to reuse next time
