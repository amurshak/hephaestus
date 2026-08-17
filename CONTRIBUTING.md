# Contributing

> **Audience: contributor** — working **on** hephaestus. Installing and running it is [README.md](README.md); the behavior spec the workflows implement is [`.ai/conventions.md`](.ai/conventions.md). Nothing in this file is true in a project that merely installed hephaestus, and nothing that *is* true there belongs here. Deeper repo internals live in [CLAUDE.md](CLAUDE.md).

## Ground rules

- **Edit canonical sources, never generated adapters.** The behavior spec is `.ai/conventions.md`, workflows live in `.ai/workflows/`, agents in `.ai/agents/`. Everything in `.claude/commands/`, `.claude/agents/`, `.opencode/`, `.agents/skills/`, `.codex/agents/`, `.hermes/`, and `.cursor/` is generated — regenerate with:
  ```bash
  ./scripts/sync-agent-adapters.sh
  ./scripts/sync-opencode-adapters.sh
  ./scripts/sync-codex-adapters.sh
  ./scripts/sync-hermes-adapters.sh
  ./scripts/sync-cursor-adapters.sh
  ```
- **Run the gates before submitting:**
  ```bash
  ./tests/run.sh                               # integration suite
  ./scripts/sync-agent-adapters.sh --check     # Claude adapter drift
  ./scripts/sync-opencode-adapters.sh --check  # OpenCode adapter drift
  ./scripts/sync-codex-adapters.sh --check     # Codex adapter drift
  ./scripts/sync-hermes-adapters.sh --check    # Hermes adapter drift
  ./scripts/sync-cursor-adapters.sh --check    # Cursor adapter drift
  bash tests/check_composition.sh              # README composition drift
  bash tests/check_conventions.sh              # workflows vs .ai/conventions.md drift
  ./scripts/collect-changelog.sh --check       # changelog fragment names
  bash scripts/verify-opencode-load.sh         # optional live OpenCode load (skips if CLI absent)
  bash scripts/verify-codex-load.sh            # optional live Codex load (skips if CLI absent)
  ```
- **Bash 3.2 compatibility** — scripts must run on stock macOS bash: no associative arrays, no `mapfile`, portable `sed -i.bak`.
- **No bloat** — replacements must be at least as concise as the original.
- **Keep the two audiences apart.** Before adding a sentence, ask whether it would still be true in a project that merely installed hephaestus. Yes → it is product, and belongs in `.ai/conventions.md` or a workflow. No → it is contributor, and belongs here or in CLAUDE.md. Retry limits are specified once in `.ai/conventions.md`; the workflows restate them at the point of use because an installed project has no `.ai/` to read, and `tests/check_conventions.sh` fails if the two disagree. Never write a by-name reference like "per CLAUDE.md retry limits" — that is what forced `/orient` to retype the limits into every installed project.
- Every PR adds a changelog fragment: `changelog.d/<issue-or-slug>.<added|changed|fixed|removed>.md`, entry body only, no leading `- `. Do not edit `CHANGELOG.md` — `scripts/collect-changelog.sh <version>` assembles it at release. Validate with `./scripts/collect-changelog.sh --check`.

## Verifying harness behavior

A generator encodes claims about a harness — where it discovers skills, how it dispatches a slash command, whether `readonly` is enforced. Those claims go stale silently when the harness ships a release. Do not reason about them from documentation; probe the installed CLI and record what you measured.

The procedure, as used to settle the Cursor `readonly` semantics in #147 and the Codex spawn form in #161:

1. **Probe the live CLI** — smallest command that answers the question (`codex --help`, a one-file skill in a scratch dir, a `cursor-agent` run against a fixture). Never a docs page.
2. **Record the version you measured**, in the note and in the commit message: "measured against codex-cli 0.145.0". A claim without a version is unfalsifiable.
3. **Encode it where it will break loudly** — a `scripts/verify-*-load.sh` guard (`verify-opencode-load.sh`, `verify-codex-load.sh`, `verify-hermes-load.sh`) that a maintainer with the CLI installed runs, and that skips cleanly without it. Prose in CLAUDE.md alone does not catch a regression.
4. **Then change the generator**, and only then.

The harness mechanics each generator relies on are documented in CLAUDE.md § Key Design Constraints, one bullet per harness.

## Dogfooding boundary

The clone is symlinked into `~/.claude` and the other harness config dirs, so editing `.ai/workflows/ship.md` and regenerating changes the `/ship` running in the session doing the edit. Intended when you are testing a workflow change; a silent trap when you are not — a mid-session regeneration can alter the command that is about to run.

Work on a workflow in a `/worktrees` worktree, where the edit is local until merge, or regenerate as the last step before committing rather than mid-flow. If a command starts behaving unlike its file, check `git status` in the clone before debugging the harness.

## Forking

Fork hephaestus to customize commands for your org while still pulling upstream updates.

**Safe to modify** — won't conflict on `git merge upstream/master`:
- `templates/` — customize scaffolds for your org's conventions
- `VERSION` — your fork's version track

**Will conflict if modified** — actively developed upstream:
- `.ai/conventions.md`, `.ai/workflows/`, and `.ai/agents/` — the behavior spec, workflows, and agents
- `.claude/commands/` — generated Claude adapters; update via `scripts/sync-agent-adapters.sh`
- `.opencode/commands/` and `.opencode/agents/` — generated OpenCode adapters; update via `scripts/sync-opencode-adapters.sh`
- `.agents/skills/` and `.codex/agents/` — generated Codex adapters; update via `scripts/sync-codex-adapters.sh`
- `.hermes/skills/` and `.hermes/agents/` — generated Hermes adapters; update via `scripts/sync-hermes-adapters.sh`
- `.cursor/commands/`, `.cursor/agents/`, `.cursor/rules/hephaestus.mdc` — generated Cursor adapters; update via `scripts/sync-cursor-adapters.sh`
- `install.sh`, `update.sh`, `uninstall.sh` — the install tooling
- `.claude-plugin/plugin.json` — the plugin manifest

```bash
git remote add upstream https://github.com/amurshak/hephaestus.git
git fetch upstream
git merge upstream/master
```

## What we most want

**Adapter generators for new harnesses.** The pattern is `scripts/sync-opencode-adapters.sh` / `scripts/sync-codex-adapters.sh` / `scripts/sync-cursor-adapters.sh`: a generator that emits your harness's format from the canonical specs, with sync + `--check` modes, stale-adapter detection, and tests mirroring `tests/test_opencode_adapters.sh`.

## Conduct

Be direct, cite evidence, assume good faith. Critique the work, not the person — the reviewer agent's standard applies to humans too: findings need evidence or they're questions.
