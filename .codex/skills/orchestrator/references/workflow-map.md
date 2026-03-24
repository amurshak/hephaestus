# Workflow Map

## Command Equivalents

- `orient`: gather git status/logs, open issues, changelog head, then suggest one next action.
- `start-issue`: issue context -> code exploration -> plan/critique loop -> implement -> auto-verify. Resolves ambiguity autonomously via documented assumptions.
- `autopilot`: full autonomous pipeline from orient through finish with retry limits. Self-triages when no issues exist. Winds down cleanly at natural stopping points.
- `test-issue`: detect changed areas and run targeted quality validation per CLAUDE.md.
- `ship`: critique gate -> quality gates -> changelog -> PR create -> auto-merge. Creates draft PRs with descriptive prefixes when gates can't fully pass.
- `finish`: verify merge -> close issue -> branch cleanup -> file follow-up issues -> docs update -> session summary.
- `update-docs`: refresh project guidance and changelog after shipped work.
- `refactor`: analysis -> plan/critique loop -> implement with parallel coders -> review gate -> ship. Enforces characterization tests before refactoring untested code.
- `critique`: auto-detects mode — Code Critique (delegates to reviewer subagent) for uncommitted changes, General Critique (SOUND/NEEDS REFINEMENT/RETHINK) for strategy/plans. Can run both simultaneously.
- `research`: break question into facets, spawn parallel researcher subagents, synthesize findings with confidence rating and source URLs.
- `create-issue`: explore relevant code via explorer subagent, draft issue with acceptance criteria and technical context, apply existing repo labels.
- `update-hephaestus`: pull latest submodule, re-run install.sh --clean, show what changed.

## Retry Limits

- Plan/critique loop: max 3 iterations. On exhaustion: proceed with best version + documented caveats.
- Post-failure plan->implement->test cycles: max 2 iterations. On exhaustion: commit progress, draft PR, file follow-up issue.
- Pre-ship critique retries: max 3 iterations. On exhaustion: draft PR with unresolved issues listed, file follow-up issue.

## Escalation Hierarchy

1. **Self-recover**: Try alternative approach, skip non-critical task, auto-fix
2. **Degrade gracefully**: Proceed with documented limitations
3. **Wind down cleanly**: Commit, push, file follow-up issues, print summary
4. **Hard stop**: Only for irreversible risk (security, data loss, force-push)

## Hard Stops (truly irreversible risk only)

- Security vulnerabilities being shipped to production
- Data loss or corruption paths
- Force-push to protected branches

## Soft Stops (proceed with documentation)

- Ambiguous requirements → make assumption, document in PR
- Public API changes → implement with deprecation path, flag in PR
- Exhausted retries → commit progress, file follow-up issue
