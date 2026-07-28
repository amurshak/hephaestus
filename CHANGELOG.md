# Changelog

## Unreleased

### Added
- **`/worktrees` — parallel multi-session orchestration** (#109): survey existing issue worktrees, auto-reap merged+clean ones (never dirty or unpushed), wave-plan the largest mutually non-conflicting set of open issues under a configurable cap (`## Worktrees` section in CLAUDE.md: `max`, `serialize_paths` hotspots, `setup`), create sibling worktrees with config propagation and single-sourced env symlinks, and spawn a seeded Claude Code session per issue (macOS Terminal automation with manual-command fallback). Extends parallelization to three levels: within-issue (coder subagents), across-issues (worktree sessions), across-time (`loop.sh`). Synthesized from two sibling implementations — one contributed proven worktree mechanics, the other wave/dependency scheduling.
- **Hook templates** (#114): `templates/hooks/protect-files.sh` (blocks Edit/Write to `.env*`, `.git/` internals, and path-traversal escapes; works as-is) and `templates/hooks/lint-on-commit.sh` (blocks `git commit` while lint fails; set `LINT_CMD`). Deterministic backstops for the prose quality gates, adapted from a battle-tested private implementation of this workflow pattern; README documents the curl install and settings wiring.
- **Risk-adaptive scored critique** (#110): `/critique`'s code mode now scores diff risk (auth/secrets +2; untested code, cross-boundary, workflow files, migrations +1 each) and maps it to review depth — L1 focused, L2 thorough with pre-mortem, L2+Double (two independent reviewers, lower score wins). Docs-only diffs auto-pass without spawning a reviewer. Reviewers return 0–100 scores mapped onto the existing verdicts (PASS ≥85, PASS WITH CHANGES 70–84, FAIL <70; blocking issues always cap at FAIL); plan critique scores dimensions 1–10 (SOUND ≥80). The reviewer agent gains an evidence requirement (uncited concerns become questions, not findings), a disconfirmation quota, and a pre-mortem protocol. All four sibling workflow implementations converged on scored critique independently — adopted from that evidence.
- **Ship evidence gate** (#112): before creating the PR, `/ship` verifies the composed body contains no unchecked `- [ ]` items or placeholder text, and that every checked quality-gate line corresponds to a gate actually run this session. Adopted from a sibling implementation's Evidence Gate pattern.
- **Critic calibration in `/finish`** (#113): the retrospective now records whether the pre-ship critique verdict held up post-merge (accurate / false-negative / false-positive, from post-merge fix commits and related issues) as a searchable line in the issue comment. Adopted from a sibling implementation's calibration loop, translated to repo-as-memory.

### Fixed
- **Dangling "per CLAUDE.md retry limits" reference on plugin/manual installs** (#111): distributed workflows reference retry limits that lived only in hephaestus's own CLAUDE.md, which plugin and manual-copy users never receive (plugin-level CLAUDE.md doesn't enter session context). `/orient`'s bootstrap now writes a compact "Workflow Rules" block (limits + wind-down convention) into the target CLAUDE.md, and `templates/CLAUDE.md.snippet` carries the same block. Found by cross-checking a sibling implementation of this workflow pattern.

## 2.0.2 — 2026-07-28

### Changed
- **`/orient` bootstraps unprepared projects**: hephaestus is an adjunct to the host codebase, but install paths without `install.sh` (plugin, manual copy) had no onboarding — commands landed in a project with none of the workflow's operating requirements established. The shipped generic `/orient` now runs a setup check before orienting: infers a CLAUDE.md "Development Commands" section from project manifests (marked `inferred — verify`), scaffolds a project-specific orient with the detected repo/structure/commands, and checks `gh` auth. All writes are additive (never overwrites); a silent no-op on prepared projects.

## 2.0.1 — 2026-07-28

### Fixed
- **Plugin manifest rejected by Claude Code**: `plugin.json` declared `"agents"` as a directory path, which the plugin schema rejects (`agents: Invalid input`) — plugin installs failed at validation. The field now enumerates the five agent files individually (the schema-valid form, confirmed via `claude plugin validate --strict`). A new test locks the manifest list to the `.claude/agents/` directory contents so added/removed agents can't silently drift out of the manifest. Caught by live install verification minutes after the repo went public.

## 2.0.0 — 2026-07-28

First public release. Hephaestus becomes a harness-neutral workflow core (`.ai/workflows/` + `.claude/agents/`) with generated adapters per harness, distributed three ways: Claude Code plugin, git submodule, or manual copy/symlink.

### Added
- `LICENSE` — MIT, matching the license declared in the plugin manifests.
- GitHub Actions CI (`.github/workflows/tests.yml`) — runs the full integration suite, both adapter drift checks, and the README composition check on every push and PR.
- **OpenCode interoperability**: added root `opencode.json` that loads `AGENTS.md` and `CLAUDE.md`, generated OpenCode command adapters under `.opencode/commands/`, generated OpenCode subagent adapters under `.opencode/agents/`, and `scripts/sync-opencode-adapters.sh` with drift detection. `install.sh`, `update.sh`, and `uninstall.sh` now handle OpenCode adapters alongside Claude adapters, with `.opencode/commands/orient.md` protected as project-specific. Added `tests/test_opencode_adapters.sh` plus install/update/uninstall coverage for OpenCode symlinks.
- **Tool-neutral workflow core and adapter drift check**: canonical workflow specs now live in `.ai/workflows/*.md` with `name`, `requires`, and `chains` frontmatter. `.claude/commands/*.md` are generated Claude adapters from those specs via `scripts/sync-agent-adapters.sh`; `--check` detects wrapper drift. Added `tests/test_agent_adapters.sh` to verify adapter sync, drift detection, and metadata completeness.
- Integration test suite for `install.sh`, `update.sh`, and `uninstall.sh` — run via `./tests/run.sh`; tests use isolated temp git repos (no network required). Additional integration tests for `loop.sh` cover input validation, `claude`-not-found guard, lockfile lifecycle, hash uniqueness, and default arguments.
- Commands declare agent dependencies via `<!-- requires: agent1, agent2 -->` on line 1. install.sh validates that required agents are installed and warns about missing dependencies.
- README: "Forking and customization" section — which files are safe to modify, how to pull upstream updates.
- **README Composition tree drift detection** (#87): new `tests/check_composition.sh` parses `<!-- requires: -->` and `<!-- chains: -->` headers from each command file and runs a bidirectional check — every `(requires: …)` annotation in the README's `## Composition` section must match the file metadata, AND every parent→child edge in the README tree must equal the parent's `chains:` list (catches edges removed from a file but kept in README, plus phantom children added to README that no file declares). Covered by `tests/test_composition.sh` with two negative cases (mutated requires:, dropped chain edge) verified against fixtures. `/update-docs` step 5 invokes the verifier; drift exits non-zero with a per-line report. The strengthened verifier surfaced one real drift on first run: `/refactor` declares `chains: /ship, /finish` but had no Composition tree — only a prose mention. README now renders both `/autopilot` and `/refactor` trees. Closes the #84(b) gap left when #85 added the section without enforcement.

### Changed
- **Distributed workflows generalized for any target project** (release audit): `/orient` rewritten generic — detects the repo via `git remote`, reads the project's CLAUDE.md/README, and defers to a project-specific orient when one exists (fixes the plugin path shipping hephaestus's own orient); `/update-docs` guards the composition check behind a file-existence test and creates CHANGELOG.md when a project has none; `/finish` states its docs-required triggers generically with a per-project override point and skips issue-close when the PR closes no issue; `/autopilot` now runs `/finish` for unmerged PRs (it branches on PR state); `/ship` and the tester agent infer quality gates from project manifests (marked `INFERRED`) when CLAUDE.md lacks a Development Commands section; `/update-hephaestus` detects plugin installs and redirects to `/plugin marketplace update`.
- **`.opencode/agents/` (plural)**: the OpenCode agent adapter directory renamed from the soft-deprecated singular `agent/` to the canonical plural form; OpenCode loads both, but new installs use the forward-compatible name.
- **`tests/check_composition.sh` is bash-3.2 compatible**: associative arrays replaced with delimited-line records, so the verifier runs on stock macOS bash.
- **Plugin manifest versioned**: `plugin.json` declares `"version": "2.0.0"`; marketplace owner email switched to the GitHub noreply address.
- **Communication rules in CLAUDE.md**: added a repo guidance section banning vague indirect closing prompts, so agents either ask explicit questions or take the next action.
- **`/finish` partial-success state handling** (#90): Step 2 now loads a single PR state payload (`state`, `mergedAt`, `mergeStateStatus`, `autoMergeRequest`, branch identity, and `closingIssuesReferences`) and branches deterministically for merged, auto-merge-pending, manual-merge-needed, and closed-without-merge states. Step 3 resolves the shipped issue from the PR's closing references, treats already-closed issues as a clean no-op, and logs argument mismatches. Step 4 preserves open PR branches during partial cleanup and re-reads `headRefName` before deletion. Added `tests/test_finish_state_branches.sh` to lock in the state matrix.
- **Deterministic `/finish` docs decision** (#89): Step 7 now derives required docs mechanically from the merged PR diff instead of judging whether the "docs surface" was covered. Every PR requires `CHANGELOG.md`; installer/script and command changes require `README.md`; agent or command changes require `CLAUDE.md`. `/finish` must log either an auto-detected skip or an auto-detected `/update-docs` run with the missing files. Added `tests/test_finish_docs_rule.sh` to cover the matrix and the command's logging contract.
- **`finish.md` step 7 permits a logged `/update-docs` skip** when the PR commit already updated the docs surface (CHANGELOG plus any other files the change required). Default remains "run it"; silent skips are still drift, but logged skips are explicitly auditable in the session summary. Tightens a procedure that previously forced redundant no-op runs.
- **README demote submodule, add Composition section** (#85): plugin install becomes the mainline narrative throughout the README. The submodule path consolidates from three sections (Adopting in an existing project, Headless mode, Forking and customization) into a single "Submodule install (for headless mode and forking)" section. New `## Composition` section after Design choices shows the `/autopilot` chain as a tree, with each command's `requires:` declared inline — built directly from the `chains:` metadata introduced in #80.
- **README opening rewrite** (#79): leads with the universal delivery loop and OODA framing before revealing `/autopilot`. Replaces the 8-phase pipeline diagram in the opening with the user-level command loop (`/orient → /create-issue → /start-issue → ⟨implementation⟩ → /ship → /finish`). The 8 phases remain in `## The pattern` as internal mechanics. Adds a Contents TOC. Trims AI-flavored phrasing (em-dash sandwiches, aphoristic closers, "stratified by least-privilege tool access").
- **Command composition refactor** (#80): commands are now single sources of truth for their concern, with composite commands chaining rather than inlining. `/autopilot` reduced from 9 inline phases to 4 (Phase 0 self-triage, Phase 1 orient, Phase 2 → `/start-issue`, Phase 3 → `/ship`, Phase 4 → `/finish`). `/start-issue` and `/refactor` drop their pre-ship critique (`/ship` owns that gate). `/ship`'s pre-push critique routes through `/critique`. `/finish` chains `/update-docs` as Step 7. New `<!-- chains: ... -->` header declares command-on-command composition; CLAUDE.md "Editing Guidelines" documents the convention. Net diff: −43 lines across 5 command files. Eliminates duplicate reviewer runs (autopilot pre-ship + ship pre-push were running the same critique twice). Follow-ups: #83 (verify autopilot end-to-end), #84 (README Composition section).
- Docs reframed around the generic-workflow-pattern thesis: README leads with the 8-phase delivery loop as the core idea, adds sections for design choices, the critique system, OODA-loop correspondence, and memory-through-external-systems. CLAUDE.md principles tightened; orient.md description matches the new framing.
- `refactor.md` now enforces a plan-critique loop before implementation (was "proceed immediately"). Same pattern as start-issue.md.
- Retry limits centralized in CLAUDE.md "Core Workflow Pattern" section. All commands now reference "per CLAUDE.md retry limits" instead of hardcoding numbers.
- `finish.md` adds a retrospective step: captures what failed, what fixed it, and reusable insights as a comment on the closed issue. Skipped if pipeline ran cleanly.
- Agents now provide richer output on failure: coder suggests alternatives on BLOCKED, tester reports likely cause and suggested action on FAIL, reviewer classifies blocking issues as fixable vs architectural.
- CLAUDE.md autonomy conventions: added git conflict detection and recovery pattern (rebase → wind down with `[CONFLICT]` prefix).

### Removed
- `.codex/skills/` — Codex skill layer removed entirely. No known consumers, historical sync drift with Claude commands (5+ past bugs). Claude commands are the canonical workflow source; maintaining a parallel Codex layer added maintenance cost for no clear benefit. Codex references removed from install.sh, update.sh, uninstall.sh, README, CLAUDE.md, and orient.md.

### Fixed
- **OpenCode coder adapter lacks worktree isolation warning** (#97): the Claude coder agent declares `isolation: worktree`, but OpenCode has no equivalent, so parallel coders share one working tree. `sync-opencode-adapters.sh` now reads the `isolation` frontmatter field and, for worktree agents, appends a serialization caveat to the generated description (read by the orchestrator at spawn time) and a warning blockquote atop the body (read by the spawned agent). Mechanical from frontmatter — applies to any future isolated agent; test-locked.
- **Adapter sync `--check` misses stale adapters** (#98): both `scripts/sync-agent-adapters.sh` and `scripts/sync-opencode-adapters.sh` iterated only source files, so renaming or deleting a source (`.ai/workflows/*.md`, `.claude/agents/*.md`) left the old generated adapter in place and `--check` still passed. `--check` now fails on generated files with no matching source (across `.claude/commands/`, `.opencode/commands/`, `.opencode/agents/`); sync mode deletes them. Sync refuses stale removal when any source fails to parse (missing `name:` is not a deleted source). Negative tests delete fixture sources and assert orphaned adapters are flagged, removed, and preserved when the source is merely unparseable.
- Stale phase-number references after the composition refactor (#83): `autopilot.md` Wind-Down Protocol said "after Phase 9" (autopilot now ends at Phase 4); `CLAUDE.md` Session Management said "Phase 8-9 of autopilot" (same orphan). Both now reference Phase 4 / post-`/finish`.
- `finish.md` step 4 now sweeps *all* stranded remote branches (intersection of merged PRs and current remote heads), not just the current PR's branch — previous version mentioned remote-delete only as a "Note:", silenced errors with `2>/dev/null || true`, and never cleaned debt left by GitHub auto-delete misses or auto-merge timing, so dozens of merged-but-undeleted branches accumulated. Local-branch delete is now idempotent (guarded by `git show-ref`) so re-runs don't error. Push failures on the sweep are surfaced and the flow continues — never aborted, never swallowed.
- `loop.sh` lockfile used `basename "$(pwd)"`, causing collisions between identically-named directories under different parents. Now hashes the full absolute path via `shasum`/`sha1sum`.
- `update-hephaestus.md` used `ORIG_HEAD` to show post-update changelog, but `git submodule update --remote` does not set `ORIG_HEAD`. Now captures HEAD before/after the update (matching `update.sh` pattern).
- `orient.md` said "No build or test pipeline" despite `./tests/run.sh` existing with 113 assertions. Updated Development Commands section.
- CHANGELOG 1.0.0 entry referenced "11 commands, 3 Codex skills" — corrected to "12 commands" (Codex removed).
- `update-docs.md` referenced "Supersedes /document" — `/document` never existed. Removed.
- Remaining hardcoded retry limits in `refactor.md`, `critique.md`, `autopilot.md`, and `start-issue.md` now reference "per CLAUDE.md retry limits" instead of hardcoding numbers.
- `ship.md` and `refactor.md` ran tests but didn't declare `tester` in `<!-- requires: -->`
- 4 commands (`finish`, `update-docs`, `update-hephaestus`, `orient`) missing `<!-- requires: -->` declarations entirely — now use `<!-- requires: none -->`
- `CLAUDE.md.snippet` template and `orient.md` command listing omitted `/update-hephaestus`
- `install.sh` and `update.sh` used `[ -d ".hephaestus/.git" ]` to detect initialized submodules, but modern git submodules use a `.git` file (not directory). Changed to `[ -e ... ]` — fixes `update.sh` silently reverting submodule to committed pointer after `git submodule update --remote`.
- `install.sh` health check treated `<!-- requires: none -->` as requiring an agent called "none". Now skips the dependency check for commands that declare no requirements.
- `update.sh` uses `git submodule update --init --remote`, so a fresh clone of a project with an uninitialized `.hephaestus` submodule updates cleanly instead of aborting.

## 1.0.0 — 2026-03-24

### Changed
- Complete README rewrite — leads with value proposition and autonomous delivery pipeline instead of install-only content. Covers all 12 commands, 5 agents, headless operation, failure recovery, and quality gates.
- `install.sh` now detects if hephaestus is already registered as a submodule at a different path (e.g. `hephaestus/` vs `.hephaestus/`) and prints actionable guidance instead of creating a duplicate. Handles HTTPS/SSH URL comparison.
- README: added "Adopting in an existing project" section with audit workflow, migration pattern (project logic → CLAUDE.md), and uninstall guidance.

### Added
- `install.sh` post-install health check: validates symlinks, checks gh CLI, orient.md, and CLAUDE.md in a ✓/✗ summary.
- `/update-hephaestus` command — pulls latest submodule, re-runs install with `--clean`, shows changelog diff and version transition.
- `VERSION` file for version tracking.
- `update.sh` now shows version transition and changelog diff between old and new HEAD.
- `uninstall.sh` — cleanly removes hephaestus symlinks and submodule from a target project. Only removes symlinks pointing to `.hephaestus/`, preserves project-specific files. Idempotent.
- `install.sh --audit` flag: prints a conflict table showing what would change without modifying the filesystem.
- `install.sh --force` flag: replaces existing files with hephaestus symlinks.
- `install.sh` default skip messages now include actionable guidance (rm + re-run, diff commands).
- `install.sh` near-name collision detection: warns when target and hephaestus have confusingly similar filenames (e.g., `critic.md` vs `critique.md`).
- `install.sh` stale symlink detection: finds dangling symlinks pointing to `.hephaestus/` after upstream renames/removals. `--clean` flag auto-removes them.
- `templates/CLAUDE.md.snippet` — pasteable block with dev commands scaffold, hephaestus commands reference, agents table, and update instructions. install.sh suggests appending it when CLAUDE.md is missing required sections.
- `install.sh` post-install validation: checks target CLAUDE.md for development commands section, warns if missing.
- `install.sh` orient.md scaffolding: copies `templates/orient.md` template if the target project doesn't have one.
- `templates/orient.md` — project-specific orient template with placeholder sections matching what hephaestus commands expect.
- CLAUDE.md: "Core Principles" section — simplicity, self-improvement, and autonomy as the design axioms that guide every layer of the project.
- CLAUDE.md: "Transition to next phase" convention — invoke `/ship` (or the relevant command) directly when work is ready, don't ask vague questions.
- CLAUDE.md: "Improving the Workflow" section — workflow feedback that applies broadly should be persisted in the repo, not just local memory.
- `loop.sh` — headless autonomous loop that runs `/autopilot` in a fresh Claude session on a configurable interval; each run gets latest Claude capabilities and a clean context window
- `orient.md` command — cold-session orientation with repo context, structure, and next-action guidance
- Prompt injection protection in `researcher.md` — fetched content treated as untrusted; embedded instructions flagged before execution
- `.gitignore` — excludes `settings.local.json` (project-specific) and `*.lock` runtime files

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
