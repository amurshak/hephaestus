# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Audience: contributor** — this file is about working **on** hephaestus. Nothing here is true in a project that merely installed it.
>
> The product side — the loop, retry limits, escalation, verdicts, and what a target project owns — is [`.ai/conventions.md`](.ai/conventions.md). The reader's test for which side a sentence belongs on: *would it still be true in a project that only installed hephaestus?* Yes → product. No → here.

## Core Principles

Three ideas shape every design decision:

1. **Simplicity** — One command to deliver an issue. One file to configure quality gates. One install to share across projects. Complexity is a bug.

2. **Self-improvement** — The system critiques its own plans before implementing, reviews its own code before shipping, and finds work when idle. Improvements propagate to every project from one clone.

3. **Autonomy** — Commands run without human intervention. They resolve ambiguity, recover from failures, and wind down cleanly. Stopping to ask is a last resort reserved for irreversible risk.

When in doubt about a design choice, pick the option that is simpler, more self-improving, or more autonomous.

## What This Is

Hephaestus is an implementation of a generic software development workflow pattern for AI coding agents. It encodes the observation that all delivery follows the same loop — orient, plan, critique, implement, review, test, ship, finish — and makes that loop executable, autonomous, and self-correcting. Distributed as one clone of prose workflows plus tool adapters that cause an AI coding agent to behave as a structured delivery system. Installed into the harness config dirs via `./install.sh`, per repo via `./install.sh --project <target>`.

## Development Commands

This repo's own quality gates. The heading is a shipped contract — `/ship` and `/test-issue` read it in every installed project — so what it names here is hephaestus's adapter-generation meta-suite, not a template for anyone else's tests.

- **Test**: `./tests/run.sh` — full integration suite (single file: `bash tests/test_<name>.sh`)
- **Lint/drift**: `./scripts/sync-agent-adapters.sh --check`, `./scripts/sync-opencode-adapters.sh --check`, `./scripts/sync-codex-adapters.sh --check`, `./scripts/sync-hermes-adapters.sh --check`, `./scripts/sync-cursor-adapters.sh --check`, `bash tests/check_composition.sh`, `bash tests/check_conventions.sh`
- **Build**: none (prose + shell; no compile step)

## Docs Requirements

The trigger list `/finish` uses here, overriding its defaults:

- **Changelog fragment** — every PR, no exceptions: `changelog.d/<issue-or-slug>.<added|changed|fixed|removed>.md`
- **README.md** — when the PR changes the consumer surface: `install.sh`, `update.sh`, `uninstall.sh`, `.ai/workflows/*.md`, `.ai/conventions.md`
- **CLAUDE.md** — when the PR changes the contributor surface: `.claude/agents/*.md`, `scripts/*`, or this file's own conventions
- **CONTRIBUTING.md** — never required mechanically; update it when the gates or the canonical-source rules change

Generated adapters (`.claude/commands/`, `.opencode/`, `.agents/skills/`, `.hermes/`, `.cursor/`) trigger nothing on their own. They regenerate on every workflow change, so triggering README from them made README a required file on essentially every PR — which is what made it a contention hotspot rather than a documentation rule.

## Worktrees

- `max:` 3
- `serialize_paths:` `install.sh`
- `setup:` none (no deps to install)

`install.sh` is where installer and distribution work collides semantically — two issues rewriting install paths in the same wave conflict in ways a rebase can't resolve. `CHANGELOG.md` is absent because it is no longer contended: entries are written as one-file-per-PR fragments in `changelog.d/` (see below), so parallel branches never touch a shared anchor. `README.md` was removed for the same reason — the contributor mechanics moved to CONTRIBUTING.md and the Docs Requirements above stopped requiring it for generated-adapter churn, so it is edited by consumer-surface work only. Do not list a file every PR touches by construction; serializing it pins concurrency at 1. Fix those structurally instead.

## Changelog

