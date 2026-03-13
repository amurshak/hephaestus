# Workflow Map

## Command Equivalents

- `orient`: gather git status/logs, open issues, changelog head, then suggest one next action.
- `start-issue`: issue context -> code exploration -> plan/critique loop -> implement -> auto-verify.
- `autopilot`: full autonomous pipeline from orient through finish with retry limits.
- `test-issue`: detect changed areas and run targeted quality validation per CLAUDE.md.
- `ship`: critique gate -> quality gates -> changelog -> PR create -> auto-merge.
- `finish`: verify merge -> close issue -> branch cleanup -> docs update.
- `update-docs`: refresh project guidance and changelog after shipped work.

## Retry Limits

- Plan/critique loop: max 3 iterations.
- Post-failure plan->implement->test cycles: max 2 iterations.
- Pre-ship critique retries: max 3 iterations.

## Hard Stops

- Ambiguous requirements.
- Required public API contract changes without approval.
- Exceeded retry limits.
