# hephaestus

**A generic software development workflow pattern, implemented in Claude Code.**

All software delivery — regardless of language, framework, or domain — follows the same loop: understand the problem, plan the work, validate the plan, execute, verify, ship, clean up. Hephaestus makes that loop executable, autonomous, and self-correcting. It is distributed as a git submodule containing prose instructions that, when loaded into Claude Code's context, cause the model to behave as a structured delivery system rather than an interactive assistant.

```
/autopilot
```

```
orient → plan → critique → implement → review → test → ship → finish
```

One command. Eight phases. It figures out the rest.

---

## The pattern

The core question behind hephaestus: **what is the minimum set of composable, autonomous workflow phases that can deliver arbitrary software changes through an AI coding assistant?**

The answer is eight phases, five agent roles, bounded retry loops at every gate, deterministic failure degradation, and external systems as the sole persistence layer.

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
| 8 | **Finish** | Close issue, delete branches, file follow-ups for anything unresolved |

### Agents

Five roles, stratified by capability through least-privilege tool access:

| Agent | Writes code | Web access | Shell access | Isolation |
|-------|------------|------------|-------------|-----------|
| **coder** | Yes | No | Yes | worktree |
| **reviewer** | No | No | Yes (read-only) | none |
| **tester** | No | No | Yes (read-only) | none |
| **explorer** | No | No | Yes (read-only) | none |
| **researcher** | No | Yes | No | none |

The coder is the only agent that can modify files, and it runs in an isolated git worktree so parallel coders can't interfere with each other. The reviewer, tester, and explorer can read code and run commands but can't edit. The researcher can access the web but can't run shell commands. The blast radius of any single agent misbehaving is bounded by its tool permissions.

Every agent returns structured output — typed fields and verdicts, not prose. This turns agent invocations into function calls the orchestrating command can branch on.

---

## Design choices

### Minimum viable command set

Twelve commands, but only five form the delivery spine: `orient`, `start-issue`, `ship`, `finish`, and `autopilot` (which chains the other four and adds the critique/test gates). The remaining seven are support functions that pipeline phases call or convenience entry points that start at a different phase.

**Delivery**

| | |
|---|---|
| `/autopilot` | Full pipeline — pick issue, plan, implement, test, ship, finish |
| `/start-issue 42` | Plan-critique-implement for one issue |
| `/ship` | Code review → quality gates → CHANGELOG → PR → auto-merge |
| `/finish` | Close issue, clean branches, file follow-ups |
| `/refactor` | Autonomous refactoring with review gate and before/after metrics |

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

Hephaestus owns the workflow — what order things happen, when to retry, when to stop. The target project owns the specifics — what test command to run, what lint rules to enforce. Commands read the target's `CLAUDE.md` at runtime to discover quality gates. The only project-specific file hephaestus ever creates is a scaffold for `orient.md`, which it then refuses to overwrite.

### Parallelization at two levels

**Within a session**: multiple coder agents work in parallel worktrees for independent tasks; multiple explorer and researcher agents fan out across subsystems simultaneously. **Across sessions**: `loop.sh` runs `/autopilot` in fresh Claude sessions on a timer, each picking up the next issue. The system parallelizes both within a unit of work and across units of work.

### Deterministic failure modes

Every command specifies what happens when things go wrong — not as afterthoughts but as first-class workflow states. Retry exhaustion produces a draft PR with a descriptive prefix (`[WIP]`, `[BLOCKED]`, `[FAILING]`), a follow-up issue with context, and a clean repo. The system degrades into artifacts the next run or a human can pick up. It never blocks on input and never leaves the repo undefined.

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

## OODA loop analysis

The pipeline maps onto Boyd's OODA loop (Observe → Orient → Decide → Act) with structural parallels and deliberate divergences.

### Where they align

| OODA | Hephaestus | Correspondence |
|------|------------|----------------|
| **Observe** | Orient phase — read issue, explore codebase, git status | Gathering raw information about the environment |
| **Orient** | Plan + critique loop | Synthesizing observations into a mental model; the critique tests whether the orientation is sound |
| **Decide** | Critique verdict + task decomposition | The commitment to a course of action |
| **Act** | Implement → review → test → ship | Execution with feedback loops that can trigger re-orientation |

The critique gate is the most interesting correspondence. Boyd argued that Orient is the critical phase — where prior experience and new information synthesize into situational understanding. Quality of orientation determines everything downstream. Hephaestus embeds this by making plan-critique the most heavily gated phase.

### Where they diverge

**OODA is continuous; hephaestus is phased.** Boyd's loop has no discrete boundaries. Hephaestus imposes explicit phase gates — you don't implement until critique passes, you don't ship until tests pass. In software delivery, premature action has outsized downside. The phased structure sacrifices tempo for correctness.

**OODA has implicit feedback; hephaestus has explicit retry loops.** Each OODA cycle incorporates results of the previous one naturally. Hephaestus makes feedback loops explicit and bounded (3 plan-critique, 3 code-review, 2 test-fix). Without bounds, an autonomous system could loop forever. The retry limits are a tempo governor that forces graceful degradation.

**OODA optimizes for tempo; hephaestus optimizes for correctness.** Boyd's insight was that faster OODA cycles create advantage by acting while the opponent is still orienting. Hephaestus inverts this — it deliberately slows down at critique gates. The "opponent" in software delivery is complexity and entropy, not a human adversary. The cost of a fast wrong action (shipping a bug) exceeds the cost of a slow correct one.

