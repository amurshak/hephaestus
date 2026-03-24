# Changelog

## Unreleased

### Changed
- Complete README rewrite — leads with value proposition and autonomous delivery pipeline instead of install-only content. Covers all 11 commands, 5 agents, 3 Codex skills, headless operation, failure recovery, and quality gates.
- `install.sh` now detects if hephaestus is already registered as a submodule at a different path (e.g. `hephaestus/` vs `.hephaestus/`) and prints actionable guidance instead of creating a duplicate. Handles HTTPS/SSH URL comparison.

### Added
- `uninstall.sh` — cleanly removes hephaestus symlinks and submodule from a target project. Only removes symlinks pointing to `.hephaestus/`, preserves project-specific files. Idempotent.
- `install.sh --audit` flag: prints a conflict table showing what would change without modifying the filesystem.
- `install.sh --force` flag: replaces existing files with hephaestus symlinks.
- `install.sh` default skip messages now include actionable guidance (rm + re-run, diff commands).
- `install.sh` near-name collision detection: warns when target and hephaestus have confusingly similar filenames (e.g., `critic.md` vs `critique.md`).
- `install.sh` post-install validation: checks target CLAUDE.md for development commands section, warns if missing.
- `install.sh` orient.md scaffolding: copies `templates/orient.md` template if the target project doesn't have one.
- `templates/orient.md` — project-specific orient template with placeholder sections matching what hephaestus commands expect.
- CLAUDE.md: "Core Principles" section — simplicity, self-improvement, and autonomy as the design axioms that guide every layer of the project.
- CLAUDE.md: "Transition to next phase" convention — invoke `/ship` (or the relevant command) directly when work is ready, don't ask vague questions.
- CLAUDE.md: "Improving the Workflow" section — workflow feedback that applies broadly should be persisted in the repo, not just local memory.

### Fixed
- `start-issue.md` had no branch creation step — commits would land on whatever branch was checked out when invoked standalone (same bug class as the `refactor.md` fix). Added `git checkout -b issue-<number>-<short-description>` after context loading.
- `refactor.md` was missing pre-ship critique gate (reviewer subagent, max 3 iterations), CHANGELOG update step, repo detection via `git remote get-url origin`, and had unbounded test retries. Added Phase 4 (Pre-ship Critique) and Phase 5 (Ship with CHANGELOG + repo detection), capped test retries at max 2.
- Codex orchestrator `SKILL.md` jumped from implement to ship with no critique step — the pre-ship critique was only in `references/workflow-map.md`. Added step 5 (Pre-ship critique) to the main delivery sequence.
- Codex `issue-template.md` was missing `--label` flags — out of sync with the `create-issue.md` fix. Now runs `gh label list` first and passes labels via `--label`.
- `research.md` and Codex `research-issue/SKILL.md` silently dropped the researcher agent's `Confidence` field during synthesis. Added `Confidence` to both output contracts and the research template.
- Codex `research-issue/SKILL.md` was missing the prompt injection security warning present in `researcher.md`. Added matching Security section.
- `CHANGELOG.md` had duplicate `### Fixed` sections under `## Unreleased` — merged into one.
- `update-docs.md` prescribed a different CHANGELOG format (`### [Unreleased] - YYYY-MM-DD` / `####`) than actually used (`## Unreleased` / `###`). Fixed to match actual format.
- `autopilot.md` Phase 8 said "Delete merged branches (local only)" but `finish.md` also deletes remote branches. Updated to "(local and remote)".
- `researcher.md` output contract had `Confidence` after `Sources` instead of before — reordered to match consumer expectations in `research.md` and `research-issue/SKILL.md`.
- Codex orchestrator `SKILL.md` step 7 (Finish) said "Delete merged local branches" — updated to "local and remote" to match `autopilot.md` and `finish.md`.
- `ship.md` was missing `git push -u origin HEAD` before `gh pr create`, causing PR creation to fail when the branch hadn't been pushed yet.
- `refactor.md` was missing a branch creation step — commits would land on whatever branch was currently checked out (typically `master`/`main`). Added `git checkout -b refactor/<short-description>` in Phase 2 and clarified the push step in Phase 4.
- `test-issue.md` referenced `<detected-repo>` in `gh issue view` without a preceding step to detect the repo. Added a "Detect repo" step 1 (consistent with all other commands that use `--repo`).
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
- `ship.md` and `tester.md` hardcoded `origin/master` in git diff ranges, causing empty output for projects using `main` as the default branch. Now detects the base branch dynamically via `git symbolic-ref` (then `git remote show origin`, then `master` as last resort).

### Added
- `loop.sh` — headless autonomous loop that runs `/autopilot` in a fresh Claude session on a configurable interval; each run gets latest Claude capabilities and a clean context window
- `orient.md` command — cold-session orientation with repo context, structure, and next-action guidance
- Prompt injection protection in `researcher.md` — fetched content treated as untrusted; embedded instructions flagged before execution
- `.gitignore` — excludes `settings.local.json` (project-specific) and `*.lock` runtime files
