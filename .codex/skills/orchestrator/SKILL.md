---
name: orchestrator
description: Orchestrate end-to-end issue-to-ship delivery workflows including orientation, issue execution, testing, shipping, finishing, refactoring, research, and doc updates. Use when the user asks to run autonomous issue work, /autopilot, /start-issue, /test-issue, /ship, /finish, /orient, /update-docs, /refactor, /critique, /research, /create-issue, or /update-hephaestus style flows.
---

# Orchestrator

Run a deterministic issue-to-ship workflow with explicit gates, repo detection, and concise status output. Designed for maximum autonomy -- resolve ambiguity, recover from failures, and wind down cleanly without human intervention.

## Workflow

Follows the same workflow as the corresponding Claude commands:

- **orient** -- Load project context and determine next action
- **start-issue** -- Plan, critique, implement, and test a specific GitHub issue
- **autopilot** -- Full autonomous orient-to-finish cycle; self-triages when no issues exist
- **test-issue** -- Run quality gates from the project's CLAUDE.md
- **ship** -- Push branch and create merge-ready PR with quality-gate checklist
- **finish** -- Close issue, delete merged branches, file follow-ups
- **update-docs** -- Sync CLAUDE.md, CHANGELOG.md, and README.md with recent work
- **refactor** -- Autonomous refactoring with plan-critique loop and review gate
- **critique** -- Adversarial review of code changes or strategy/plans
- **research** -- Parallel web research with synthesized findings
- **create-issue** -- Codebase-informed GitHub issue creation with research and labels
- **update-hephaestus** -- Update the hephaestus submodule to latest version

See `CLAUDE.md` for retry limits, escalation hierarchy, and session management rules.

## References

- `references/workflow-map.md` -- command-by-command phase mappings
- `references/role-map.md` -- agent delegation patterns
- `references/trace-eval-gates.md` -- observability and regression checks
