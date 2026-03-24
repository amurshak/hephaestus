---
name: orchestrator
description: Orchestrate end-to-end issue-to-ship delivery workflows including orientation, issue execution, testing, shipping, finishing, and doc updates. Use when the user asks to run autonomous issue work, /autopilot, /start-issue, /test-issue, /ship, /finish, /orient, or /update-docs style flows.
---

# Orchestrator

## Overview

Run a deterministic issue-to-ship workflow with explicit gates, repo detection, and concise status output. Designed for maximum autonomy — resolve ambiguity, recover from failures, and wind down cleanly without human intervention.

## Workflow Selection

1. Start with `orient` when context is unclear or work just resumed.
2. Run `start issue` for implementation on a specific GitHub issue.
3. Run `autopilot` for a fully autonomous orient->start->plan->critique->implement->test->ship->finish cycle. If no issues exist, autopilot self-triages by scanning the codebase and creating issues.
4. Run `test issue` before shipping if recent changes are unverified.
5. Run `ship` only when critique and quality gates pass (or pass with documented caveats).
6. Run `finish` only after PR merge is confirmed (or PR is created and awaiting merge).
7. Run `update docs` whenever architecture, priorities, or release notes changed.

## Core Rules

- Detect repo via `git remote get-url origin` before any `gh` action.
- Fail closed on quality gates: do not create or merge PRs with known security issues or broken builds.
- **Resolve ambiguity autonomously**: infer intent from codebase context, choose the simplest interpretation, document assumptions in the PR body. Do NOT stop to ask the user unless the ambiguity involves irreversible risk.
- **Recover before escalating**: when something fails, try an alternative approach. Only stop if alternatives are exhausted AND the failure involves irreversible risk.
- Run quality checks per the project's CLAUDE.md (test command, lint command, build command).
- Enforce trace and eval gates before shipping.

## Escalation Hierarchy

1. **Self-recover**: Try a different approach, skip non-critical tasks, auto-fix what you can
2. **Degrade gracefully**: Proceed with documented limitations (draft PR with descriptive prefix)
3. **Wind down cleanly**: Commit progress, file follow-up issues, print summary
4. **Hard stop**: Only for irreversible risk — security vulnerabilities being shipped, data loss paths, force-push

## Delivery Sequence

1. Load context:
- `git status`
- `git log --oneline -5`
- relevant issue details via `gh issue view`

2. Plan and critique:
- Build concrete steps and acceptance checks.
- Run critique until plan is sound or retry limit is reached.
- If critique can't reach SOUND after 3 iterations: proceed with the most defensible version and document caveats.

3. Implement:
- Execute independent tasks in parallel where safe.
- Keep changes scoped and commit logical units.
- If a task is blocked: try one alternative, then skip with a TODO and continue.

4. Verify:
- Run quality checks as specified in the project's CLAUDE.md.
- Map results to issue acceptance criteria when an issue number is available.
- If verification fails: analyze root cause, re-plan with failure context (max 2 cycles). If still failing: commit progress, draft PR with failure analysis, file follow-up issue.

5. Pre-ship critique:
- Launch reviewer for code critique before shipping.
- **FAIL**: Fix blocking issues, re-critique (max 3 iterations). If still FAIL: commit progress, draft PR with `[BLOCKED]` prefix, file follow-up issue.
- **PASS WITH CHANGES**: Fix blocking issues, proceed.
- **PASS**: Proceed.

6. Ship:
- Update `CHANGELOG.md`.
- Push and create merge-ready PR with quality-gate checklist.
- Enable squash auto-merge (if auto-merge can't be enabled, note it and proceed).

7. Finish:
- Confirm PR merged (or note pending merge).
- Close issue with PR reference.
- Delete merged branches (local and remote).
- File follow-up issues for any remaining work.

## Session Management

Every session must end at a clean checkpoint:
- No uncommitted changes
- Branches pushed to remote
- Follow-up issues filed for unfinished work
- Session summary printed (completed, created, remaining)

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
