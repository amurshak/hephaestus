<!-- requires: none -->
# Orient — Hephaestus

## Repo
`amurshak/hephaestus` — portable AI workflow toolkit distributed as a git submodule.

## What it is
Shared agents and slash commands that enable autonomous issue-to-ship workflows. Installed into other projects via `./install.sh <target>`. Not a standalone app.

## Structure
- `.claude/agents/` — coder, reviewer, tester, explorer, researcher
- `.claude/commands/` — autopilot, start-issue, ship, finish, critique, refactor, research, create-issue, test-issue, update-docs, update-hephaestus, orient
- `install.sh` / `update.sh` — submodule install/update scripts
- `CHANGELOG.md` — release history

## Development commands
- **Tests**: `./tests/run.sh` — integration tests for shell scripts (install, update, uninstall)
- **Quality gates**: code review (reviewer subagent) + test suite

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
