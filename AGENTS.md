# AGENTS.md

## Commands
- Run the full integration suite with `./tests/run.sh`; run a focused file with `./tests/run.sh tests/test_install.sh` or `bash tests/test_install.sh`.
- Check generated Claude command adapters with `./scripts/sync-agent-adapters.sh --check`; regenerate them with `./scripts/sync-agent-adapters.sh`.
- Check generated OpenCode adapters with `./scripts/sync-opencode-adapters.sh --check`; regenerate them with `./scripts/sync-opencode-adapters.sh`.
- Confirm OpenCode loads project adapters (`opencode debug config` or `bash scripts/verify-opencode-load.sh`); start OpenCode from the project root.
- Check generated Codex adapters with `./scripts/sync-codex-adapters.sh --check`; regenerate them with `./scripts/sync-codex-adapters.sh`.
- Confirm Codex still takes the positional-prompt spawn form, and that the skills and agent roles are in a root it reads, with `bash scripts/verify-codex-load.sh`; pass a project path to check an installed project (the shared set lives in `$CODEX_HOME` after a `--project` install).
- Check generated Cursor adapters with `./scripts/sync-cursor-adapters.sh --check`; regenerate them with `./scripts/sync-cursor-adapters.sh`.
- Check generated Hermes adapters with `./scripts/sync-hermes-adapters.sh --check`; regenerate them with `./scripts/sync-hermes-adapters.sh`.
- Confirm Hermes discovers project skills with `bash scripts/verify-hermes-load.sh` — Hermes needs the project's `.hermes/skills` wired via `skills.external_dirs` (recommended) or `HERMES_HOME`; pass a project path to check an installed project.
- Check README composition drift with `bash tests/check_composition.sh`; `tests/test_composition.sh` wraps this plus negative fixture cases.

## Sources Of Truth
- Canonical workflow specs live in `.ai/workflows/*.md`; `.claude/commands/*.md` are generated and should not be edited directly.
- OpenCode command adapters in `.opencode/commands/*.md` are generated from `.ai/workflows/*.md`; OpenCode agent adapters in `.opencode/agents/*.md` are generated from `.claude/agents/*.md`.
- Codex skill adapters in `.agents/skills/*/SKILL.md` are generated from `.ai/workflows/*.md`; Codex agent roles in `.codex/agents/*.toml` are generated from `.claude/agents/*.md`.
- Hermes skill adapters in `.hermes/skills/hephaestus/*/SKILL.md` are generated from `.ai/workflows/*.md`; Hermes `delegate_task` briefs in `.hermes/agents/*.md` are generated from `.claude/agents/*.md`.
- Workflow frontmatter must include `name`, `requires`, and `chains`; use `requires: none` or `chains: none` when empty.
- Preserve `$ARGUMENTS` in workflows that accept user input.
- Agent definitions are hand-edited in `.claude/agents/*.md`; preserve YAML frontmatter, tool lists, isolation mode, and structured output contracts.
- Retry limits live in `CLAUDE.md`; commands should reference them rather than hardcoding counts.

## Repo Shape
- This is a shell/prose workflow repo, not a package-manager project; there is no `package.json`. CI is `.github/workflows/tests.yml` (runs `tests/run.sh`, every adapter drift check, and the composition check).
- Plugin metadata is in `.claude-plugin/plugin.json`; OpenCode config is `opencode.json`; install/headless tooling is `install.sh`, `update.sh`, `uninstall.sh`, and `loop.sh`.
- `install.sh` (no args) symlinks the shared adapters into the harness config dirs — `~/.claude/{commands,agents}`, `~/.config/opencode/{commands,agents}`, `~/.codex/{skills,agents}`, `~/.hermes/{skills/hephaestus,agents}` — honoring `$CLAUDE_CONFIG_DIR`, `$XDG_CONFIG_HOME`, `$CODEX_HOME`, and `$HERMES_HOME`. Links are absolute into the clone; tests assert this.
- `install.sh --project <path>` scaffolds only what a repo owns: `orient` for all four harnesses (from `templates/orient.md`, never overwritten), `AGENTS.md`, `opencode.json`, `.hermes/.gitignore`. `--vendor <path>` does that plus copies the shared set into the repo; `--migrate` first strips a pre-2.2 `.hephaestus` submodule install.
- Every mode writes a manifest of the paths it created — `$XDG_STATE_HOME/hephaestus/manifest` or `<project>/.heph-manifest` — and later runs read it to decide what is safe to refresh or remove.

## Verification Gotchas
- Tests create isolated temporary git repos and copy current uncommitted working-tree changes into fixtures, so focused tests exercise local edits before commit. Install tests call `sandbox_home` so a user-level install under test can never touch the real `~/.claude`, `~/.codex`, `~/.config/opencode`, or `~/.hermes`.
- Adapter changes usually need every `./scripts/sync-*-adapters.sh --check` and `./tests/run.sh`; workflow-command drift is a common failure mode.
- README `## Composition` must match command `requires`/`chains` metadata bidirectionally; update README trees when command composition changes.
- `/finish` docs rules are mechanical: every PR needs `CHANGELOG.md`; installer or command changes also need `README.md`; agent or command changes also need `CLAUDE.md`.
- `loop.sh` depends on `claude` on `PATH` and uses a project-scoped lock directory in `/tmp` based on the full working directory path.