Entries are **fragments**, not direct edits to CHANGELOG.md: `/ship` writes `changelog.d/<issue-or-slug>.<added|changed|fixed|removed>.md` containing the entry body without the leading `- `. Distinct filenames per PR make merge conflicts structurally impossible.

At release, `scripts/collect-changelog.sh <version>` folds every fragment into a dated `## <version>` section and deletes them (`--preview` to dry-run, `--check` to validate filenames). Hand-written `## Unreleased` content is merged by category, so the transition loses nothing. `.gitattributes` sets `CHANGELOG.md merge=union` as a backstop for any direct edit that slips through.

Target projects adopt the same convention with `install.sh --project --changelog-fragments <path>`, which scaffolds `changelog.d/`, a `CHANGELOG.md` if absent, a copy of `collect-changelog.sh`, and the `.gitattributes` line. It is opt-in — unlike every other scaffold, it changes *where* `/ship` writes — and sticky: later runs detect the adoption from the distributed script and keep it without the flag. `/ship` and `/update-docs` stay conditional on `changelog.d/` existing, so a project that never opts in is unaffected.

## Repository Structure

- `.claude/agents/` — Subagent definitions (coder, reviewer, tester, explorer, researcher) with tool permissions and structured output contracts
- `.ai/conventions.md` — the product behavior spec the workflows implement; enforced by `tests/check_conventions.sh`
- `.ai/workflows/` — canonical, tool-neutral workflow specs with `name`, `requires`, and `chains` frontmatter
- `.claude/commands/` — generated Claude slash-command adapters for the canonical workflows
- `.opencode/commands/` — generated OpenCode command adapters for the same canonical workflows
- `.opencode/agents/` — generated OpenCode subagent adapters from `.claude/agents/`
- `.agents/skills/` — generated Codex skill adapters for the same canonical workflows
- `.codex/agents/` — generated Codex agent-role adapters from `.claude/agents/`
- `.hermes/skills/hephaestus/` — generated Hermes skill adapters for the same canonical workflows
- `.hermes/agents/` — generated Hermes `delegate_task` briefs from `.claude/agents/`
- `.cursor/commands/`, `.cursor/agents/` — generated Cursor slash commands and subagents
- `.cursor/rules/hephaestus.mdc` — generated always-apply Cursor rule (chain graph + Claude→Cursor mapping)
- `opencode.json` — OpenCode project config that loads `AGENTS.md` and this file as instructions
- `.claude-plugin/plugin.json` — Plugin manifest for Claude Code marketplace install (declares `commands` and `agents` paths so the plugin loader finds them under `.claude/`)
- `scripts/sync-agent-adapters.sh` — generates/checks tool-specific adapters from `.ai/workflows/`
- `scripts/sync-opencode-adapters.sh` — generates/checks OpenCode commands and agent adapters
- `scripts/sync-codex-adapters.sh` — generates/checks Codex skills and agent-role adapters
- `scripts/sync-hermes-adapters.sh` — generates/checks Hermes skills and delegate briefs
- `scripts/sync-cursor-adapters.sh` — generates/checks Cursor commands, subagents, and the project rule
- `changelog.d/` — one changelog fragment per PR; `scripts/collect-changelog.sh <version>` folds them into CHANGELOG.md at release
- `install.sh` — Three modes: default symlinks the shared adapters into the harness config dirs (`~/.claude/`, `~/.config/opencode/`, `~/.codex/`, `~/.hermes/`, `~/.cursor/`); `--project` scaffolds the files a repo owns; `--vendor` commits the shared set into a repo. Every mode records what it wrote in a manifest. `--migrate` first strips a pre-2.2 `.hephaestus` submodule install from the target repo
- `update.sh` — Pulls the clone and re-installs (`--vendor <path>` for a vendored repo)
- `uninstall.sh` — Removes exactly what the matching manifest records

## Core Workflow Pattern

