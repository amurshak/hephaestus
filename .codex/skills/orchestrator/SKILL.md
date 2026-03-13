---
name: orchestrator
description: Orchestrate end-to-end issue-to-ship delivery workflows including orientation, issue execution, testing, shipping, finishing, and doc updates. Use when the user asks to run autonomous issue work, /autopilot, /start-issue, /test-issue, /ship, /finish, /orient, or /update-docs style flows.
---

# Orchestrator

## Overview

Run a deterministic issue-to-ship workflow with explicit gates, repo detection, and concise status output.

## Workflow Selection

1. Start with `orient` when context is unclear or work just resumed.
2. Run `start issue` for implementation on a specific GitHub issue.
3. Run `autopilot` for a fully autonomous orient->start->plan->critique->implement->test->ship->finish cycle.
4. Run `test issue` before shipping if recent changes are unverified.
5. Run `ship` only when critique and quality gates pass.
6. Run `finish` only after PR merge is confirmed.
7. Run `update docs` whenever architecture, priorities, or release notes changed.

## Core Rules

- Detect repo via `git remote get-url origin` before any `gh` action.
- Fail closed on quality gates: do not create or merge PRs with known blockers.
- Stop and ask the user if requirements are ambiguous, public API contracts must change, or retry limits are exceeded.
- Run quality checks per the project's CLAUDE.md (test command, lint command, build command).
- Enforce trace and eval gates before shipping.

## Delivery Sequence

1. Load context:
- `git status`
- `git log --oneline -5`
- relevant issue details via `gh issue view`

2. Plan and critique:
- Build concrete steps and acceptance checks.
- Run critique until plan is sound or retry limit is reached.

3. Implement:
- Execute independent tasks in parallel where safe.
- Keep changes scoped and commit logical units.

4. Verify:
- Run quality checks as specified in the project's CLAUDE.md.
- Map results to issue acceptance criteria when an issue number is available.

5. Ship:
- Update `CHANGELOG.md`.
- Push and create merge-ready PR with quality-gate checklist.
- Enable squash auto-merge.

6. Finish:
- Confirm PR merged.
- Close issue with PR reference.
- Delete merged local branches.

## Output Format

Use concise sections:
- `Current state`
- `Plan`
- `Execution`
- `Quality gates`
- `Ship status`
- `Next action`

## References

- For exact command-by-command mappings, read `references/workflow-map.md`.
- For role delegation patterns, read `references/role-map.md`.
- For required observability and regression checks, read `references/trace-eval-gates.md`.
