# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Hephaestus is a portable AI workflow toolkit distributed as a git submodule. It provides shared agents, commands, and Codex skills that enable autonomous issue-to-ship development workflows across multiple projects. It is not a standalone application — it is installed into other projects via `./install.sh <target>`.

## Repository Structure

- `.claude/agents/` — Subagent definitions (coder, reviewer, tester, explorer, researcher) with tool permissions and structured output contracts
- `.claude/commands/` — User-facing slash commands that orchestrate agents through quality-gated workflows
- `.codex/skills/` — Codex skill equivalents (orchestrator, critic, research-issue) with reference docs in `references/` subdirectories
- `install.sh` — Adds hephaestus as `.hephaestus` submodule in a target project, creates symlinks into `.claude/` and `.codex/`
- `update.sh` — Pulls latest hephaestus into an already-installed project

## Core Workflow Pattern

All delivery commands enforce a deterministic loop:

1. **Plan** — Break work into steps via TodoWrite
2. **Critique** — Adversarial evaluation (max 3 iterations until SOUND/PASS)
3. **Implement** — Parallel coder subagents for independent tasks, sequential for dependencies
4. **Test** — Quality gates per the target project's CLAUDE.md (test, lint, build commands)
5. **Ship** — PR with quality-gate checklist, squash auto-merge
6. **Finish** — Close issue, delete merged branches, update docs

Autonomy-first: commands resolve ambiguity via documented assumptions, recover from failures by trying alternative approaches, and wind down cleanly when limits are reached (commit progress, file follow-up issues). Hard stops are reserved for irreversible risk only (security vulnerabilities, data loss, force-push).

## Key Design Constraints

- **Commands read the target project's CLAUDE.md** to discover test/lint/build commands. The "Development Commands" section in each installed project drives all quality gates.
- **Repo detection** is done via `git remote get-url origin` — commands never hardcode repo references.
- **orient.md is project-specific** — it is explicitly excluded from install.sh symlinking. Each project must create its own.
- **install.sh is idempotent** — it never overwrites existing files; re-running is safe.
- **Symlinks are relative** — agents link as `../../.hephaestus/.claude/agents/<name>`, commands as `../../.hephaestus/.claude/commands/<name>`, skills as `../../.hephaestus/.codex/skills/<name>`.

## Agent Conventions

- Agents declare their allowed tools and isolation mode in YAML frontmatter
- Coder agents run in `isolation: worktree` to enable safe parallel edits
- All agents return structured output (files changed, status, verdict) — never raw verbose logs
- Reviewer verdicts: PASS / PASS WITH CHANGES / FAIL
- General critique verdicts: SOUND / NEEDS REFINEMENT / RETHINK

## Autonomy Conventions

Commands are designed to run without human intervention. The escalation hierarchy is:

1. **Self-recover**: Try an alternative approach (different strategy, skip non-critical task, etc.)
2. **Degrade gracefully**: Proceed with documented limitations rather than blocking
3. **Wind down cleanly**: Commit progress, file follow-up issues, print summary
4. **Hard stop**: Only for irreversible risk — security issues being shipped, data loss, force-push

**Ambiguity resolution**: When requirements are unclear, infer intent from codebase context and existing patterns. Choose the simplest interpretation. Document all assumptions in the PR body under "Assumptions Made."

**Retry exhaustion**: When retry limits are reached, do NOT stop and ask. Instead: commit progress on a branch, create a draft PR with a descriptive prefix (`[WIP]`, `[BLOCKED]`, `[FAILING]`), file a follow-up issue with context, and wind down.

**Transition to next phase**: When work is complete and ready to ship, invoke `/ship` directly (or present it as a concrete option). Do not ask vague questions like "Want me to commit and ship this?" — the workflow has explicit commands for every transition. Use them.

## Session Management

Every session must end at a clean checkpoint:

1. **No uncommitted changes** — always commit before stopping, even partial work
2. **No orphaned branches** — push branches so progress is preserved remotely
3. **Breadcrumbs for next session** — file GitHub issues for unfinished work with enough context to resume
4. **Clean local state** — delete merged branches, pop session stashes
5. **Session summary** — print what was completed, what was created, what remains

Natural stopping points (in order of preference):
- After finishing an issue (Phase 8-9 of autopilot)
- After shipping a PR (even if not yet merged)
- After committing progress and filing follow-up issues
- Never mid-implementation with uncommitted changes

## Improving the Workflow

When the user gives feedback about how commands, agents, or workflows should behave, consider whether the improvement applies broadly across projects. If it does, persist it in the repo (CLAUDE.md, the relevant command/agent file, or Codex skill) — not just in local memory. Local memory is per-machine; repo changes propagate to every project using hephaestus.

## Editing Guidelines

When modifying agents or commands:
- Preserve the YAML frontmatter format in agent files (name, description, tools, isolation)
- Preserve the `$ARGUMENTS` placeholder in commands — it receives user input at invocation
- Keep retry limits consistent across commands and skills (plan-critique: 3, test cycles: 2, pre-ship critique: 3)
- Commands that delegate to subagents should specify which agent type to use and what structured output to expect
- Codex skill `references/` docs mirror the logic in Claude commands — keep them in sync

## What Target Projects Must Provide

These are NOT in this repo — each installed project owns them:
- `.claude/commands/orient.md` — project-specific context (repos, structure, next action)
- `.claude/hooks/` — lint/test hooks for the project's tech stack
- `CLAUDE.md` with a "Development Commands" section (test, lint, build commands)
- `AGENTS.md` — index of available local and shared skills
- `.codex/settings.local.json` and `.claude/settings.local.json` — project-specific config
