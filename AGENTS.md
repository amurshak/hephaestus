# AGENTS.md

## Commands
- Run the full integration suite with `./tests/run.sh`; run a focused file with `./tests/run.sh tests/test_install.sh` or `bash tests/test_install.sh`.
- Check generated Claude command adapters with `./scripts/sync-agent-adapters.sh --check`; regenerate them with `./scripts/sync-agent-adapters.sh`.
- Check generated OpenCode adapters with `./scripts/sync-opencode-adapters.sh --check`; regenerate them with `./scripts/sync-opencode-adapters.sh`.
- Check README composition drift with `bash tests/check_composition.sh`; `tests/test_composition.sh` wraps this plus negative fixture cases.

## Sources Of Truth
- Canonical workflow specs live in `.ai/workflows/*.md`; `.claude/commands/*.md` are generated and should not be edited directly.
- OpenCode command adapters in `.opencode/commands/*.md` are generated from `.ai/workflows/*.md`; OpenCode agent adapters in `.opencode/agent/*.md` are generated from `.claude/agents/*.md`.
- Workflow frontmatter must include `name`, `requires`, and `chains`; use `requires: none` or `chains: none` when empty.
- Preserve `$ARGUMENTS` in workflows that accept user input.
- Agent definitions are hand-edited in `.claude/agents/*.md`; preserve YAML frontmatter, tool lists, isolation mode, and structured output contracts.
- Retry limits live in `CLAUDE.md`; commands should reference them rather than hardcoding counts.

## Repo Shape
- This is a shell/prose workflow repo, not a package-manager project; there is no `package.json` or CI workflow.
- Plugin metadata is in `.claude-plugin/plugin.json`; OpenCode config is `opencode.json`; submodule/headless install tooling is `install.sh`, `update.sh`, `uninstall.sh`, and `loop.sh`.
- `install.sh` symlinks shared agents and commands into a target project, but always treats `.claude/commands/orient.md` as project-specific and scaffolds it from `templates/orient.md` only when missing.
- `install.sh` also symlinks `.opencode/agent` and `.opencode/commands`; `.opencode/commands/orient.md` is project-specific and scaffolded from `templates/orient.md` when missing.
- Symlinks created by `install.sh` are relative paths through `.hephaestus/`; tests assert this.

## Verification Gotchas
- Tests create isolated temporary git repos and copy current uncommitted working-tree changes into fixtures, so focused tests exercise local edits before commit.
- Adapter changes usually need `./scripts/sync-agent-adapters.sh --check`, `./scripts/sync-opencode-adapters.sh --check`, and `./tests/run.sh`; workflow-command drift is a common failure mode.
- README `## Composition` must match command `requires`/`chains` metadata bidirectionally; update README trees when command composition changes.
- `/finish` docs rules are mechanical: every PR needs `CHANGELOG.md`; installer or command changes also need `README.md`; agent or command changes also need `CLAUDE.md`.
- `loop.sh` depends on `claude` on `PATH` and uses a project-scoped lock directory in `/tmp` based on the full working directory path.