**The spec is [`.ai/conventions.md`](.ai/conventions.md)** — the eight phases, the retry limits, the escalation ladder, ambiguity handling, verdicts, session checkpoints, and what a target project owns. Read it before changing any workflow; it governs this repo's sessions too.

It is a spec, not a runtime dependency. The workflows are the shipped artifact, so they state each limit at the point of use — an installed project has no `.ai/` directory to read. `bash tests/check_conventions.sh` fails if a workflow states a value the spec does not — or states one in a shape it cannot read — so the two cannot drift silently. Change the spec first, then the workflows, then run the check.

Never reintroduce a by-name reference like "per CLAUDE.md retry limits": it forced `/orient` to retype the limits into every installed project's CLAUDE.md, which is the hand-maintained duplication this layout exists to prevent.

## Key Design Constraints

- **Workflows live in `.ai/workflows/`** as the canonical source. `.claude/commands/` files are generated adapters; run `./scripts/sync-agent-adapters.sh` after workflow edits and `./scripts/sync-agent-adapters.sh --check` in quality gates.
- **OpenCode adapters are generated too**: `.opencode/commands/` comes from `.ai/workflows/`; `.opencode/agents/` comes from `.claude/agents/`. The generator localizes Claude dialect (worktrees/subagents/TodoWrite → Task/`@agent` + serialize edits, and the `/worktrees` spawn CLI → `opencode --prompt`) and injects slash-command chain notes. Run `./scripts/sync-opencode-adapters.sh` after workflow or agent edits and `./scripts/sync-opencode-adapters.sh --check` in quality gates. Verify a live open session loads them with `bash scripts/verify-opencode-load.sh`.
- **Codex adapters are generated too**: `.agents/skills/*/SKILL.md` comes from `.ai/workflows/`; `.codex/agents/*.toml` comes from `.claude/agents/`. The generator localizes the same Claude dialect, including the `/worktrees` spawn CLI → `codex "<prompt>"`. Codex reads skills from `$CODEX_HOME/skills` and a project's own `.agents/skills`, and matches `/start-issue <N>` to a skill implicitly via its `Use for /<name> requests.` description anchor (both measured against codex-cli 0.145.0). `bash scripts/verify-codex-load.sh` guards the spawn form live — that `codex --help` still takes a positional prompt — and checks the adapters are in a root Codex reads. Run `./scripts/sync-codex-adapters.sh` after workflow or agent edits and `./scripts/sync-codex-adapters.sh --check` in quality gates.
- **Hermes adapters are generated too**: `.hermes/skills/hephaestus/*/SKILL.md` comes from `.ai/workflows/`; `.hermes/agents/*.md` comes from `.claude/agents/`. The generator localizes the same Claude dialect (worktrees/subagents/TodoWrite → `delegate_task` with per-role `toolsets` + the todo tool + serialize edits, and the `/worktrees` spawn CLI → `hermes chat -s hephaestus/<skill> -q`, since `-q` bypasses the slash dispatcher and a bare `/<skill>` would reach the model as literal text) and warns that a delegate inherits neither the parent conversation nor its working directory. Hermes has no project-local skill discovery, so the files stay inert until the project's `.hermes/skills` is wired — `skills.external_dirs` (recommended) or `HERMES_HOME` — `bash scripts/verify-hermes-load.sh` checks that wiring against a live install; its checks are layout-only and so prove a skill resolves but not that its body loads, which `--live` confirms with one billed probe. Run `./scripts/sync-hermes-adapters.sh` after workflow or agent edits and `--check` in quality gates.
- **Cursor adapters are generated too**: `.cursor/commands/` comes from `.ai/workflows/`; `.cursor/agents/` comes from `.claude/agents/`; `.cursor/rules/hephaestus.mdc` is derived from both. Cursor mechanics that shape the output: command files are injected **verbatim** (frontmatter is stripped only for imported `.claude/commands`), so they carry no YAML and lead with the workflow's opening line — Cursor's hover preview; `$ARGUMENTS`/`$1`… *are* substituted; frontmatter values are not unquoted, so they are emitted bare; `readonly: true` is honoured and emitted for agents with no shell and no edit tools, while `tools:` is only rendered to the model as prose and is never an access control. The `/worktrees` spawn CLI localizes to `cursor-agent -p`; the `-p` is load-bearing, since the slash dispatcher is bound to the TUI input widget and a bare positional `/start-issue <N>` reaches the model as literal text instead of dispatching. Cursor spawns are therefore headless — `-p` prints and exits — deliberately unlike the Claude and Codex rows. Run `./scripts/sync-cursor-adapters.sh` after workflow or agent edits and `--check` in quality gates.
- **Commands read the target project's CLAUDE.md** to discover test/lint/build commands. The "Development Commands" section in each installed project drives all quality gates.
- **`/finish` branches on explicit PR state** before cleanup. Merged PRs complete the full close/cleanup/docs flow; auto-merge-pending and manual-merge-needed PRs preserve the issue and PR branch; closed-unmerged PRs abort finish cleanly.
- **`/finish` splits cleanup by checkout context** (`git rev-parse --git-dir` vs `--git-common-dir`). A session in a linked worktree cannot check out the base branch, delete its own branch, or pop the shared stash, and `git worktree remove .` *succeeds* by deleting its own cwd — killing the run mid-workflow. So worktree sessions close the issue, sweep remote branches, and report, then stop; `/orient` chains `/worktrees cleanup` in the primary to reap what they left.
- **`/finish` decides docs sync mechanically** from the PR diff, against the trigger list in "Docs Requirements" above — that section is the rule for this repo, and it overrides finish.md's defaults whole. If any required doc is missing from the diff, `/finish` runs `/update-docs` and logs the missing files.
- **Repo detection** is done via `git remote get-url origin` — commands never hardcode repo references.
- **orient is project-specific** — it is excluded from symlinking in every harness. `install.sh --project` scaffolds a template from `templates/orient.md` that must be customized. The shipped generic `/orient` covers install paths without install.sh (plugin, manual copy): on first run in an unprepared project it bootstraps the operating requirements — infers a Development Commands section from manifests and scaffolds a project orient — additively, never overwriting. It skips the bootstrap writes in a repo that defines the workflow rather than consuming it, recognised by `.ai/workflows/` plus a `scripts/sync-*-adapters.sh` generator — `.claude/commands/orient.md` here is the generated consumer adapter, so without the guard `/orient` treats this repo as a target project and offers to scaffold the requirements it authors. The phrasing is deliberately generic: the guard ships to every installed project, so it must not name this repo.
- **install.sh is idempotent** — re-running refreshes the files it installed and never touches anything else.
- **Changelog fragments are opt-in, then sticky** — `--changelog-fragments` scaffolds the convention. Project mode writes no manifest, so adoption is inferred, and a path alone is never the evidence: it takes `changelog.d/` **and** a `scripts/collect-changelog.sh` carrying the `# hephaestus:collect-changelog` token (a token, not the prose header — rewording a comment must not un-adopt every project). A repo with its own script at that path is not an adopter; adoption is declined whole rather than scaffolding the other files around a collect script that will never be installed, and `--force` never takes that file over. Our own copy is code, not a customization point, so it *is* refreshed under `--force` once it drifts.
- **Ownership is recorded, not inferred** — each install writes a manifest (`$XDG_STATE_HOME/hephaestus/manifest` at user level, `<project>/.heph-manifest` when vendored) listing every path it wrote. Install, update, `--clean`, and uninstall all read it, so a file hephaestus did not write is never modified or removed, and an adapter dropped upstream is detected exactly.
- **User-level symlinks are absolute** — they point into the clone, so they resolve from any cwd, including a git worktree. (The former submodule layout used relative links into `.hephaestus/`, which dangle in worktrees because `git worktree add` does not populate submodules.)
- **Never `git add .hermes` wholesale** — under `HERMES_HOME` that directory is Hermes's profile home. Stage `.hermes/skills`, `.hermes/agents`, and `.hermes/.gitignore` only; the scaffolded `.gitignore` is the backstop.

