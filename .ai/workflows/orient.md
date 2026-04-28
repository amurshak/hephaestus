---
name: orient
requires: none
chains: none
---
# Orient — Hephaestus

## Repo
`amurshak/hephaestus` — a generic software development workflow pattern, implemented in Claude Code.

## What it is
Eight-phase delivery loop (orient → plan → critique → implement → review → test → ship → finish) encoded as slash commands and agent definitions. Distributed as a git submodule installed into other projects via `./install.sh <target>`.

## Structure
- `.claude/agents/` — coder, reviewer, tester, explorer, researcher
- `.claude/commands/` — autopilot, start-issue, ship, finish, critique, refactor, research, create-issue, test-issue, update-docs, update-hephaestus, orient
- `install.sh` / `update.sh` — submodule install/update scripts
- `CHANGELOG.md` — release history

## Development commands
- **Tests**: `./tests/run.sh` — integration tests for shell scripts (install, update, uninstall)
- **Quality gates**: code review (reviewer subagent) + test suite

## Sync state
First, sync with remote and prune stale tracking refs (branches GitHub deleted on merge but git still has):
```
git fetch --prune origin
```

## Find work
```
gh issue list --state open --repo amurshak/hephaestus
```
If no open issues, self-triage: scan for TODOs, inconsistencies between agents/commands, missing functionality.

## Next action
Run `/autopilot` — it will pick the highest-priority open issue or self-triage if the queue is empty.

## Key constraints
- Symlinks in installed projects are relative — don't break paths when renaming files
- `orient.md` is excluded from `install.sh` symlinking (each project owns its own)
- `settings.local.json` pre-approves `Bash(*) + WebFetch(*)` for this project
