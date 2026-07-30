# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Core Principles

Three ideas shape every design decision:

1. **Simplicity** — One command to deliver an issue. One file to configure quality gates. One install to share across projects. Complexity is a bug.

2. **Self-improvement** — The system critiques its own plans before implementing, reviews its own code before shipping, and finds work when idle. Improvements propagate to every project from one clone.

3. **Autonomy** — Commands run without human intervention. They resolve ambiguity, recover from failures, and wind down cleanly. Stopping to ask is a last resort reserved for irreversible risk.

When in doubt about a design choice, pick the option that is simpler, more self-improving, or more autonomous.

## What This Is

Hephaestus is an implementation of a generic software development workflow pattern for AI coding agents. It encodes the observation that all delivery follows the same loop — orient, plan, critique, implement, review, test, ship, finish — and makes that loop executable, autonomous, and self-correcting. Distributed as one clone of prose workflows plus tool adapters that cause an AI coding agent to behave as a structured delivery system. Installed into the harness config dirs via `./install.sh`, per repo via `./install.sh --project <target>`.

## Development Commands

- **Test**: `./tests/run.sh` — full integration suite (single file: `bash tests/test_<name>.sh`)
- **Lint/drift**: `./scripts/sync-agent-adapters.sh --check`, `./scripts/sync-opencode-adapters.sh --check`, `./scripts/sync-codex-adapters.sh --check`, `./scripts/sync-hermes-adapters.sh --check`, `./scripts/sync-cursor-adapters.sh --check`, `bash tests/check_composition.sh`
- **Build**: none (prose + shell; no compile step)

## Worktrees

- `max:` 3
- `serialize_paths:` `install.sh`, `README.md`
- `setup:` none (no deps to install)

`install.sh` and `README.md` are where adapter, installer, and distribution work collides semantically — two issues rewriting install paths or the install section in the same wave conflict in ways a rebase can't resolve. `CHANGELOG.md` is absent because it is no longer contended: entries are written as one-file-per-PR fragments in `changelog.d/` (see below), so parallel branches never touch a shared anchor.

## Changelog

Entries are **fragments**, not direct edits to CHANGELOG.md: `/ship` writes `changelog.d/<issue-or-slug>.<added|changed|fixed|removed>.md` containing the entry body without the leading `- `. Distinct filenames per PR make merge conflicts structurally impossible.

At release, `scripts/collect-changelog.sh <version>` folds every fragment into a dated `## <version>` section and deletes them (`--preview` to dry-run, `--check` to validate filenames). Hand-written `## Unreleased` content is merged by category, so the transition loses nothing. `.gitattributes` sets `CHANGELOG.md merge=union` as a backstop for any direct edit that slips through.

Target projects adopt the same convention with `install.sh --project --changelog-fragments <path>`, which scaffolds `changelog.d/`, a `CHANGELOG.md` if absent, a copy of `collect-changelog.sh`, and the `.gitattributes` line. It is opt-in — unlike every other scaffold, it changes *where* `/ship` writes — and sticky: later runs detect the adoption from the distributed script and keep it without the flag. `/ship` and `/update-docs` stay conditional on `changelog.d/` existing, so a project that never opts in is unaffected.

## Repository Structure

