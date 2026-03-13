# Changelog

## Unreleased

### Fixed
- `loop.sh` killed itself on the first failed `claude` run: `set -euo pipefail` caused the entire loop to exit when the `claude | tee` pipeline returned non-zero. Removed `-e`, use `PIPESTATUS[0]` to capture claude's exit code, log the error, and continue looping.
- `loop.sh` had no protection against concurrent instances, non-numeric interval arguments, or `claude` being absent from PATH. Added `mkdir`-based atomic lockfile (project-scoped), numeric+range validation, and `command -v claude` guard.
- `finish.md` branch cleanup silently skipped all squash-merged branches: `git branch --merged` never lists them because squash commits are not in the target's ancestry. Replaced with `gh pr view --json headRefName` to get the branch name directly, and switched to `git branch -D` (force delete). Also added `git checkout $BASE` before deletion (cannot delete the checked-out branch) and remote branch cleanup.
- `refactor.md` had no ship path — Phase 4 only printed a report with no commit/push/PR steps. Added Phase 4 (Ship) and renumbered Report to Phase 5.
- `finish.md` was redundantly updating CHANGELOG after `/ship` already did it, causing triple-updates in autopilot runs. Removed; added explicit note that CHANGELOG is ship's responsibility.
- `finish.md` stash pop had no guard — `git stash pop` would error if no stash exists. Now checks before popping.
- `start-issue.md` ran code critique and tests together in one phase with no separate retry path for critique failures. Split into Phase 4 (critique, max 3 retries) and Phase 5 (tests).
- `researcher.md` output contract was missing `Conflicting viewpoints` and `Recommendations` fields that `research.md` expects from subagents, causing data to be silently dropped during synthesis.
- `update.sh` silently missed new agents/commands added after initial install. Now re-runs `install.sh` after pulling to repair and add any new symlinks.
- `reviewer.md` missing test adequacy and CLAUDE.md compliance evaluation dimensions — pre-ship critique gate now checks for untested risky behavior and project convention violations.
- `create-issue.md` drafted labels in body text but never passed `--label` to `gh issue create`. Now runs `gh label list` first and passes labels via `--label` flags.

### Added
- `loop.sh` — headless autonomous loop that runs `/autopilot` in a fresh Claude session on a configurable interval; each run gets latest Claude capabilities and a clean context window
- `orient.md` command — cold-session orientation with repo context, structure, and next-action guidance
- Prompt injection protection in `researcher.md` — fetched content treated as untrusted; embedded instructions flagged before execution
- `.gitignore` — excludes `settings.local.json` (project-specific) and `*.lock` runtime files

### Fixed
- `ship.md` and `tester.md` hardcoded `origin/master` in git diff ranges, causing empty output for projects using `main` as the default branch. Now detects the base branch dynamically via `git symbolic-ref` (then `git remote show origin`, then `master` as last resort).