**OODA has no wind-down state.** Boyd's loop assumes continuous operation. Hephaestus adds a failure-mode state machine: when retries exhaust, the system transitions to clean shutdown that preserves progress and creates breadcrumbs. AI sessions have finite context and finite reliability — the system must stop gracefully at any point.

**Nested loops.** Hephaestus nests OODA-like cycles within the larger pipeline. The test-fix cycle is its own observe-orient-decide-act loop. The pre-ship critique is another. This fractal structure — loops within loops, each with termination conditions — is more complex than Boyd's single-level model.

### The deeper correspondence

Boyd argued that speed of the OODA loop matters less than quality of orientation. An entity with a superior mental model makes better decisions even at lower tempo. Hephaestus embodies this: explorer agents fan out in parallel to build context, the critique gate stress-tests the plan across seven plan dimensions (logic, assumptions, completeness, trade-offs, evidence, second-order effects, timing), and persistent failures trigger RETHINK — forcing the system to rebuild orientation from scratch rather than iterating on a flawed one. Designed to be right before fast.

---

## Memory through external systems

Hephaestus doesn't build its own memory. It uses existing systems as read/write stores for different types of state:

| System | Memory function | Written by |
|--------|----------------|------------|
| **GitHub Issues** | Work queue, context, acceptance criteria | `create-issue`, `finish` (follow-ups), retry exhaustion |
| **Git history** | Implementation decisions, change rationale | Commits from every delivery command |
| **GitHub PRs** | Review state, quality gate results, in-flight work | `ship`, retry exhaustion (draft PRs) |
| **CLAUDE.md** | Project configuration, quality gates, constraints | `update-docs` |
| **CHANGELOG.md** | Release history | `ship`, `update-docs` |
| **Draft PRs with prefixes** | Failure breadcrumbs (`[WIP]`, `[BLOCKED]`, `[FAILING]`) | Retry exhaustion handlers |
| **Follow-up issues** | Deferred work, unresolved problems | `finish`, retry exhaustion |

Each `loop.sh` invocation starts a fresh Claude session with no memory of previous runs. The only way information persists between sessions is through these external artifacts. This is a feature: the system's state is always inspectable through standard developer tools (GitHub UI, git log, file contents), never locked in opaque internal state.

**The repo is the memory.** Git history records what was done and why. Issues record what needs to be done. PRs record work in flight. CLAUDE.md records how the project works. The system reads these on every run to reconstruct its orientation — stateless architecture where the "database" is the development environment itself.

**Failure state is encoded as artifacts.** When the system can't complete work, it creates a draft PR encoding the failure mode and a follow-up issue with context. The next run picks these up through the same issue-reading pipeline that handles human-created issues. Error recovery uses the same codepath as normal work intake.

When the target project uses Slack, Notion, or other documentation systems, the same principle applies — those systems become additional memory surfaces that feed context into future sessions through the project's `orient.md` and `CLAUDE.md`.

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

## Adopting in an existing project

If your project already has `.claude/commands/` or agents, run the audit first:

```bash
./install.sh --audit /path/to/your/project
```

This shows what would change — new symlinks, conflicts with your existing files, and name collisions — without modifying anything.

The key idea: **hephaestus handles orchestration, your `CLAUDE.md` handles project-specific configuration.** Move test/lint/build commands and project constraints into `CLAUDE.md`, then let hephaestus commands take over the workflow.

To remove hephaestus later: `.hephaestus/uninstall.sh` removes only hephaestus symlinks and the submodule, keeps your project-specific files.

---

## Headless mode

`loop.sh` runs `/autopilot` in a fresh Claude session every N minutes. Clean context each time — no bloat. Project-scoped lockfile prevents overlap. Survives crashes. Runs with `--dangerously-skip-permissions` — scope what's allowed in your `settings.local.json`.

---

## Forking and customization

Fork hephaestus to customize commands for your org while still pulling upstream updates.

**Safe to modify** — won't cause merge conflicts with upstream:
- `templates/` — customize scaffolds for your org's conventions
- `VERSION` — your fork's version track

**Will conflict if modified** — actively developed upstream:
- `.claude/commands/` and `.claude/agents/` — the core workflow files
- `install.sh`, `update.sh`, `uninstall.sh` — the install tooling

```bash
git remote add upstream https://github.com/amurshak/hephaestus.git
git fetch upstream
git merge upstream/master
```

---

## Your project's setup

Hephaestus reads your project's `CLAUDE.md` — specifically the "Development Commands" section. That's where it learns what to test, lint, and build:

```bash
cat .hephaestus/templates/CLAUDE.md.snippet >> CLAUDE.md
```

Then replace the placeholder commands with your actual test/lint/build commands. install.sh scaffolds `orient.md` automatically — customize it with your project's repos, structure, and priorities.

Optional but recommended:

| | |
|---|---|
| `.claude/hooks/lint-on-commit.sh` | Your lint command, before every commit |
| `.claude/hooks/protect-files.sh` | Block edits to `.env`, lock files, secrets |
| `AGENTS.md` | Index of local + shared agents |
| `.claude/settings.local.json` | Permissions and hook paths |
