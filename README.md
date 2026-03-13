# hephaestus

The machine that builds the machine. A portable AI workflow toolkit — agents, commands, and skills for Claude Code and Codex — shared across projects via git submodule.

## Contents

```
.claude/
  agents/     coder, reviewer, tester, explorer, researcher
  commands/   create-issue, start-issue, test-issue, ship, finish,
              critique, research, refactor, autopilot, update-docs
.codex/
  skills/     orchestrator, critic, research-issue
```

## Install into a project

From this repo's directory:

```bash
chmod +x install.sh
./install.sh /path/to/your/project
```

This:
1. Adds `hephaestus` as a `.hephaestus` git submodule in your project
2. Creates symlinks in `.claude/agents/`, `.claude/commands/`, `.codex/skills/`
3. Never overwrites existing project-specific files

## Pull updates

From inside any project that has `hephaestus` installed:

```bash
git submodule update --remote .hephaestus
# or use the bundled helper:
/path/to/hephaestus/update.sh
```

## What stays project-specific

These are **not** in this repo — each project owns them:

| File | Why project-specific |
|---|---|
| `.claude/commands/orient.md` | References project GitHub repos and structure |
| `.claude/hooks/` | Lint/test commands vary by tech stack |
| `AGENTS.md` | Skill index references local skill paths |
| `.codex/settings.local.json` | Skill paths and memory config |
| `.claude/settings.local.json` | Hook paths and allowed permissions |

## After installing, add these to your project

1. **`.claude/commands/orient.md`** — project-specific session startup (git status, open issues, changelog, next action)
2. **`.claude/hooks/lint-on-commit.sh`** — run your lint command before commits
3. **`.claude/hooks/protect-files.sh`** — block accidental edits to `.env`, lock files, etc.
4. **`AGENTS.md`** — skill index listing local + shared skills

## How commands work

All commands read CLAUDE.md to discover project-specific test, lint, and build commands. Keep your CLAUDE.md's "Development Commands" section up to date and the shared commands will automatically use the right commands for your project.
