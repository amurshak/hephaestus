# hephaestus

[![tests](https://github.com/amurshak/hephaestus/actions/workflows/tests.yml/badge.svg)](https://github.com/amurshak/hephaestus/actions/workflows/tests.yml) [![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**A general-purpose software development workflow pattern for AI coding agents.**

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

The core is a set of harness-neutral workflow specs (`.ai/workflows/`) and agent definitions — plain markdown files. Per-harness support is *generated adapters* from those specs: Claude Code, [OpenCode](https://opencode.ai), Codex, [Hermes](https://github.com/NousResearch/hermes-agent), and [Cursor](https://cursor.com) adapters ship today; new harnesses are a ~200-line generator script away.

The stance is protocol-oriented toward agents, models, and harnesses: each is a neutral spec with pluggable implementations — agent roles rather than vendor bindings, model tiers rather than model IDs, workflow specs rather than one harness's dialect.

Hephaestus is an OODA loop — observe, orient, decide, act — for software. Boyd designed OODA for fighter pilots: cycle faster than the opponent and you win. Software has the opposite problem. Shipping too fast costs more than slowing down. So this loop puts most of its weight on Orient. Plans face adversarial review before code begins. Code faces adversarial review before it ships. Retries are bounded so nothing spirals.

The core of Hephaestus is composed of five commands spread across eight internal phases. These are the fundamental process primitives of the development workflow. The system has five agent roles. Its memory lives in places that already exist: git history, GitHub issues, PRs, project management tools, project documentation. No opaque internal state. When retries exhaust, the system degrades into artifacts (draft PRs, follow-up issues, commits) the next session or a human can resume from.

## Install

In Claude Code:

```
/plugin marketplace add amurshak/hephaestus
/plugin install heph@hephaestus
```

That's it — commands appear under `/heph:` (`/heph:autopilot`, `/heph:ship`, …). For OpenCode, Codex, Hermes, manual copy, or the script install (one install, every project — plus headless mode and forking), see [Get started](#get-started).

**Requirements:** [Claude Code](https://claude.com/claude-code), [OpenCode](https://opencode.ai), [Codex](https://openai.com/codex), [Hermes](https://github.com/NousResearch/hermes-agent), or [Cursor](https://cursor.com) · [`gh` CLI](https://cli.github.com) authenticated (workflows drive GitHub issues and PRs) · git.

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
- [Script install](#script-install-every-project-at-once)
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

| Agent | Edit tools | Web access | Shell access | Isolation | Model tier |
|-------|------------|------------|-------------|-----------|------------|
| **coder** | Yes | No | Yes | worktree | sonnet |
| **reviewer** | No | No | Yes (instructed read-only) | none | opus |
| **tester** | No | No | Yes (instructed read-only) | none | haiku |
| **explorer** | No | No | Yes (instructed read-only) | none | haiku |
| **researcher** | No | Yes | No | none | sonnet |

The coder is the only agent granted edit tools; it runs in an isolated git worktree so parallel coders don't interfere. The reviewer, tester, and explorer have no edit tools and are instructed to treat their shell as read-only — a convention, not a sandbox, since an unrestricted shell can write. The researcher can access the web but has no shell at all. Tool grants bound most of the blast radius; the shell-bearing agents rely on instruction for the rest.

Every agent returns structured output — typed fields and verdicts, not prose. This turns agent invocations into function calls the orchestrating command can branch on.

#### Model tiers

Roles differ in what it costs to get them wrong, so they run on different models. Adversarial review is the job that must not miss a real bug; a read-only file search is not. Agents declare a harness-neutral tier — `opus`, `sonnet`, `haiku`, or `inherit` — and [`.ai/models.conf`](.ai/models.conf) says what each tier means for a harness that needs a concrete value:

| Harness | Rendered as |
|---------|-------------|
| Claude Code | the tier name, natively |
| OpenCode | `model: <provider>/<model-id>` |
| Codex | `model_reasoning_effort` (a pinnable `model` if you want one) |
| Cursor | `model`, unset by default — Cursor's model namespace churns per release, so tiers inherit until you pin them |
| Hermes | `model: <provider>/<model-id>`, advisory — Hermes applies one global `delegation.model` |

To run the roles on another provider, repoint the mapping — not the tiers. Drop a `~/.hephaestus/models.conf` to change it for every project, or point `$HEPHAESTUS_MODELS` at a file for one run; layers merge per key, so naming a single tier leaves the rest at their shipped defaults. Generator `--check` reads the shipped file alone, so a personal override never turns the drift gate red for everyone else.

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

Hephaestus owns the workflow — what order things happen, when to retry, when to stop. That behavior is specified once in [`.ai/conventions.md`](.ai/conventions.md) and implemented by the canonical workflows in `.ai/workflows/`; every harness directory is a generated adapter of those (see [CONTRIBUTING.md](CONTRIBUTING.md) for the generators).

The target project owns the specifics — what test command to run, what lint rules to enforce. Commands read the target's `CLAUDE.md` at runtime to discover them; `## Development Commands` is the only section a project must supply. The only command hephaestus ever writes into your repo is a scaffold for `orient`, which it then refuses to overwrite.

### Parallelization at three levels

**Within a session**: multiple coder agents work in parallel worktrees for independent tasks; multiple explorer and researcher agents fan out across subsystems simultaneously. **Across issues**: `/worktrees` surveys and reaps finished worktrees, plans a wave of mutually non-conflicting issues under a configurable cap (declare contention hotspots in a `## Worktrees` section of CLAUDE.md), creates a sibling worktree per issue with config propagated and env files single-sourced, and spawns a seeded agent session in each. **Across time**: `loop.sh` runs `/autopilot` in fresh sessions on a timer, each picking up the next issue.

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

`/orient` collects what a spawned session could not clean up itself — a `/finish` running inside a worktree cannot remove the worktree it occupies, so it defers:

```
/orient                             (requires: none)
└── /worktrees                      (requires: none)
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
| **changelog.d/ → CHANGELOG.md** | Release history — one fragment per PR, folded at release by `scripts/collect-changelog.sh` | `ship`, `update-docs` |
| **Draft PRs with prefixes** | Failure breadcrumbs (`[WIP]`, `[BLOCKED]`, `[FAILING]`) | Retry exhaustion handlers |
| **Follow-up issues** | Deferred work, unresolved problems | `finish`, retry exhaustion |

Each `loop.sh` invocation starts a fresh session with no memory of previous runs. Information persists between sessions only through these external artifacts. The system's state is always inspectable through standard developer tools (GitHub UI, git log, file contents), never locked in opaque internal state.

**The repo is the memory.** Git history records what was done and why. Issues record what needs to be done. PRs record work in flight. CLAUDE.md records how the project works. The system reads these on every run to reconstruct its orientation — stateless architecture where the "database" is the development environment itself.

**Failure state is encoded as artifacts.** When the system can't complete work, it creates a draft PR encoding the failure mode and a follow-up issue with context. The next run picks these up through the same issue-reading pipeline that handles human-created issues. Error recovery uses the same codepath as normal work intake.

Slack, Notion, and other documentation systems extend the principle — additional memory surfaces fed into future sessions through `orient.md` and `CLAUDE.md`.

---

## Get started

The workflows, commands, and agents are plain markdown files. Three ways to get them in front of your harness, in order of friction:

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

### 2. Script install (any harness)

```bash
git clone https://github.com/amurshak/hephaestus.git ~/.hephaestus
~/.hephaestus/install.sh                             # once per machine
~/.hephaestus/install.sh --project /path/to/project  # once per repo
```

The first command installs the shared commands, agents, and skills into your harness config dirs — `~/.claude/`, `~/.config/opencode/`, `~/.codex/`, `~/.hermes/` — so they work in **every** project. The second scaffolds the handful of files a project owns: `orient` for each harness, `AGENTS.md`, `opencode.json`, `.hermes/.gitignore`. Commands run under bare names (`/autopilot`, `/ship`). `~/.hephaestus/update.sh` pulls and re-links. Full detail in [Script install](#script-install-every-project-at-once).

### 3. Copy the files by hand (any harness)

Zero machinery — vendor the files directly:

```bash
git clone https://github.com/amurshak/hephaestus.git
# Claude Code:
mkdir -p your-project/.claude
cp -R hephaestus/.claude/commands hephaestus/.claude/agents your-project/.claude/
# OpenCode:
mkdir -p your-project/.opencode
cp -R hephaestus/.opencode/commands hephaestus/.opencode/agents your-project/.opencode/
cp hephaestus/opencode.json your-project/   # loads AGENTS.md + CLAUDE.md
# Codex:
mkdir -p your-project/.agents your-project/.codex
cp -R hephaestus/.agents/skills your-project/.agents/
cp -R hephaestus/.codex/agents your-project/.codex/
# Hermes:
mkdir -p your-project/.hermes
cp -R hephaestus/.hermes/skills hephaestus/.hermes/agents your-project/.hermes/
# Cursor:
mkdir -p your-project/.cursor/rules
cp -R hephaestus/.cursor/commands hephaestus/.cursor/agents your-project/.cursor/
cp hephaestus/.cursor/rules/hephaestus.mdc your-project/.cursor/rules/
```

No update story — re-copy when you want the latest, or use `install.sh --vendor` to get the same committed copies with a manifest that makes updates and removal exact.

### Cursor usage

Three adapter families, all generated by `scripts/sync-cursor-adapters.sh`:

| Path | What it is |
|------|------------|
| `.cursor/commands/*.md` | Slash commands — `/autopilot`, `/ship`, … |
| `.cursor/agents/*.md` | Subagents — `coder`, `reviewer`, `explorer`, `tester`, `researcher` |
| `.cursor/rules/hephaestus.mdc` | Always-apply rule carrying the chain graph and the Claude→Cursor mapping |

Cursor's own mechanics shape them:

- **Commands are injected verbatim.** Cursor strips YAML frontmatter only from imported `.claude/commands` files, so these adapters carry none and lead with the workflow's own opening line — what Cursor shows as the hover preview. `$ARGUMENTS` and `$1`… *are* substituted, so those placeholders survive.
- **`readonly: true` where it is free.** Cursor honours the key (it maps to a READONLY permission mode), so `researcher` gets it. Whether READONLY also withholds the terminal is undocumented, so `reviewer`, `tester`, and `explorer` — which need a working shell — keep the default mode and carry the restriction as instruction, exactly as they do under Claude Code. `tools:` is *not* an access control in Cursor: it is rendered to the model as prose.
- **No worktree isolation.** Parallel `coder` runs share one working tree, so file-modifying tasks must be serialized. The adapters say so in both the subagent description (where the orchestrator decides to parallelize) and the body.

`.cursor/rules/` is shared with your own project rules. Hephaestus only ever writes and reclaims `hephaestus.mdc`, and the manifest makes that exact — a rule it did not write is never touched.

### OpenCode usage (cwd is the product)

1. Shared adapters load from `~/.config/opencode/` in every project (`install.sh`); a vendored or hand-copied `.opencode/` works too.
2. **Start OpenCode from the project root** — the project's own `.opencode/orient` and `AGENTS.md` are discovered by walking up from cwd, so starting from `$HOME` loses them.
3. Type `/` — you should see `/autopilot`, `/ship`, `/finish`, …
4. Verify load: `opencode debug config` or `bash scripts/verify-opencode-load.sh` (from hephaestus root or after install).
5. Nested steps say “run `/ship`” — invoke the slash command so the full template loads; do not paraphrase. Role work uses the Task tool or `@coder` / `@reviewer` / … (no worktree isolation — serialize file-writing `@coder` tasks).

### Codex usage (skills, matched by description)

1. `install.sh` links the skills into `~/.codex/skills/` (honoring `$CODEX_HOME`) for every project; Codex also reads a project's own `.agents/skills/`, so a vendored or hand-copied install works with no wiring.
2. Codex has no slash-command registry — `/autopilot`, `/ship`, … are ordinary prompt text that Codex matches to a skill by its description, which every generated skill anchors with `Use for /<name> requests.`
3. Verify: `bash scripts/verify-codex-load.sh` (add a project path to check an installed project) — it asks the live CLI whether `codex [OPTIONS] [PROMPT]` still takes the positional prompt `/worktrees` uses to seed a spawned session, then finds the skills and agent roles and prints which root each resolved to.
4. Role work uses the agent roles — `~/.codex/agents/` after `install.sh`, `.codex/agents/` when vendored. No worktree isolation — serialize file-modifying coder tasks.

### Hermes usage (a skill package, wired once)

Hermes is not a command-file harness. Its extension surface is a skills system, so hephaestus ships as a **skill package**: thirteen skills under the `hephaestus` category plus five delegate briefs.

1. `install.sh` puts the package straight into `~/.hermes/skills/hephaestus/` and `~/.hermes/agents/`, which Hermes already reads — **no wiring needed**, and it applies to every project. The rest of this section is only for a per-project copy (`--vendor` or hand-copied), which creates `.hermes/skills/hephaestus/` and `.hermes/agents/` inside the repo.
2. **Wire discovery once**, for a per-project copy only. Hermes reads `~/.hermes/skills` plus whatever `skills.external_dirs` names; it has no project-local discovery. Add to `~/.hermes/config.yaml` under the top-level `skills:` key:
   ```yaml
   skills:
     external_dirs:
       - /path/to/your-project/.hermes/skills
   ```
   `HERMES_HOME=/path/to/your-project/.hermes` also works and needs no config edit, but it makes the repo Hermes's whole profile home — `config.yaml`, credentials, session transcripts and memories land in your working tree, and `.hermes/skills` becomes writable. Commit only `.hermes/skills` and `.hermes/agents` if you go that route. `external_dirs` is the recommended path.
3. Verify: `bash ~/.hephaestus/scripts/verify-hermes-load.sh` (add the project path for a per-project copy) — it checks the wiring, then confirms the skills appear in `hermes skills list`. Those are layout checks, so they prove a skill *resolves*, not that Hermes loads its body; add `--live` for one billed probe that confirms the workflow actually reaches the model.
4. Invoke as `/autopilot`, `/ship`, `/finish`, … Under `external_dirs` the package is read-only to Hermes, so its self-improving skill writes land in `~/.hermes/skills` and cannot mutate a generated adapter out of sync; the generator's `--check` catches it if they ever do.
5. Role work uses `delegate_task`. Each brief in `.hermes/agents/` gives the `toolsets` to pass (`["terminal", "file"]` for coder, `["file", "web"]` for researcher) and the prompt to send as `context`. Three Hermes specifics: a delegate inherits **none** of the parent conversation and not its working directory either, so `context` carries absolute paths and everything else it needs; the `toolsets` you pass are intersected with the session's and anything missing is dropped silently, so a researcher delegate in a session without `web` loses web search with no error; and `delegate_task` has no per-child worktree, so parallel coder delegates share one working tree — serialize file-modifying work.

**Two doctrines to keep straight.** Hermes's persistent memory (`~/.hermes/memories/`) is profile-scoped, capped, and frozen into the system prompt at session start — it is not repo state. Hephaestus keeps the repo canonical: issues, PRs, and git history are the memory that survives a machine change. Use Hermes memory for durable preferences, not for what a workflow decided. Likewise the kanban toolset is a local board with no GitHub issue sync, so GitHub issues remain the work queue; kanban is optional scratch space for a single session's fan-out.

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
| `AGENTS.md` | Index of local + shared agents (`install.sh --project` scaffolds this from a template) |
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

## Script install (every project at once)

For Claude Code alone, the plugin is the least-friction path. The script install is the right choice when you need:

- **Every harness** — one install covers Claude Code, OpenCode, Codex, and Hermes.
- **Every project** — the shared set lives in your harness config dirs, so a new repo needs no adapter install at all.

- **Headless mode** — `loop.sh` runs `/autopilot` on a timer in a fresh session each time. Plugins can't do this since they run *inside* the harness; `loop.sh` runs Claude Code or OpenCode as a subprocess.
- **Forking and upstream sync** — clone the repo, modify commands, `git merge upstream/master` for upstream changes.

### Install

```bash
git clone https://github.com/amurshak/hephaestus.git ~/.hephaestus
~/.hephaestus/install.sh
```

Symlinks the shared commands, agents, and skills into `~/.claude/`, `~/.config/opencode/`, `~/.codex/`, and `~/.hermes/` (honoring `$CLAUDE_CONFIG_DIR`, `$XDG_CONFIG_HOME`, `$CODEX_HOME`, and `$HERMES_HOME`), then runs a health check. Commands work under bare names (`/autopilot`, `/ship`, …) in every project — no plugin namespace, and for Hermes no `external_dirs` wiring.

Then prepare each repo with the files a project genuinely owns — `orient` for each harness, `AGENTS.md`, `opencode.json`, `.hermes/.gitignore` — and validate its `CLAUDE.md`:

```bash
~/.hephaestus/install.sh --project /path/to/your/project
```

Both are idempotent and never overwrite a file they did not install. If a config dir already holds a command, agent, or skill of the same name, audit first to surface the conflict:

```bash
~/.hephaestus/install.sh --audit
```

### Pin the workflow to a repo instead

Teams that want everyone's `/ship` to behave identically — and CI to be reproducible — can commit the adapters alongside the code:

```bash
~/.hephaestus/install.sh --vendor /path/to/your/project
```

This copies the shared set into the repo, does the `--project` scaffolding, and writes a `.heph-manifest` recording the version and every file it wrote. That manifest is the pin: `update.sh --vendor` refreshes exactly those files, and `uninstall.sh --vendor` removes exactly those files. Plain committed files — no submodule, so nothing to initialize on clone, in CI, or in a git worktree.

### Stop the changelog from conflicting

Every PR touches `CHANGELOG.md` by construction, so parallel waves conflict on it every time. The fix is one file per PR:

```bash
~/.hephaestus/install.sh --project --changelog-fragments /path/to/your/project
```

`/ship` then writes `changelog.d/<issue-or-slug>.<added|changed|fixed|removed>.md` instead of editing `CHANGELOG.md`; distinct filenames make the conflict structurally impossible. At release, the `scripts/collect-changelog.sh` copy this installs folds every fragment into a dated section and deletes them (`--preview` to dry-run, `--check` to validate names in a quality gate).

It is opt-in because it changes *where* `/ship` writes — everything else the installer scaffolds only adds. Adopting it also scaffolds a `CHANGELOG.md` if you have none and sets `CHANGELOG.md merge=union` in `.gitattributes` as a backstop, leaving an existing `.gitattributes` alone with a note. Later runs, including `update.sh`, recognize the adoption and keep it without the flag. Without it, `/ship` keeps appending to `CHANGELOG.md` as before.

If your repo already has its own `scripts/collect-changelog.sh`, adoption is declined outright — nothing is scaffolded, and `--force` will not take that file over. Recognition needs both `changelog.d/` and a script carrying hephaestus's provenance token, so a name collision is never mistaken for adoption.

The copy that lands is stamped with the version it came from and a checksum of the original, which lets a later run tell the two reasons it can differ apart. If you have not touched it and upstream has moved, `update.sh` refreshes it in place — no flag, since there is nothing of yours to lose. If you *have* edited it, it is left alone and reported, and only `--force` overwrites it. That matters because `--force` is repo-wide: it also replaces same-named adapters you may have hand-edited, so needing it just to pick up a fix in one script was a bad trade. Copies installed before stamping existed are a special case — an edit and an upstream change are indistinguishable there, so a drifted one still waits for `--force`; once refreshed or found identical to the clone, it is stamped and self-heals from then on.

### Migrating from a submodule install

Installs from before 2.2 put hephaestus in a `.hephaestus` submodule and symlinked every adapter through it. One command converts a repo:

```bash
~/.hephaestus/install.sh --migrate /path/to/your/project     # add --audit to preview
```

It removes the submodule (deinit, `git rm`, the `.git/modules` entry, and `.gitmodules` if nothing else uses it) and every symlink pointing through `.hephaestus/`, then scaffolds the project-owned files. Your `orient`, `AGENTS.md`, hooks, and `CLAUDE.md` are untouched. `--migrate` implies `--project`; add `--vendor` to migrate straight to committed copies. Run `install.sh` once for the shared set if you haven't — the health check tells you if it's missing. Commit the result.

### Manage the install

| | |
|---|---|
| `install.sh --audit`         | Preview what would change without modifying anything |
| `install.sh --force`         | Take over a same-named file the installer did not write; project `orient` files stay protected |
| `install.sh --clean`         | Remove adapters dropped upstream since the last install |
| `install.sh --migrate <path>` | Convert a pre-2.2 submodule install, then scaffold |
| `install.sh --project <path>`| Scaffold the project-owned files in a repo |
| `install.sh --project --changelog-fragments <path>` | Adopt one changelog entry per PR (also valid with `--vendor`) |
| `install.sh --vendor <path>` | Commit the shared set into a repo, pinned by `.heph-manifest` |
| `update.sh` / `update.sh --vendor <path>` | Pull the latest and re-install |
| `/update-hephaestus`         | The same update, driven from inside your harness |
| `uninstall.sh` / `uninstall.sh --vendor <path>` | Remove exactly what was installed |

Every install records what it wrote — user-level in `$XDG_STATE_HOME/hephaestus/manifest`, vendored in the repo's `.heph-manifest`. Updates and removals read that record, so your own files are never touched by either.

### Headless mode

```bash
cd /path/to/your/project
nohup ~/.hephaestus/loop.sh 30 autopilot.log &
HEPH_HARNESS=opencode nohup ~/.hephaestus/loop.sh 30 autopilot-oc.log &
```

`loop.sh` runs `/autopilot` in a fresh session every N minutes. Clean context each time — no bloat. Project-scoped lockfile prevents overlap. Survives crashes. Claude path uses `--dangerously-skip-permissions`; OpenCode path uses `opencode run --auto --command autopilot` (start from the project root so `.opencode/` loads). Default harness is Claude; set `HEPH_HARNESS=opencode` for OpenCode.

### Forking

Fork hephaestus to customize commands for your org while still pulling upstream updates — which files are safe to edit and which conflict on `git merge upstream/master` is in [CONTRIBUTING.md § Forking](CONTRIBUTING.md#forking).

---

## Contributing

This README is the **consumer** surface: installing hephaestus and running it against your project. Two documents cover the other side.

| Document | Covers |
|---|---|
| [`.ai/conventions.md`](.ai/conventions.md) | The behavior spec the workflows implement — the loop, retry limits, escalation, verdicts, what your project owns |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Working **on** hephaestus — canonical sources, adapter generators, quality gates, forking |

PRs welcome. The short version: edit canonical sources (`.ai/conventions.md`, `.ai/workflows/`, `.claude/agents/`), never generated adapters; run `./tests/run.sh` and every `scripts/sync-*-adapters.sh --check`. Adapter generators for new harnesses are especially welcome.

## License

[MIT](LICENSE)