- `.claude/agents/` — Subagent definitions (coder, reviewer, tester, explorer, researcher) with tool permissions and structured output contracts
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
- **OpenCode adapters are generated too**: `.opencode/commands/` comes from `.ai/workflows/`; `.opencode/agents/` comes from `.claude/agents/`. The generator localizes Claude dialect (worktrees/subagents/TodoWrite → Task/`@agent` + serialize edits, and the `/worktrees` spawn CLI → `opencode --prompt`) and injects slash-command chain notes. Run `./scripts/sync-opencode-adapters.sh` after workflow or agent edits and `./scripts/sync-opencode-adapters.sh --check` in quality gates. Verify a live open session loads them with `bash scripts/verify-opencode-load.sh`.
- **Codex adapters are generated too**: `.agents/skills/*/SKILL.md` comes from `.ai/workflows/`; `.codex/agents/*.toml` comes from `.claude/agents/`. The generator localizes the same Claude dialect, including the `/worktrees` spawn CLI → `codex "<prompt>"`. Run `./scripts/sync-codex-adapters.sh` after workflow or agent edits and `./scripts/sync-codex-adapters.sh --check` in quality gates.
- **Hermes adapters are generated too**: `.hermes/skills/hephaestus/*/SKILL.md` comes from `.ai/workflows/`; `.hermes/agents/*.md` comes from `.claude/agents/`. The generator localizes the same Claude dialect (worktrees/subagents/TodoWrite → `delegate_task` with per-role `toolsets` + the todo tool + serialize edits, and the `/worktrees` spawn CLI → `hermes chat -s hephaestus/<skill> -q`, since `-q` bypasses the slash dispatcher and a bare `/<skill>` would reach the model as literal text) and warns that a delegate inherits neither the parent conversation nor its working directory. Hermes has no project-local skill discovery, so the files stay inert until the project's `.hermes/skills` is wired — `skills.external_dirs` (recommended) or `HERMES_HOME` — `bash scripts/verify-hermes-load.sh` checks that wiring against a live install. Run `./scripts/sync-hermes-adapters.sh` after workflow or agent edits and `--check` in quality gates.
- **Cursor adapters are generated too**: `.cursor/commands/` comes from `.ai/workflows/`; `.cursor/agents/` comes from `.claude/agents/`; `.cursor/rules/hephaestus.mdc` is derived from both. Cursor mechanics that shape the output: command files are injected **verbatim** (frontmatter is stripped only for imported `.claude/commands`), so they carry no YAML and lead with the workflow's opening line — Cursor's hover preview; `$ARGUMENTS`/`$1`… *are* substituted; frontmatter values are not unquoted, so they are emitted bare; `readonly: true` is honoured and emitted for agents with no shell and no edit tools, while `tools:` is only rendered to the model as prose and is never an access control. The `/worktrees` spawn CLI localizes to `cursor-agent`. Run `./scripts/sync-cursor-adapters.sh` after workflow or agent edits and `--check` in quality gates.
- **Commands read the target project's CLAUDE.md** to discover test/lint/build commands. The "Development Commands" section in each installed project drives all quality gates.
- **`/finish` branches on explicit PR state** before cleanup. Merged PRs complete the full close/cleanup/docs flow; auto-merge-pending and manual-merge-needed PRs preserve the issue and PR branch; closed-unmerged PRs abort finish cleanly.
- **`/finish` decides docs sync mechanically** from the PR diff: every PR requires CHANGELOG.md; command or installer changes also require README.md; command or agent changes also require CLAUDE.md. If any required doc is missing, `/finish` runs `/update-docs` and logs the missing files.
- **Repo detection** is done via `git remote get-url origin` — commands never hardcode repo references.
- **orient is project-specific** — it is excluded from symlinking in every harness. `install.sh --project` scaffolds a template from `templates/orient.md` that must be customized. The shipped generic `/orient` covers install paths without install.sh (plugin, manual copy): on first run in an unprepared project it bootstraps the operating requirements — infers a Development Commands section from manifests and scaffolds a project orient — additively, never overwriting.
- **install.sh is idempotent** — re-running refreshes the files it installed and never touches anything else.
- **Changelog fragments are opt-in, then sticky** — `--changelog-fragments` scaffolds the convention; adoption is read back from `<project>/scripts/collect-changelog.sh`, never from `changelog.d/` (scriv owns that directory name too). That copy is code, not a customization point: it is refreshed when it drifts from the clone, under `--force`.
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
- Preserve the YAML frontmatter format in agent files (name, description, tools, model, isolation)
- Edit canonical workflow specs in `.ai/workflows/`, not generated `.claude/commands/` adapters.
- Do not hand-edit `.opencode/commands/` or `.opencode/agents/`; regenerate them with `./scripts/sync-opencode-adapters.sh`.
- Do not hand-edit `.agents/skills/*/SKILL.md` or `.codex/agents/`; regenerate them with `./scripts/sync-codex-adapters.sh`.
- Do not hand-edit `.hermes/skills/` or `.hermes/agents/`; regenerate them with `./scripts/sync-hermes-adapters.sh`.
- Do not hand-edit `.cursor/`; regenerate it with `./scripts/sync-cursor-adapters.sh`.
- Preserve the `$ARGUMENTS` placeholder in workflows that receive user input at invocation.
- Retry limits are defined in "Core Workflow Pattern" above — commands must reference them, not hardcode
- Commands that delegate to subagents should specify which agent type to use and what structured output to expect
- Run `./scripts/sync-agent-adapters.sh --check` before shipping adapter changes
- Run `./scripts/sync-opencode-adapters.sh --check` before shipping OpenCode adapter changes
- Run `./scripts/sync-codex-adapters.sh --check` before shipping Codex adapter changes
- Run `./scripts/sync-hermes-adapters.sh --check` before shipping Hermes adapter changes
- Run `./scripts/sync-cursor-adapters.sh --check` before shipping Cursor adapter changes
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
