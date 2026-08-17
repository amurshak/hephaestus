Orient in the current project. On first contact with an unprepared project, set up the workflow's operating requirements, then orient. Run autonomously.

<!-- requires: none -->
<!-- chains: /worktrees -->
<!-- generated from .ai/workflows/orient.md; do not edit directly -->

> **Cursor:** run from the project root that contains `.cursor/`. Invoke nested workflows as slash commands (/worktrees) so their full templates load — do not paraphrase. Delegate to the subagents in `.cursor/agents/`; they share one working tree, so serialize file-modifying tasks.


> Each project should own its orient command — `install.sh` scaffolds one from `templates/orient.md` and never symlinks this file. This shipped version is the generic fallback (plugin and manual-copy installs): it bootstraps missing setup, then orients.

## Step 1 — Detect repo

`git remote get-url origin` — derive `<owner>/<repo>` for all `gh` commands. If there is no remote, work local-only and skip issue listing.

## Step 2 — Setup check

Hephaestus is an adjunct to the host codebase. Verify its operating requirements and bootstrap what's missing — all writes are additive; never overwrite or modify existing content beyond appending a missing section.

Skip items 1–2 when the repo *defines* these requirements rather than consuming them — the workflow source itself, recognised by `.ai/workflows/` alongside a `scripts/sync-*-adapters.sh` generator. Read its CONTRIBUTING.md instead. Item 3 still applies.

1. **CLAUDE.md with a "Development Commands" section** (test/lint/build — this drives every quality gate). If missing: derive the section from commands the repo already documents (CLAUDE.md under any heading, AGENTS.md, README, CI config); fall back to inferring from project manifests (package.json, Makefile, pyproject.toml, go.mod, etc.) only when nothing is documented. Create CLAUDE.md or append the section, marked `<!-- inferred by hephaestus — verify these commands -->` on its own line directly under the heading — `install.sh --interactive` finds and removes it there once a human confirms the commands.
2. **Project-specific orient** at `.claude/commands/orient.md` (also `.opencode/commands/orient.md` if the project has a `.opencode/` directory). For each that is missing: scaffold one containing the detected repo, a one-paragraph structure summary from a quick scan, the Development Commands from step 1, and find-work instructions — then note it should be customized as the project evolves.
3. **`gh` CLI authenticated** (`gh auth status`). Not fixable autonomously — if missing or unauthenticated, report it and continue local-only.

Retry limits and the wind-down convention are not bootstrapped: the commands carry them. A project only needs a `## Workflow Rules` section if it wants values other than the defaults.

Report every bootstrap action taken. Leave bootstrap writes uncommitted so the user can verify the inferred commands — say so in the report. On an already-prepared project this step is a silent no-op.

## Step 3 — Orient

- Read CLAUDE.md and the project orient — if a project-specific orient exists, prefer its guidance over this file.
- Sync state: `git fetch --prune origin`, then `git status -sb` and `git log --oneline -5`.
- Reap deferred worktrees — in the primary checkout only (`git rev-parse --git-dir` equals `--git-common-dir`). If `git worktree list` shows any linked worktree, run `/worktrees cleanup`. `/finish` cannot remove the worktree it runs in, so finished ones accumulate until a primary session sweeps them.
- Find work: `gh issue list --state open --repo <detected-repo>` and `gh pr list --state open --repo <detected-repo>`. If no open issues, self-triage: scan for TODOs, failing checks, doc drift, missing tests.

## Step 4 — Report

Current branch and sync state, setup actions taken (if any), open issues/PRs, and the recommended next action.

## Next action

Run `/autopilot` — it picks the highest-priority open issue or self-triages if the queue is empty. Or `/start-issue <#>` for a specific issue.
