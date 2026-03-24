# hephaestus

The machine that builds the machine.

An autonomous issue-to-ship delivery system for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex](https://openai.com/index/introducing-codex/), distributed as a git submodule. Install once, share across every project. Fire-and-forget with quality gates — not the usual interactive prompt-approve-repeat loop. Works with any tech stack: hephaestus discovers your test, lint, and build commands from your project's `CLAUDE.md`.

## What happens when you run `/autopilot`

Open a GitHub issue. Run `/autopilot`. Get a merged PR.

Here's what actually happens behind the scenes: hephaestus reads the issue, explores the relevant codebase (parallel explorer subagents across subsystems), then enters a plan-critique loop — building an implementation plan, adversarially critiquing it, and refining until the plan is sound (up to 3 iterations). It implements the plan using parallel coder subagents in isolated worktrees, then runs a pre-ship code review (security, architecture, test adequacy, CLAUDE.md compliance). Tests, lint, and build run as parallel quality gates. It updates the CHANGELOG, creates a PR with a quality-gate checklist, enables squash auto-merge, closes the issue, and deletes merged branches.

When tests fail, it analyzes the root cause and retries with a revised plan (up to 2 full plan-implement-test cycles). When code review finds issues, it fixes and re-submits (up to 3 iterations). When retry limits are exhausted, it commits progress, creates a draft PR with a descriptive prefix (`[FAILING]`, `[BLOCKED]`, `[WIP]`), files a follow-up issue with context for the next session, and winds down cleanly. It never leaves your repo in a dirty state — every session ends with committed code, pushed branches, and breadcrumbs for what remains.

If the issue queue is empty, it self-triages: scans for TODOs, inconsistencies, and gaps, creates the highest-impact issue, and continues the pipeline.

## Getting started

### Install

From the hephaestus repo directory:

```bash
./install.sh /path/to/your/project
```

This adds hephaestus as a `.hephaestus` git submodule, creates symlinks into `.claude/agents/`, `.claude/commands/`, and `.codex/skills/`, and never overwrites existing files. Idempotent — safe to re-run.

### First run

```bash
/autopilot                 # full autonomous pipeline — pick issue, deliver, ship
/start-issue 42            # plan-critique-implement cycle for a specific issue
```

Create your own `.claude/commands/orient.md` for project-specific cold-start context (orient.md is excluded from install — each project owns its own).

### Update

```bash
.hephaestus/update.sh
# or manually: git submodule update --remote .hephaestus
```

Pulls the latest and re-runs `install.sh` to pick up new agents, commands, and skills.

## What's included

### Commands

| Command | What it does |
|---|---|
| `/autopilot` | Full autonomous pipeline: pick issue (or self-triage), plan, implement, test, ship, finish |
| `/start-issue` | Plan-critique-implement cycle for a specific issue, ending ready for `/ship` |
| `/ship` | Pre-ship critique gate, parallel quality gates, CHANGELOG, PR, squash auto-merge |
| `/finish` | Close issue, delete branches (local + remote), file follow-ups, session summary |
| `/test-issue` | Run quality gates via tester subagents, verify acceptance criteria |
| `/refactor` | Analyze, plan, implement, review, ship — with before/after metrics |
| `/research` | Parallel researcher subagents per facet, synthesized findings with confidence levels |
| `/critique` | Adversarial review — code mode (via reviewer) or general/strategy mode |
| `/create-issue` | Research-backed issue creation with labels and testable acceptance criteria |
| `/update-docs` | Update CLAUDE.md, CHANGELOG, and README after recent work |
| `/orient` | Cold-session startup: repo context, open issues, recent history, next action |

The `/autopilot` pipeline covers the same phases as `/start-issue`, `/ship`, `/finish`, and `/update-docs`. Each command also works standalone.

### Agents

| Agent | Isolation | Role |
|---|---|---|
| coder | worktree | Focused implementation. Multiple coders run in parallel for independent changes. |
| reviewer | — | Security, architecture, test adequacy, CLAUDE.md compliance. Verdicts: PASS / PASS WITH CHANGES / FAIL. |
| tester | — | Runs project-specific quality gates (test, lint, build). Structured pass/fail output. |
| explorer | — | Read-only codebase investigation. Multiple explorers parallelize across subsystems. |
| researcher | — | Web research with prompt injection protection. Multiple researchers parallelize across facets. |

All agents declare tools and isolation in YAML frontmatter. All return structured output — never raw verbose logs.

Codex equivalents exist for the core workflows: **orchestrator**, **critic**, and **research-issue** skills in `.codex/skills/`.

## The pipeline

```
Orient → Plan → Critique (×3) → Implement → Review (×3) → Test (×2) → Ship → Finish
```

| Phase | What happens | On failure |
|---|---|---|
| **Orient** | Git status, recent history, repo detection via `git remote get-url origin` | — |
| **Plan** | Break issue into steps, identify parallel vs. sequential tasks | — |
| **Critique** | Adversarial self-critique of the plan (max 3 iterations) | NEEDS REFINEMENT: proceed with caveats. RETHINK: implement sound subset, file follow-up. |
| **Implement** | Parallel coder subagents in worktree isolation | Blocked task: try one alternative, then skip with TODO comment |
| **Review** | Reviewer subagent: security, architecture, tests, compliance (max 3 iterations) | After 3 FAILs: draft PR with `[BLOCKED]` prefix, file follow-up issue |
| **Test** | Quality gates from project's CLAUDE.md — test, lint, build (max 2 cycles) | After 2 failures: draft PR with `[FAILING]` prefix, file follow-up issue |
| **Ship** | Update CHANGELOG, push, create PR with quality-gate checklist, squash auto-merge | Auto-merge unavailable: leave PR open, note in summary |
| **Finish** | Close issue, delete branches (local + remote), file follow-ups, print summary | — |

## Headless operation

`loop.sh` runs `/autopilot` in a fresh Claude session on a configurable interval. Each session gets the latest model capabilities and a clean context window — no context bloat across runs.

```bash
# Run autopilot every 30 minutes in the background
nohup ./.hephaestus/loop.sh 30 autopilot.log &
```

Sessions run with `--dangerously-skip-permissions` for unattended operation — review your project's `settings.local.json` to control what's allowed. Safety: project-scoped lockfile prevents concurrent instances, numeric interval validation, survives individual session failures, graceful shutdown on SIGINT/SIGTERM.

## What your project provides

These are **not** in hephaestus — each project owns them:

| File | Why project-specific |
|---|---|
| `.claude/commands/orient.md` | References your project's repos, structure, and priorities |
| `.claude/hooks/` | Lint/test commands vary by tech stack |
| `AGENTS.md` | Skill index referencing local + shared skill paths |
| `.codex/settings.local.json` | Skill paths and memory config |
| `.claude/settings.local.json` | Hook paths and allowed permissions |
| `CLAUDE.md` "Development Commands" | Source of truth for all quality gates (test, lint, build) |

### After installing, set up

1. **`.claude/commands/orient.md`** — project-specific session startup (git status, open issues, changelog, next action)
2. **`.claude/hooks/lint-on-commit.sh`** — run your lint command before commits
3. **`.claude/hooks/protect-files.sh`** — block accidental edits to `.env`, lock files, etc.
4. **`AGENTS.md`** — skill index listing local + shared skills
5. **`CLAUDE.md` "Development Commands" section** — this is the source of truth for all quality gates. Keep it up to date and every shared command automatically uses the right test, lint, and build commands for your project.