## Agent Conventions

Five agent roles, stratified by least-privilege tool access. Coder is the only agent that can modify files (runs in `isolation: worktree` for safe parallel edits). Reviewer, tester, and explorer are read-only. Researcher has web access but no shell.

- Agents declare allowed tools, isolation mode, and model tier in YAML frontmatter
- All agents return structured output (files changed, status, verdict) — never raw verbose logs
- Reviewer verdicts: PASS / PASS WITH CHANGES / FAIL
- General critique verdicts: SOUND / NEEDS REFINEMENT / RETHINK

**Model tiers** — every agent declares `model: opus | sonnet | haiku | inherit`. The tier is harness-neutral; `.ai/models.conf` says what it means per harness (OpenCode gets a `provider/model-id`, Codex gets `model_reasoning_effort`, Cursor ships unset because its model namespace churns per release, Hermes gets an advisory `provider/model-id` since it applies one global `delegation.model`, Claude Code takes the tier name as-is). Assign by what the role costs to get wrong: reviewer `opus`, coder and researcher `sonnet`, explorer and tester `haiku`. Override the mapping — not the tiers — in `~/.hephaestus/models.conf` (user level, every project) or `$HEPHAESTUS_MODELS`; layers merge per key. Generator `--check` ignores overrides so committed adapters stay reproducible across machines.

