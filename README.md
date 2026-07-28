# hephaestus

[![tests](https://github.com/amurshak/hephaestus/actions/workflows/tests.yml/badge.svg)](https://github.com/amurshak/hephaestus/actions/workflows/tests.yml) [![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**A generic software development workflow pattern for AI coding agents.**

Software delivery follows the same loop in every project: understand the problem, plan the work, validate the plan, execute, verify, ship, clean up.
Hephaestus is an opinionated instantiation of this loop as an agentic software development workflow pattern that answers the question:

**what is the minimum composable workflow that can deliver arbitrary software changes through an AI coding assistant?** 

```
/orient → /create-issue → /start-issue → ⟨implementation⟩ → /ship → /finish
```

Or run the whole loop as one command:

```
/autopilot
```

The core is a set of harness-neutral workflow specs (`.ai/workflows/`) and agent definitions — plain markdown files. Per-harness support is *generated adapters* from those specs: Claude Code and [OpenCode](https://opencode.ai) adapters ship today; new harnesses are a ~200-line generator script away.

## Install

In Claude Code:

```
/plugin marketplace add amurshak/hephaestus
/plugin install heph@hephaestus
```

That's it — commands appear under `/heph:` (`/heph:autopilot`, `/heph:ship`, …). For OpenCode, manual copy/symlink, or the git-submodule install (headless mode, forking), see [Get started](#get-started).

**Requirements:** [Claude Code](https://claude.com/claude-code) or [OpenCode](https://opencode.ai) · [`gh` CLI](https://cli.github.com) authenticated (workflows drive GitHub issues and PRs) · git.

Hephaestus is an OODA loop — observe, orient, decide, act — for software. Boyd designed OODA for fighter pilots: cycle faster than the opponent and you win. Software has the opposite problem. Shipping too fast costs more than slowing down. So this loop puts most of its weight on Orient. Plans face adversarial review before code begins. Code faces adversarial review before it ships. Retries are bounded so nothing spirals.

The core of Hephaestus is composed of five commands spread across eight internal phases. These are the fundamental process primitives of the development workflow. The system has five agent roles. Its memory lives in places that already exist: git history, GitHub issues, PRs, project management tools, project documentation. No opaque internal state. When retries exhaust, the system degrades into artifacts (draft PRs, follow-up issues, commits) the next session or a human can resume from.

---

## Contents

- [The pattern](#the-pattern)
- [OODA loop analysis](#ooda-loop-analysis)
- [Design choices](#design-choices)
- [Composition](#composition)
- [The critique system](#the-critique-system)
- [Memory through external systems](#memory-through-external-systems)
- [Get started](#get-started)
- [Your project's setup](#your-projects-setup)
- [Submodule install](#submodule-install-for-headless-mode-and-forking)
- [Contributing](#contributing)
- [License](#license)

---

## The pattern

### Phases

| # | Phase | What happens |
|---|-------|-------------|
| 1 | **Orient** | Read the issue, explore relevant code, understand what's needed |
| 2 | **Plan** | Break work into steps, identify what can run in parallel |
| 3 | **Critique** | Adversarially evaluate the plan — refine or rethink (up to 3 rounds) |
| 4 | **Implement** | Parallel coder agents in isolated worktrees, one commit per logical unit |
| 5 | **Review** | Security, architecture, test coverage, convention compliance (up to 3 rounds) |
| 6 | **Test** | Quality gates from the project's `CLAUDE.md` (up to 2 full retry cycles) |
| 7 | **Ship** | CHANGELOG, PR with quality checklist, squash auto-merge |
| 8 | **Finish** | Branch on PR state, close shipped issues, clean branches, file follow-ups, and run or skip docs sync by a deterministic PR-diff rule |

### Agents

Five roles, stratified by capability through least-privilege tool access:

| Agent | Edit tools | Web access | Shell access | Isolation |
|-------|------------|------------|-------------|-----------|
| **coder** | Yes | No | Yes | worktree |
| **reviewer** | No | No | Yes (instructed read-only) | none |
| **tester** | No | No | Yes (instructed read-only) | none |
| **explorer** | No | No | Yes (instructed read-only) | none |
| **researcher** | No | Yes | No | none |

The coder is the only agent granted edit tools; it runs in an isolated git worktree so parallel coders don't interfere. The reviewer, tester, and explorer have no edit tools and are instructed to treat their shell as read-only — a convention, not a sandbox, since an unrestricted shell can write. The researcher can access the web but has no shell at all. Tool grants bound most of the blast radius; the shell-bearing agents rely on instruction for the rest.

Every agent returns structured output — typed fields and verdicts, not prose. This turns agent invocations into function calls the orchestrating command can branch on.

---

## OODA loop analysis

The pipeline maps onto Boyd's OODA loop (Observe → Orient → Decide → Act) with structural parallels and deliberate divergences.

### Where they align

| OODA | Hephaestus | Correspondence |
|------|------------|----------------|
| **Observe** | Orient phase — read issue, explore codebase, git status | Gathering raw information about the environment |
| **Orient** | Plan + critique loop | Synthesizing observations into a mental model; the critique tests whether the orientation is sound |
| **Decide** | Critique verdict + task decomposition | The commitment to a course of action |
| **Act** | Implement → review → test → ship | Execution with feedback loops that can trigger re-orientation |

The critique gate is the most interesting correspondence. Boyd argued Orient is the critical phase — quality of orientation determines everything downstream. Hephaestus fortifies it with mandatory adversarial review: the reviewer agent attacks the plan before code is written, then attacks the code before it ships. Two passes exist solely to break orientation.

### Where they diverge

**OODA is continuous; hephaestus is phased.** Boyd's loop has no discrete boundaries. Hephaestus imposes explicit phase gates — you don't implement until critique passes, you don't ship until tests pass. In software delivery, premature action has outsized downside. The phased structure sacrifices tempo for correctness.

**OODA has implicit feedback; hephaestus has explicit retry loops.** Each OODA cycle incorporates results of the previous one naturally. Hephaestus makes feedback loops explicit and bounded (3 plan-critique, 3 code-review, 2 test-fix). Without bounds, an autonomous system could loop forever. The retry limits are a tempo governor that forces graceful degradation.

**OODA optimizes for tempo; hephaestus optimizes for correctness.** Boyd's insight was that faster cycles create advantage while the opponent is still orienting. Hephaestus inverts it: the "opponent" is complexity and entropy, and each `act` is a discrete artifact (a PR), not a continuous decision stream. Slow critique gates are affordable when each output is durable. Shipping a bug costs more than waiting.

**OODA has no wind-down state.** Boyd's loop assumes continuous operation. Hephaestus adds a failure-mode state machine: when retries exhaust, the system transitions to clean shutdown that preserves progress and creates breadcrumbs. Sessions have finite context and finite reliability — the system must stop gracefully at any point.

**Nested loops.** Hephaestus nests OODA-like cycles within the larger pipeline. The test-fix cycle is its own observe-orient-decide-act loop. The pre-ship critique is another. This fractal structure — loops within loops, each with termination conditions — is more complex than Boyd's single-level model.

### The deeper correspondence

Boyd argued that speed of the OODA loop matters less than quality of orientation. An entity with a superior mental model makes better decisions even at lower tempo. Hephaestus embodies this: explorer agents fan out in parallel to build context, the critique gate stress-tests the plan across seven dimensions (logic, assumptions, completeness, trade-offs, evidence, second-order effects, timing), and persistent failures trigger RETHINK — forcing the system to rebuild orientation from scratch rather than iterating on a flawed one. Designed to be right before fast.

---

## Design choices

### Minimum viable command set

Thirteen commands, but the delivery spine is `/autopilot` and the three commands it chains — `start-issue`, `ship`, `finish` — with orientation run inline as its first phase. The rest are support functions that pipeline phases call or convenience entry points that start at a different phase.

**Delivery**

| | |
|---|---|
| `/autopilot` | Full pipeline — pick issue, plan, implement, test, ship, finish |
| `/start-issue 42` | Plan-critique-implement for one issue |
| `/ship` | Code review → quality gates → CHANGELOG → PR → auto-merge |
| `/finish` | Close issue, clean branches, file follow-ups |
| `/refactor` | Autonomous refactoring with review gate and before/after metrics |
| `/worktrees` | Parallel multi-session orchestration — reap finished worktrees, wave-plan non-conflicting issues, spawn a seeded session per issue |

**Support**

| | |
|---|---|
| `/research` | Parallel web research, synthesized findings with confidence levels |
| `/critique` | Adversarial review — code or strategy |
| `/create-issue` | Codebase-informed issue creation with labels and acceptance criteria |
| `/test-issue` | Run quality gates, verify acceptance criteria |
| `/update-docs` | Sync CLAUDE.md, CHANGELOG, README with recent work |
| `/update-hephaestus` | Pull latest, re-install, show what changed |
| `/orient` | Cold-start: repo state, open issues, next action |

### Separation of orchestration from configuration

Hephaestus owns the workflow — what order things happen, when to retry, when to stop. Canonical workflows live in `.ai/workflows/` with frontmatter for `name`, `requires`, and `chains`; `.claude/commands/` and `.opencode/commands/` are generated adapters checked by `scripts/sync-agent-adapters.sh --check` and `scripts/sync-opencode-adapters.sh --check`. The target project owns the specifics — what test command to run, what lint rules to enforce. Commands read the target's `CLAUDE.md` at runtime to discover quality gates. The only project-specific command hephaestus ever creates is a scaffold for `orient.md`, which it then refuses to overwrite.

### Parallelization at three levels

**Within a session**: multiple coder agents work in parallel worktrees for independent tasks; multiple explorer and researcher agents fan out across subsystems simultaneously. **Across issues**: `/worktrees` surveys and reaps finished worktrees, plans a wave of mutually non-conflicting issues under a configurable cap (declare contention hotspots in a `## Worktrees` section of CLAUDE.md), creates a sibling worktree per issue with config propagated and env files single-sourced, and spawns a seeded Claude Code session in each. **Across time**: `loop.sh` runs `/autopilot` in fresh sessions on a timer, each picking up the next issue.

### Deterministic failure modes

Every command specifies what happens when things go wrong — not as afterthoughts but as first-class workflow states. Retry exhaustion produces a draft PR with a descriptive prefix (`[WIP]`, `[BLOCKED]`, `[FAILING]`), a follow-up issue with context, and a clean repo. The system degrades into artifacts the next run or a human can pick up. It never blocks on input and never leaves the repo undefined.

---

## Composition

Each canonical workflow declares what it directly uses (`requires:` for agents) and what it chains (`chains:` for other workflows). The generated Claude adapters expose the same metadata as command headers. `/autopilot` is the most composed:

```
/autopilot                          (requires: explorer)
├── Phase 0  self-triage (inline)
├── Phase 1  orient (inline)
├── Phase 2  /start-issue           (requires: coder, explorer)
│            └── /test-issue        (requires: tester)
├── Phase 3  /ship                  (requires: tester)
│            └── /critique          (requires: reviewer)
└── Phase 4  /finish                (requires: none)
             └── /update-docs       (requires: none)
```

`/refactor` follows a parallel structure for refactoring work:

```
/refactor                           (requires: coder, explorer)
├── Phase 1  analysis (inline)
├── Phase 2  plan-critique (inline)
├── Phase 3  implement (inline)
├── Phase 4  /ship                  (requires: tester)
│            └── /critique          (requires: reviewer)
└── Phase 5  /finish                (requires: none)
             └── /update-docs       (requires: none)
```

**Why explicit composition.** Single source of truth: change `/critique`'s retry semantics once, and every command that chains `/critique` (currently `/ship`) inherits the change. Eliminates the duplicate gates earlier inline structures created — pre-ship critique used to run twice on `/autopilot` (once in autopilot itself, once again inside its inlined ship procedure).

**Subagents preserve main-context growth.** Verbose work — diff reads, file scans, intermediate reasoning — stays inside subagent context. Only structured output (verdicts, file lists) returns to the orchestrator. Chaining commands costs ~80 lines of prompt prose per chained command in main context; trivial vs. the duplication eliminated.

---

## The critique system

The critique system is the most heavily gated part of the pipeline. It operates at three levels:

**The `/critique` command** — a standalone, dual-mode entry point. Auto-detects whether to run code critique (uncommitted changes → reviewer agent) or general critique (strategy/plans → inline evaluation across logic, assumptions, completeness, trade-offs, evidence, second-order effects, timing).

**The reviewer agent** — the specialized code critic. Evaluates correctness, security (OWASP top 10), architecture, test adequacy, performance, error handling, and CLAUDE.md compliance. Read-only tool permissions enforce separation between critic and creator.

**Critique gates in the pipeline** — embedded checkpoints where execution pauses for adversarial evaluation:
- **Plan critique** (Phase 3): SOUND / NEEDS REFINEMENT / RETHINK
- **Code critique** (Phase 5): PASS / PASS WITH CHANGES / FAIL

On iteration 2+, the system distinguishes NEW blockers from PERSISTENT ones, and for persistent blockers asks whether the issue is fixable-with-a-different-strategy or a design-level-problem. Three rounds is the limit — if adversarial review hasn't resolved it by then, the problem requires human judgment or a fundamentally different approach, not more iteration.

The design reflects a core belief: the model's first plan is usually wrong in some way, and adversarial self-review catches errors that optimistic forward passes miss. The system spends its error budget on getting orientation right rather than recovering from poor execution.

---

## Memory through external systems

Hephaestus doesn't build its own memory. It uses existing systems as read/write stores for different types of state:

| System | Memory function | Written by |
|--------|----------------|------------|
| **GitHub Issues** | Work queue, context, acceptance criteria | `create-issue`, `finish` (follow-ups), retry exhaustion |
| **Git history** | Implementation decisions, change rationale | Commits from every delivery command |
| **GitHub PRs** | Review state, quality gate results, in-flight work | `ship`, retry exhaustion (draft PRs) |
| **CLAUDE.md** | Project configuration, quality gates, constraints | `update-docs`, `finish` docs check |
| **CHANGELOG.md** | Release history | `ship`, `update-docs` |
| **Draft PRs with prefixes** | Failure breadcrumbs (`[WIP]`, `[BLOCKED]`, `[FAILING]`) | Retry exhaustion handlers |
| **Follow-up issues** | Deferred work, unresolved problems | `finish`, retry exhaustion |

Each `loop.sh` invocation starts a fresh session with no memory of previous runs. Information persists between sessions only through these external artifacts. The system's state is always inspectable through standard developer tools (GitHub UI, git log, file contents), never locked in opaque internal state.

**The repo is the memory.** Git history records what was done and why. Issues record what needs to be done. PRs record work in flight. CLAUDE.md records how the project works. The system reads these on every run to reconstruct its orientation — stateless architecture where the "database" is the development environment itself.

**Failure state is encoded as artifacts.** When the system can't complete work, it creates a draft PR encoding the failure mode and a follow-up issue with context. The next run picks these up through the same issue-reading pipeline that handles human-created issues. Error recovery uses the same codepath as normal work intake.

Slack, Notion, and other documentation systems extend the principle — additional memory surfaces fed into future sessions through `orient.md` and `CLAUDE.md`.

---

## Get started

The workflows, commands, and agents are plain markdown files. Three ways to get them into a project, in order of friction:

### 1. Plugin (Claude Code)

```bash
/plugin marketplace add amurshak/hephaestus
/plugin install heph@hephaestus
```

Commands install under the `/heph:` namespace: `/heph:autopilot`, `/heph:ship`, `/heph:finish`, etc.

```bash
/heph:autopilot              # pick highest-priority issue, run end-to-end
/heph:start-issue 42         # work a specific issue
```

| | |
|---|---|
| `/plugin marketplace update hephaestus` | Pull the latest hephaestus |
| `/plugin uninstall heph`     | Remove the plugin |

### 2. Copy or symlink the files (any harness)

Zero machinery — vendor the files directly:

```bash
git clone https://github.com/amurshak/hephaestus.git
# Claude Code:
mkdir -p your-project/.claude
cp -R hephaestus/.claude/commands hephaestus/.claude/agents your-project/.claude/
# OpenCode:
mkdir -p your-project/.opencode
cp -R hephaestus/.opencode/commands hephaestus/.opencode/agents your-project/.opencode/
```

Commands run under bare names (`/autopilot`). No update story — re-copy when you want the latest. Symlink instead of copy if you keep a local clone and want updates via `git pull`.

### 3. Submodule (updatable vendoring, headless mode, forking)

```bash
git clone https://github.com/amurshak/hephaestus.git && cd hephaestus
./install.sh /path/to/your/project
```

One shared copy, relative symlinks into `.claude/` and `.opencode/`, `update.sh` for updates. Required for [headless mode](#headless-mode) (`loop.sh` runs Claude Code as a subprocess). Details in [Submodule install](#submodule-install-for-headless-mode-and-forking).

---

## Your project's setup

Hephaestus reads your project's `CLAUDE.md` — specifically the "Development Commands" section. That's where it learns what to test, lint, and build. Pull the snippet:

```bash
curl -s https://raw.githubusercontent.com/amurshak/hephaestus/master/templates/CLAUDE.md.snippet >> CLAUDE.md
```

Then replace the placeholder commands with your actual test/lint/build commands.

Hephaestus also ships an `/orient` command for cold-start context. The shipped version bootstraps an unprepared project on first run — it infers Development Commands from your manifests (marked for verification) and scaffolds a project-specific orient — then orients. Each project should own a customized `.claude/commands/orient.md` with its repos, structure, and priorities; pull the template to start from that instead:

```bash
mkdir -p .claude/commands
curl -s https://raw.githubusercontent.com/amurshak/hephaestus/master/templates/orient.md > .claude/commands/orient.md
```

Optional but recommended:

| | |
|---|---|
| `.claude/hooks/lint-on-commit.sh` | Your lint command, before every commit |
| `.claude/hooks/protect-files.sh` | Block edits to `.env`, lock files, secrets |
| `AGENTS.md` | Index of local + shared agents |
| `.claude/settings.local.json` | Permissions and hook paths |

Both hooks ship as ready-to-use templates — deterministic backstops for the prose gates (`protect-files.sh` works as-is; set `LINT_CMD` in `lint-on-commit.sh`):

```bash
mkdir -p .claude/hooks
curl -s https://raw.githubusercontent.com/amurshak/hephaestus/master/templates/hooks/protect-files.sh > .claude/hooks/protect-files.sh
curl -s https://raw.githubusercontent.com/amurshak/hephaestus/master/templates/hooks/lint-on-commit.sh > .claude/hooks/lint-on-commit.sh
chmod +x .claude/hooks/*.sh
```

Each file's header shows the `settings.json` wiring.

---

## Submodule install (for headless mode and forking)

For most Claude Code users the plugin is the least-friction path. The submodule is the right choice when you need:

- **Headless mode** — `loop.sh` runs `/autopilot` on a timer in a fresh session each time. The plugin can't do this since plugins run *inside* Claude Code; `loop.sh` runs Claude Code as a subprocess.
- **Forking and upstream sync** — clone the repo, modify commands, `git merge upstream/master` for upstream changes.

### Install

```bash
./install.sh /path/to/your/project
```

This adds `.hephaestus` as a submodule, symlinks commands and agents into `<project>/.claude/` and `<project>/.opencode/`, scaffolds `orient.md` templates, validates `CLAUDE.md`, and runs a health check. Safe to re-run. Commands install under bare names (`/autopilot`, `/ship`, etc.) — no plugin namespace, since they live directly in the project's command directories.

If your project already has `.claude/commands/` or agents, audit first to surface conflicts:

```bash
./install.sh --audit /path/to/your/project
```

### Manage the install

| | |
|---|---|
| `install.sh --audit`         | Preview what would change without modifying anything |
| `install.sh --force`         | Replace existing shared adapter files with hephaestus versions; project `orient.md` files stay protected |
| `install.sh --clean`         | Remove dangling symlinks after upstream renames |
| `/update-hephaestus`         | Pull latest, re-install, show what changed |
| `.hephaestus/uninstall.sh`   | Clean removal — only hephaestus symlinks |

### Headless mode

```bash
nohup ./.hephaestus/loop.sh 30 autopilot.log &
```

`loop.sh` runs `/autopilot` in a fresh session every N minutes. Clean context each time — no bloat. Project-scoped lockfile prevents overlap. Survives crashes. Runs with `--dangerously-skip-permissions` — scope what's allowed in your `settings.local.json`.

### Forking

Fork hephaestus to customize commands for your org while still pulling upstream updates.

**Safe to modify** — won't conflict on `git merge upstream/master`:
- `templates/` — customize scaffolds for your org's conventions
- `VERSION` — your fork's version track

**Will conflict if modified** — actively developed upstream:
- `.ai/workflows/` and `.claude/agents/` — the core workflow and agent files
- `.claude/commands/` — generated Claude adapters; update via `scripts/sync-agent-adapters.sh`
- `.opencode/commands/` and `.opencode/agents/` — generated OpenCode adapters; update via `scripts/sync-opencode-adapters.sh`
- `install.sh`, `update.sh`, `uninstall.sh` — the install tooling
- `.claude-plugin/plugin.json` — the plugin manifest

```bash
git remote add upstream https://github.com/amurshak/hephaestus.git
git fetch upstream
git merge upstream/master
```

---

## Contributing

PRs welcome. Before submitting:

```bash
./tests/run.sh                            # integration suite
./scripts/sync-agent-adapters.sh --check  # Claude adapter drift
./scripts/sync-opencode-adapters.sh --check  # OpenCode adapter drift
```

Edit canonical sources (`.ai/workflows/`, `.claude/agents/`), never generated adapters (`.claude/commands/`, `.opencode/`); regenerate with the sync scripts. Adapter generators for new harnesses are especially welcome — see `scripts/sync-opencode-adapters.sh` for the pattern.

## License

[MIT](LICENSE)
