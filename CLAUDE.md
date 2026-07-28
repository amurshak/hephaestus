# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Core Principles

Three ideas shape every design decision:

1. **Simplicity** — One command to deliver an issue. One file to configure quality gates. One submodule to share across projects. Complexity is a bug.

2. **Self-improvement** — The system critiques its own plans before implementing, reviews its own code before shipping, and finds work when idle. Improvements propagate to every project via the submodule.

3. **Autonomy** — Commands run without human intervention. They resolve ambiguity, recover from failures, and wind down cleanly. Stopping to ask is a last resort reserved for irreversible risk.

When in doubt about a design choice, pick the option that is simpler, more self-improving, or more autonomous.

## What This Is

Hephaestus is an implementation of a generic software development workflow pattern for AI coding agents. It encodes the observation that all delivery follows the same loop — orient, plan, critique, implement, review, test, ship, finish — and makes that loop executable, autonomous, and self-correcting. Distributed as a git submodule containing prose workflows plus tool adapters that cause an AI coding agent to behave as a structured delivery system. Installed into other projects via `./install.sh <target>`.

## Development Commands

- **Test**: `./tests/run.sh` — full integration suite (single file: `bash tests/test_<name>.sh`)
- **Lint/drift**: `./scripts/sync-agent-adapters.sh --check`, `./scripts/sync-opencode-adapters.sh --check`, `bash tests/check_composition.sh`
- **Build**: none (prose + shell; no compile step)

## Repository Structure

- `.claude/agents/` — Subagent definitions (coder, reviewer, tester, explorer, researcher) with tool permissions and structured output contracts
- `.ai/workflows/` — canonical, tool-neutral workflow specs with `name`, `requires`, and `chains` frontmatter
- `.claude/commands/` — generated Claude slash-command adapters for the canonical workflows
- `.opencode/commands/` — generated OpenCode command adapters for the same canonical workflows
- `.opencode/agents/` — generated OpenCode subagent adapters from `.claude/agents/`
- `opencode.json` — OpenCode project config that loads `AGENTS.md` and this file as instructions
- `.claude-plugin/plugin.json` — Plugin manifest for Claude Code marketplace install (declares `commands` and `agents` paths so the plugin loader finds them under `.claude/`)
- `scripts/sync-agent-adapters.sh` — generates/checks tool-specific adapters from `.ai/workflows/`
- `scripts/sync-opencode-adapters.sh` — generates/checks OpenCode commands and agent adapters
- `install.sh` — Adds hephaestus as `.hephaestus` submodule in a target project, creates symlinks into `.claude/` and `.opencode/`
- `update.sh` — Pulls latest hephaestus into an already-installed project

## Core Workflow Pattern

All delivery commands enforce a deterministic eight-phase loop:

1. **Orient** — Read the issue, explore relevant code, understand what's needed
2. **Plan** — Break work into steps via TodoWrite, identify parallelizable tasks
3. **Critique** — Adversarial evaluation (max 3 iterations until SOUND/PASS)
4. **Implement** — Parallel coder subagents in worktrees for independent tasks, sequential for dependencies
5. **Review** — Pre-ship code critique (max 3 iterations)
6. **Test** — Quality gates per the target project's CLAUDE.md (test, lint, build commands)
7. **Ship** — PR with quality-gate checklist, squash auto-merge
8. **Finish** — Close issue, delete merged branches, file follow-ups, update docs

**Retry limits** (all commands reference these — do not hardcode separately):
- Plan-critique loop: max **3** iterations
- Pre-ship code critique: max **3** iterations
- Test-fix cycles: max **2** full plan-implement-test cycles

Autonomy-first: commands resolve ambiguity via documented assumptions, recover from failures by trying alternative approaches, and wind down cleanly when limits are reached (commit progress, file follow-up issues). Hard stops are reserved for irreversible risk only (security vulnerabilities, data loss, force-push).

## Key Design Constraints

