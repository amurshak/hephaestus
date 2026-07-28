---
name: orient
requires: none
chains: none
---
Orient in the current project before starting work. Run autonomously.

> Each project should own its `orient.md` — `install.sh` scaffolds a customizable template from `templates/orient.md` and never symlinks this one. This generic version is the fallback when no project-specific orient exists (e.g. plugin installs).

## Steps

1. **Detect repo**: `git remote get-url origin` — derive `<owner>/<repo>` for all `gh` commands. If there is no remote, work local-only and skip issue listing.

2. **Load project context**: Read the project's `CLAUDE.md` (conventions, "Development Commands" for test/lint/build) and README. If a project-specific `orient.md` command exists alongside this one, prefer its guidance.

3. **Sync state**: `git fetch --prune origin`, then `git status -sb` and `git log --oneline -5` for recent context.

4. **Find work**:
   ```
   gh issue list --state open --repo <detected-repo>
   ```
   Also check open PRs: `gh pr list --state open --repo <detected-repo>`. If no open issues, self-triage: scan for TODOs, failing checks, doc drift, missing tests.

5. **Report**: current branch and sync state, open issues/PRs, and the recommended next action.

## Next action
Run `/autopilot` — it picks the highest-priority open issue or self-triages if the queue is empty. Or `/start-issue <#>` for a specific issue.
