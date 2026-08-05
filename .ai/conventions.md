# Workflow Conventions

> **Audience: product** — every statement here is true in any project that installed hephaestus. Nothing about maintaining *this* repo belongs in this file; that lives in [CONTRIBUTING.md](../CONTRIBUTING.md) and [CLAUDE.md](../CLAUDE.md).

This is the behavior spec the workflows implement. The workflows in `.ai/workflows/` are the shipped artifact — they state these values at the point of use so they resolve in an installed project, where this file does not exist. `tests/check_conventions.sh` fails if a workflow disagrees with this file.

## The eight-phase loop

Every delivery command walks the same phases:

1. **Orient** — read the issue, explore the code, understand what's needed
2. **Plan** — break work into steps, identify what can run in parallel
3. **Critique** — adversarial evaluation of the plan before code exists
4. **Implement** — parallel coders for independent tasks, sequential for dependencies
5. **Review** — adversarial evaluation of the code before it ships
6. **Test** — the target project's quality gates
7. **Ship** — PR with a gate checklist, squash auto-merge
8. **Finish** — close the issue, delete merged branches, file follow-ups, sync docs

## Retry limits

| Loop | Limit |
|---|---|
| Plan-critique | 3 iterations |
| Pre-ship code critique | 3 iterations |
| Test-fix | 2 full plan-implement-test cycles |

These are product defaults. A project that needs different values states them in a `## Workflow Rules` section of its own CLAUDE.md; an explicit project rule wins over the default. Nothing scaffolds that section — a project without one gets the defaults above.

## Escalation

When something fails, climb this ladder in order. Each rung is tried before the next:

1. **Self-recover** — try a different approach
2. **Degrade gracefully** — proceed with the limitation documented, rather than blocking
3. **Wind down cleanly** — commit progress, push the branch, open a draft PR prefixed `[WIP]` / `[BLOCKED]` / `[FAILING]`, file a follow-up issue with context
4. **Hard stop** — only for irreversible risk: shipping a known security hole, data loss, force-push

Retry exhaustion is a rung-3 event, never a question to the user.

**Git conflicts** are a rung-3 case with a fixed shape: check the base branch before implementing, attempt a rebase, and if the rebase fails, commit progress, open a draft PR prefixed `[CONFLICT]`, and file a follow-up issue with the conflict details.

## Ambiguity

Infer intent from the codebase, existing patterns, and commit history. Choose the simplest reading that satisfies the acceptance criteria. Record each assumption under "Assumptions Made" in the PR body.

## Phase transitions

When work is ready for the next phase, invoke that phase's command directly — `/ship`, `/finish` — or name it as a concrete option. The loop has an explicit command for every transition; a vague "want me to commit this?" is never one of them.

## Session checkpoints

Every session ends at a clean checkpoint, in this order of preference: after `/finish`, after `/ship`, or after committing progress and filing follow-up issues. Never mid-implementation with uncommitted changes. A checkpoint means:

1. **Nothing uncommitted** — commit before stopping, even partial work
2. **No orphaned branches** — push so progress survives the session
3. **Breadcrumbs** — a GitHub issue per unfinished thread, with enough context to resume
4. **Clean local state** — merged branches deleted, session stashes popped
5. **A summary** — what was completed, what was created, what remains

## Verdicts

- Code review: **PASS** / **PASS WITH CHANGES** / **FAIL**
- General critique: **SOUND** / **NEEDS REFINEMENT** / **RETHINK**

## What the project owns

Hephaestus ships the loop; the project supplies the specifics. Workflows read these from the project's CLAUDE.md at runtime:

| Section | Read by | Supplies |
|---|---|---|
| `## Development Commands` | `/ship`, `/test-issue`, tester | test, lint, and build commands — the quality gates |
| `## Worktrees` | `/worktrees` | `max`, `serialize_paths`, `setup` |
| `## Docs Requirements` | `/finish` | which doc files a change must update, overriding the defaults |

Only `## Development Commands` is required. The rest have working defaults. `## Workflow Rules` is not in this table because no step goes looking for it: a project's CLAUDE.md is ambient context, so an explicit rule there wins over a command's default without anything having to fetch it.
