# hephaestus

**The machine that builds the machine.**

A git submodule that gives [Claude Code](https://docs.anthropic.com/en/docs/claude-code) a complete delivery workflow — from GitHub issue to merged PR, hands-off. It plans its own work, critiques its own plans, writes code in parallel, reviews what it wrote, runs your tests, and ships. When things break, it retries with a different approach or winds down cleanly. When there's nothing to do, it finds work. When you improve the workflow, those improvements propagate to every project. Install it once, share it everywhere.

```
/autopilot
```

```
reads issue → explores codebase → plans → critiques plan → refines
→ implements (parallel) → code review → tests → PR → merge → cleanup
```

That's the whole thing. One command. It figures out the rest.

---

## Why

Hephaestus is built on three ideas: **simplicity** — one command to deliver, one file to configure; **self-improvement** — it critiques its own plans, reviews its own code, finds its own work when idle, and evolves as you use it; **autonomy** — it runs without intervention, recovers from failure, and only stops for irreversible risk. Point it at an issue and walk away.

---

## Get started

```bash
# Install — handles the submodule, don't git submodule add manually
./install.sh /path/to/your/project
```

This adds the `.hephaestus` submodule, symlinks commands and agents, scaffolds an `orient.md` template, validates your `CLAUDE.md`, and runs a health check. Safe to re-run.

```bash
# Append hephaestus sections to your CLAUDE.md (dev commands, command reference, agents)
cat .hephaestus/templates/CLAUDE.md.snippet >> CLAUDE.md

# Deliver an issue
/autopilot                 # picks highest-priority issue, does everything
/start-issue 42            # work a specific issue

# Run unattended on a loop
nohup ./.hephaestus/loop.sh 30 autopilot.log &
```

**Manage the install:**

| | |
|---|---|
| `install.sh --audit` | Preview what would change without modifying anything |
| `install.sh --force` | Replace existing files with hephaestus versions |
| `install.sh --clean` | Remove dangling symlinks after upstream renames |
| `/update-hephaestus` | Pull latest, re-install, show what changed |
| `.hephaestus/uninstall.sh` | Clean removal — only removes hephaestus symlinks |

---

## How it works

### The pipeline

Every delivery runs the same loop:

1. **Orient** — read the issue, explore relevant code, understand what's needed
2. **Plan** — break the work into steps, identify what can run in parallel
3. **Critique** — adversarially tear apart its own plan, refine, repeat (up to 3 rounds)
4. **Implement** — parallel coder agents in isolated worktrees, one commit per logical unit
5. **Review** — security, architecture, test coverage, convention compliance (up to 3 rounds)
6. **Test** — your test/lint/build commands from `CLAUDE.md` (up to 2 full retry cycles)
7. **Ship** — CHANGELOG, PR with quality checklist, squash auto-merge
8. **Finish** — close issue, delete branches, file follow-ups for anything unresolved

### When things fail

It doesn't stop and ask. It tries a different approach. If retries are exhausted:
- Commits everything it has
- Opens a draft PR (`[FAILING]`, `[BLOCKED]`, or `[WIP]`) with what went wrong
- Files a follow-up issue with context for the next run
- Leaves the repo clean

### When there's nothing to do

`/autopilot` with an empty issue queue runs self-triage — scans for TODOs, code quality gaps, and inconsistencies, creates the highest-impact issue, and continues.

### Headless mode

`loop.sh` runs `/autopilot` in a fresh Claude session every N minutes. Clean context each time — no bloat. Project-scoped lockfile prevents overlap. Survives crashes. Runs with `--dangerously-skip-permissions` — scope what's allowed in your `settings.local.json`.

---

## Commands

**Delivery**

| | |
|---|---|
| `/autopilot` | Full pipeline — pick issue, plan, implement, test, ship, finish |
| `/start-issue 42` | Plan-critique-implement for one issue |
| `/ship` | Code review → quality gates → CHANGELOG → PR → auto-merge |
| `/finish` | Close issue, clean branches, file follow-ups |
| `/refactor` | Autonomous refactoring with review gate and before/after metrics |

**Research & quality**

| | |
|---|---|
| `/research` | Parallel web research, synthesized findings with confidence levels |
| `/critique` | Adversarial review — code or strategy |
| `/create-issue` | Codebase-informed issue creation with labels and acceptance criteria |
| `/test-issue` | Run quality gates, verify acceptance criteria |
| `/update-docs` | Sync CLAUDE.md, CHANGELOG, README with recent work |
| `/update-hephaestus` | Pull latest, re-install, show what changed |
| `/orient` | Cold-start: repo state, open issues, next action |

---

## Agents

Five specialized agents that commands orchestrate:

| | |
|---|---|
| **coder** | Writes code in isolated worktrees. Runs in parallel for independent tasks. |
| **reviewer** | Security, architecture, test adequacy, convention compliance. PASS / PASS WITH CHANGES / FAIL. |
| **tester** | Runs your test/lint/build and returns structured results. |
| **explorer** | Read-only codebase investigation. Fans out across subsystems in parallel. |
| **researcher** | Web search with source cross-referencing and injection protection. |

---

## Adopting in an existing project

If your project already has `.claude/commands/` or agents, run the audit first:

```bash
./install.sh --audit /path/to/your/project
```

This shows what would change — new symlinks, conflicts with your existing files (with line counts), and name collisions — without modifying anything.

**When you have overlapping commands** (e.g., your own `/ship`):

1. Compare: `diff .claude/commands/ship.md .hephaestus/.claude/commands/ship.md`
2. If your version has project-specific quality checks, move that logic into your `CLAUDE.md` "Development Commands" section — hephaestus reads it from there
3. Replace: `rm .claude/commands/ship.md && .hephaestus/install.sh .` — or use `--force` to replace all at once

The key idea: **hephaestus handles orchestration, your `CLAUDE.md` handles project-specific configuration.** Move test/lint/build commands and project constraints into `CLAUDE.md`, then let hephaestus commands take over the workflow.

To remove hephaestus later: `.hephaestus/uninstall.sh` removes only hephaestus symlinks and the submodule, keeps your project-specific files.

---

## Forking and customization

Fork hephaestus to customize commands for your org while still pulling upstream updates.

**Safe to modify in a fork** — these won't cause merge conflicts with upstream:
- `templates/` — customize the orient.md and CLAUDE.md scaffolds for your org's conventions
- `VERSION` — your fork's version track

**Will conflict if modified** — these are actively developed upstream:
- `.claude/commands/` and `.claude/agents/` — the core workflow files
- `install.sh`, `update.sh`, `uninstall.sh` — the install tooling

**Pulling upstream updates into a fork:**

```bash
git remote add upstream https://github.com/amurshak/hephaestus.git
git fetch upstream
git merge upstream/master
```

install.sh works with any submodule URL — forks install identically to upstream.

---

## Your project's setup

Hephaestus reads your project's `CLAUDE.md` — specifically the "Development Commands" section. That's where it learns what to test, lint, and build. The fastest way to set this up:

```bash
cat .hephaestus/templates/CLAUDE.md.snippet >> CLAUDE.md
```

Then replace the placeholder commands with your actual test/lint/build commands.

install.sh scaffolds `orient.md` automatically. Customize it with your project's repos, structure, and priorities.

Optional but recommended:

| | |
|---|---|
| `.claude/hooks/lint-on-commit.sh` | Your lint command, before every commit |
| `.claude/hooks/protect-files.sh` | Block edits to `.env`, lock files, secrets |
| `AGENTS.md` | Index of local + shared agents |
| `.claude/settings.local.json` | Permissions and hook paths |
