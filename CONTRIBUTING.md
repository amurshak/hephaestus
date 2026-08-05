# Contributing

> **Audience: contributor** — working **on** hephaestus. Installing and running it is [README.md](README.md); the behavior spec the workflows implement is [`.ai/conventions.md`](.ai/conventions.md). Nothing in this file is true in a project that merely installed hephaestus, and nothing that *is* true there belongs here. Deeper repo internals live in [CLAUDE.md](CLAUDE.md).

## Ground rules

- **Edit canonical sources, never generated adapters.** The behavior spec is `.ai/conventions.md`, workflows live in `.ai/workflows/`, agents in `.claude/agents/`. Everything in `.claude/commands/`, `.opencode/`, `.agents/skills/`, `.codex/agents/`, `.hermes/`, and `.cursor/` is generated — regenerate with:
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

## Forking

Fork hephaestus to customize commands for your org while still pulling upstream updates.

**Safe to modify** — won't conflict on `git merge upstream/master`:
- `templates/` — customize scaffolds for your org's conventions
- `VERSION` — your fork's version track

**Will conflict if modified** — actively developed upstream:
- `.ai/conventions.md`, `.ai/workflows/`, and `.claude/agents/` — the behavior spec, workflows, and agents
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