- **Workflows live in `.ai/workflows/`** as the canonical source. `.claude/commands/` files are generated adapters; run `./scripts/sync-agent-adapters.sh` after workflow edits and `./scripts/sync-agent-adapters.sh --check` in quality gates.
- **OpenCode adapters are generated too**: `.opencode/commands/` comes from `.ai/workflows/`; `.opencode/agents/` comes from `.claude/agents/`. Run `./scripts/sync-opencode-adapters.sh` after workflow or agent edits and `./scripts/sync-opencode-adapters.sh --check` in quality gates.
- **Commands read the target project's CLAUDE.md** to discover test/lint/build commands. The "Development Commands" section in each installed project drives all quality gates.
- **`/finish` branches on explicit PR state** before cleanup. Merged PRs complete the full close/cleanup/docs flow; auto-merge-pending and manual-merge-needed PRs preserve the issue and PR branch; closed-unmerged PRs abort finish cleanly.
- **`/finish` decides docs sync mechanically** from the PR diff: every PR requires CHANGELOG.md; command or installer changes also require README.md; command or agent changes also require CLAUDE.md. If any required doc is missing, `/finish` runs `/update-docs` and logs the missing files.
- **Repo detection** is done via `git remote get-url origin` — commands never hardcode repo references.
- **orient.md is project-specific** — it is excluded from symlinking. If the target project doesn't have one, install.sh scaffolds a template from `templates/orient.md` that must be customized. The shipped generic `/orient` covers install paths without install.sh (plugin, manual copy): on first run in an unprepared project it bootstraps the operating requirements — infers a Development Commands section from manifests and scaffolds a project orient — additively, never overwriting.
- **install.sh is idempotent** — it never overwrites existing files; re-running is safe.
- **Symlinks are relative** — agents link as `../../.hephaestus/.claude/agents/<name>`, commands as `../../.hephaestus/.claude/commands/<name>`.

## Agent Conventions

Five agent roles, stratified by least-privilege tool access. Coder is the only agent that can modify files (runs in `isolation: worktree` for safe parallel edits). Reviewer, tester, and explorer are read-only. Researcher has web access but no shell.

- Agents declare allowed tools and isolation mode in YAML frontmatter
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

**Git conflicts**: Before implementation, check for conflicts with the base branch. If conflicts exist, attempt rebase. If rebase fails, wind down cleanly — commit progress, create a draft PR with `[CONFLICT]` prefix, file a follow-up issue with the conflict details.

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
- After finishing an issue (Phase 4 of autopilot, post-/finish)
- After shipping a PR (even if not yet merged)
- After committing progress and filing follow-up issues
- Never mid-implementation with uncommitted changes

## Improving the Workflow

When the user gives feedback about how commands, agents, or workflows should behave, consider whether the improvement applies broadly across projects. If it does, persist it in the repo (CLAUDE.md or the relevant command/agent file) — not just in local memory. Local memory is per-machine; repo changes propagate to every project using hephaestus.

## Editing Guidelines

When modifying agents or commands:
- Preserve the YAML frontmatter format in agent files (name, description, tools, isolation)
- Edit canonical workflow specs in `.ai/workflows/`, not generated `.claude/commands/` adapters.
- Do not hand-edit `.opencode/commands/` or `.opencode/agents/`; regenerate them with `./scripts/sync-opencode-adapters.sh`.
- Preserve the `$ARGUMENTS` placeholder in workflows that receive user input at invocation.
- Retry limits are defined in "Core Workflow Pattern" above — commands must reference them, not hardcode
- Commands that delegate to subagents should specify which agent type to use and what structured output to expect
- Run `./scripts/sync-agent-adapters.sh --check` before shipping adapter changes
- Run `./scripts/sync-opencode-adapters.sh --check` before shipping OpenCode adapter changes
- **No bloat**: Replacements must be at least as concise as the original. If the new text is longer without adding information, tighten it. Bloat and drift are the enemies of excellence.

**Workflow metadata** — every `.ai/workflows/*.md` declares its dependencies in frontmatter:
- `requires: agent1, agent2` lists subagents the workflow launches directly. Use `requires: none` if it launches none.
- `chains: /cmd-a, /cmd-b` lists other workflows it invokes. Use `chains: none` if it chains none. Generated Claude adapters render this as `<!-- requires: -->` and `<!-- chains: -->` headers.

Composition rule: if you find yourself copying procedure from `/foo` into `/bar`, replace with a chain instead. Duplicate procedures drift.

## What Target Projects Must Provide

These are NOT in this repo — each installed project owns them:
- `.claude/commands/orient.md` — project-specific context (scaffolded by install.sh, must be customized)
- `.opencode/commands/orient.md` — OpenCode project-specific context (scaffolded by install.sh, must be customized if using OpenCode)
- `.claude/hooks/` — lint/test hooks for the project's tech stack
- `CLAUDE.md` with a "Development Commands" section (test, lint, build commands)
- `AGENTS.md` — index of available local and shared agents (scaffolded by install.sh from `templates/AGENTS.md`)
- `.claude/settings.local.json` — project-specific config

## Communication rules

**Never end a response with an indirect pointer to a question.** Banned closers: "Want me to do that?", "Give me the ok and I'll...", "Let's get started?", "Let me know if...", "Sound good?", "Should I proceed?". Either ask the explicit question (with options) or just take the action — no vague closing prompts.
