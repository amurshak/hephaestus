# hephaestus

**The machine that builds the machine.**

Turn GitHub issues into merged PRs — autonomously. One command, no babysitting.

```
you:  /autopilot
      ↓
      reads the issue
      ↓
      explores the codebase (parallel agents)
      ↓
      plans → critiques its own plan → refines (up to 3 rounds)
      ↓
      implements (parallel coders in isolated worktrees)
      ↓
      reviews its own code (security, architecture, test coverage)
      ↓
      runs your tests, lint, and build
      ↓
      updates CHANGELOG, opens PR, squash-merges
      ↓
      closes the issue, cleans up branches
done.
```

If something fails along the way, it doesn't just stop. It retries with a different approach, and if that's exhausted, it commits what it has, opens a draft PR explaining what went wrong, files a follow-up issue, and leaves your repo clean. Every time.

No open issues? It self-triages — scans the codebase for TODOs, inconsistencies, and gaps, creates an issue, and gets to work.

## Why this exists

Most AI coding setups are interactive. You prompt, it asks a question, you approve, it writes some code, you review, repeat. That works for exploration, but it doesn't scale.

Hephaestus is the other mode: **fire-and-forget with quality gates**. You point it at an issue and walk away. It handles the full loop — planning, implementation, code review, testing, shipping — with built-in retry logic and clean failure handling. The same workflow works across every project because it's distributed as a **git submodule** and discovers your stack from your `CLAUDE.md`.

## Get started in 60 seconds

```bash
# 1. Install into your project (creates submodule + symlinks, never overwrites existing files)
./install.sh /path/to/your/project

# 2. Ship an issue
/autopilot                 # picks the highest-priority issue and delivers it
/start-issue 42            # or target a specific issue

# 3. Or run it on a loop, unattended
nohup ./.hephaestus/loop.sh 30 autopilot.log &   # every 30 min, fresh session each time
```

Update anytime: `.hephaestus/update.sh` pulls the latest and adds new agents/commands automatically.

## What you get

### Delivery commands

| | |
|---|---|
| **`/autopilot`** | The full pipeline. Picks an issue (or self-triages), plans, implements, tests, ships, finishes. |
| **`/start-issue 42`** | Plan-critique-implement for one issue. Pairs with `/ship` when you're ready. |
| **`/ship`** | Code review gate → quality gates → CHANGELOG → PR → auto-merge. |
| **`/finish`** | Close issue, delete branches, file follow-ups. |
| **`/refactor`** | Autonomous refactoring with before/after metrics and review gate. |

### Research & quality commands

| | |
|---|---|
| **`/research`** | Parallel web research across facets, synthesized with confidence levels. |
| **`/critique`** | Adversarial review — works on code (via reviewer agent) or strategy/plans. |
| **`/create-issue`** | Explores the codebase first, then creates a well-scoped issue with labels. |
| **`/test-issue`** | Runs your full quality gate suite and verifies acceptance criteria. |
| **`/update-docs`** | Keeps CLAUDE.md, CHANGELOG, and README in sync after shipping. |
| **`/orient`** | Cold-start context: repo state, open issues, what to do next. |

### Agents under the hood

| Agent | What it does |
|---|---|
| **coder** | Writes code in an isolated worktree. Multiple coders run in parallel for independent tasks. |
| **reviewer** | Adversarial code review: security, architecture, test coverage, convention compliance. |
| **tester** | Runs your project's test/lint/build commands and returns structured results. |
| **explorer** | Read-only codebase analysis. Multiple explorers fan out across subsystems simultaneously. |
| **researcher** | Web research with source cross-referencing and prompt injection protection. |

## The pipeline in detail

```
Orient → Plan → Critique (×3) → Implement → Review (×3) → Test (×2) → Ship → Finish
```

Every phase has a failure mode that keeps things moving:

- **Plan-critique loop** — Up to 3 rounds of adversarial self-critique. If the plan still isn't sound, it implements the defensible parts and files a follow-up for the rest.
- **Implementation** — Parallel coder agents in isolated worktrees. If one is blocked, it tries an alternative, then skips with a TODO and continues.
- **Code review** — Reviewer agent checks security, architecture, tests, and conventions. Up to 3 fix-and-resubmit cycles. If still failing: `[BLOCKED]` draft PR + follow-up issue.
- **Testing** — Runs your quality gates (from your project's `CLAUDE.md`). Up to 2 full plan-implement-test cycles. If still failing: `[FAILING]` draft PR with root-cause analysis.
- **Shipping** — CHANGELOG update, PR with quality-gate checklist, squash auto-merge. If auto-merge isn't available, it leaves the PR open and tells you.

## Headless mode

`loop.sh` runs `/autopilot` in a fresh Claude session on a repeating interval. Each run gets a clean context window — no bloat from previous sessions.

```bash
nohup ./.hephaestus/loop.sh 30 autopilot.log &
```

Runs with `--dangerously-skip-permissions` for unattended operation — configure allowed actions in your project's `settings.local.json`. Built-in safety: project-scoped lockfile, survives session crashes, clean shutdown on SIGINT/SIGTERM.

## Configuring your project

Hephaestus reads your project — you don't configure hephaestus. The key file is your **`CLAUDE.md`**: its "Development Commands" section tells every agent what test, lint, and build commands to run. Keep that up to date and everything works.

After installing, create these project-specific files:

| File | Purpose |
|---|---|
| `CLAUDE.md` with "Development Commands" | Source of truth for all quality gates |
| `.claude/commands/orient.md` | Your project's repos, structure, priorities |
| `.claude/hooks/lint-on-commit.sh` | Your lint command, run before every commit |
| `.claude/hooks/protect-files.sh` | Block edits to `.env`, lock files, secrets |
| `AGENTS.md` | Index of available local + shared agents |
| `.claude/settings.local.json` | Allowed permissions and hook paths |

Codex equivalents (**orchestrator**, **critic**, **research-issue**) live in `.codex/skills/` for projects using OpenAI Codex.