## Configuration Surfaces

Two mechanisms, split by consumer. Which one a new setting belongs to is decided in this section, not per-PR. The test: **does a script consume the value, or does the agent read it?** Script-consumed → a config file with the `models.conf` layering. Agent-read → CLAUDE.md prose. The failure mode the test blocks is adding a schema and a parser so an LLM can read a value it could already read — indirection that fights what hephaestus is, prose workflows that cause an agent to behave.

| Surface | Consumed by | Layering |
|---|---|---|
| `.ai/models.conf` → `scripts/models.sh` | a **generator**, at build time, baked into the adapters | shipped → `~/.hephaestus/models.conf` → project `.ai/models.conf` → `$HEPHAESTUS_MODELS`, merged per key |
| CLAUDE.md prose — the sections listed in `.ai/conventions.md` under "What the project owns" | the **agent**, at runtime | per project; only `## Development Commands` is required |

Nothing in `scripts/`, `install.sh`, `update.sh`, or `uninstall.sh` parses CLAUDE.md, and `models.conf` has exactly one reader. Keep it that way.

Retry limits and critique thresholds look like the archetypal config value and are not: they are set in `.ai/conventions.md`, restated by the workflows at the point of use, and overridable per project in a `## Workflow Rules` block — read only by the agent. `tests/check_conventions.sh` greps them, but to prove the restatements match the spec; verification is not consumption. Moving them to a config file would add a parser and change nothing about how they are consumed. Settled — do not reopen.

## Improving the Workflow

When the user gives feedback about how commands, agents, or workflows should behave, consider whether the improvement applies broadly across projects. If it does, persist it in the repo (CLAUDE.md or the relevant command/agent file) — not just in local memory. Local memory is per-machine; repo changes propagate to every project using hephaestus.

## Editing Guidelines

When modifying agents or commands:
- Preserve the YAML frontmatter format in agent files (name, description, tools, model, isolation)
- Edit canonical workflow specs in `.ai/workflows/`, not generated `.claude/commands/` adapters.
- Do not hand-edit `.opencode/commands/` or `.opencode/agents/`; regenerate them with `./scripts/sync-opencode-adapters.sh`.
- Do not hand-edit `.agents/skills/*/SKILL.md` or `.codex/agents/`; regenerate them with `./scripts/sync-codex-adapters.sh`.
- Do not hand-edit `.hermes/skills/` or `.hermes/agents/`; regenerate them with `./scripts/sync-hermes-adapters.sh`.
- Do not hand-edit `.cursor/`; regenerate it with `./scripts/sync-cursor-adapters.sh`.
- Preserve the `$ARGUMENTS` placeholder in workflows that receive user input at invocation.
- Retry limits are specified in `.ai/conventions.md` and restated by the workflows at the point of use, in the spec's own nouns — `<count> iterations` or `<count> cycles`, up to two words between. A generic noun ("3 retries") names no loop and is rejected; change the spec first, then the workflows, then run `bash tests/check_conventions.sh`
- Commands that delegate to subagents should specify which agent type to use and what structured output to expect
- Run `./scripts/sync-agent-adapters.sh --check` before shipping adapter changes
- Run `./scripts/sync-opencode-adapters.sh --check` before shipping OpenCode adapter changes
- Run `./scripts/sync-codex-adapters.sh --check` before shipping Codex adapter changes
- Run `./scripts/sync-hermes-adapters.sh --check` before shipping Hermes adapter changes
- Run `./scripts/sync-cursor-adapters.sh --check` before shipping Cursor adapter changes
- Measure and cut text in bytes (`wc -c`, `cut -b`), not `${#var}`/`${var:0:n}`/`[[ =~ [multibyte] ]]` — those switch between bytes and characters with `$LANG`, which makes a generator's output and a test's verdict depend on the machine
- **No bloat**: Replacements must be at least as concise as the original. If the new text is longer without adding information, tighten it. Bloat and drift are the enemies of excellence.

**Workflow metadata** — every `.ai/workflows/*.md` declares its dependencies in frontmatter:
- `requires: agent1, agent2` lists subagents the workflow launches directly. Use `requires: none` if it launches none.
- `chains: /cmd-a, /cmd-b` lists other workflows it invokes. Use `chains: none` if it chains none. Generated Claude adapters render this as `<!-- requires: -->` and `<!-- chains: -->` headers.

Composition rule: if you find yourself copying procedure from `/foo` into `/bar`, replace with a chain instead. Duplicate procedures drift.

## What Target Projects Must Provide

These are NOT in this repo — each installed project owns them (`install.sh --project` scaffolds them):
- `.claude/commands/orient.md` — project-specific context (must be customized)
- `.opencode/commands/orient.md` — OpenCode project-specific context (must be customized if using OpenCode)
- `.agents/skills/orient/` — Codex project-specific orient skill (must be customized if using Codex)
- `.hermes/skills/hephaestus/orient/` — Hermes project-specific orient skill (must be customized if using Hermes)
- `.cursor/commands/orient.md` — Cursor project-specific context (scaffolded, must be customized if using Cursor)
- `.cursor/rules/*.mdc` other than `hephaestus.mdc` — the project's own Cursor rules; hephaestus never writes or removes them
- `.claude/hooks/` — lint/test hooks for the project's tech stack
- `CLAUDE.md` with a "Development Commands" section (test, lint, build commands)
- `changelog.d/`, `CHANGELOG.md`, `scripts/collect-changelog.sh`, `.gitattributes` — only where the project opted in with `install.sh --changelog-fragments`; all four are project-owned and survive uninstall
- `AGENTS.md` — index of available local and shared agents (scaffolded from `templates/AGENTS.md`)
- `.claude/settings.local.json` — project-specific config

## Communication rules

**Never end a response with an indirect pointer to a question.** Banned closers: "Want me to do that?", "Give me the ok and I'll...", "Let's get started?", "Let me know if...", "Sound good?", "Should I proceed?". Either ask the explicit question (with options) or just take the action — no vague closing prompts.
