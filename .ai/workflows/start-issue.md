---
name: start-issue
requires: coder, explorer
chains: /test-issue
---
Start working on issue $ARGUMENTS. Run autonomously through the full plan-critique-implement cycle.

## Autonomy Rules

- **Resolve ambiguity yourself.** If requirements are unclear, make reasonable assumptions based on codebase context, existing patterns, and the issue description. Document assumptions in commit messages and the eventual PR body. Do NOT stop to ask the user.
- **Recover before escalating.** If an approach fails, try a different one. Only stop if you've exhausted alternatives AND the failure involves irreversible risk.

## Phase 1: Context

1. **Detect repo**: Run `git remote get-url origin` to identify the target repo.

2. **Load context in parallel**:
   - **Read the issue**: `gh issue view <#> --repo <detected-repo>`
   - **Explore codebase** (explorer subagent(s)): Search for relevant files, understand current implementation
   - **Recent history**: `git log --oneline -10`
   - For complex issues, spawn multiple explorer subagents per subsystem

3. **Resolve ambiguities**: If the issue is underspecified:
   - Infer intent from related code, tests, and commit history
   - Choose the simplest interpretation that satisfies the acceptance criteria
   - Log each assumption as a bullet point for later inclusion in the PR body

4. **Record scope**: Resolve the task change scope below before implementation; preserve its base through commits and pass it to `/test-issue` and the later `/ship` handoff.

5. **Create feature branch**: `git checkout -b issue-<number>-<short-description>` where `<short-description>` is a kebab-case summary derived from the issue title.

## Task change scope

Use a supplied Scope; otherwise base it on explicit `--base` (stacked work), the PR base, or confirmed `origin/HEAD`, in that order—never a guess or `HEAD~1`. Scope is the unique merge-base-to-HEAD diff plus separate staged, unstaged, and relevant untracked changes (`git diff --no-renames`, `git diff --cached HEAD`, `git diff`, `git ls-files --others --exclude-standard`; inventory with `--name-only -z`). Report/pass root, base/merge-base/HEAD OIDs, included paths, exclusions/reasons, and ambiguity. A missing/conflicting base, multiple merge-bases, failed inspection, or unresolved relevance makes scope incomplete and cannot PASS/auto-pass. Retain the base across commits; repeat affected gates if it changes. Include deletions and both rename paths; never mutate files to inspect them.

## Phase 2: Plan-Critique Loop

1. **Plan**: Break the issue into concrete steps with TodoWrite. Identify independent tasks for parallel coders.
2. **Self-critique** (general critique mode): Evaluate the plan for logic, assumptions, completeness, trade-offs.
3. **Refine**: Update the plan to address weaknesses.
4. **Re-critique**: Evaluate the refined plan.
5. **Repeat** until verdict reaches **SOUND** (max 3 iterations).

If critique iterations are exhausted:
- **NEEDS REFINEMENT**: Proceed with the best version. The remaining concerns become "Known Limitations" documented in the PR.
- **RETHINK**: Proceed with the most defensible subset of the plan — implement what IS sound, skip what isn't. File a follow-up issue for the unsound parts; if a skipped part carries a required criterion, the outcome is `[WIP]`, not `ready`.

## Phase 3: Implement

- Use parallel coder subagents (in worktrees) for independent changes
- Sequential implementation for dependent changes
- Commit each logical unit separately
- If a task is blocked: try one alternative approach. If still blocked and no acceptance criterion requires it, defer it to a follow-up issue and continue. If a required criterion depends on it, stop and wind down `[WIP]`: commit, push, open a draft PR listing the unmet criteria, file a follow-up issue. A TODO never satisfies a required criterion.

## Phase 4: Test → `/test-issue <#>`

Refresh and pass the recorded Scope to `/test-issue <#>` to execute project quality gates and verify acceptance criteria. The pre-ship code critique is `/ship`'s job — running it here would just duplicate the gate.

Continue to completion only when `/test-issue` reports every gate PASS and every required criterion met. A gate that could not run (BLOCKED) or an unverified criterion is not a pass: retry once if environmental, else wind down `[BLOCKED]` as below.

If tests fail or a required criterion is unmet:
- Analyze the root cause — don't blindly retry
- Go back to Phase 2 with failure context (max 2 full cycles)
- If still failing after 2 cycles: commit progress on the branch, create a draft PR (`--draft`) with `[FAILING]` prefix and failure analysis in the body, file a follow-up issue

Report the outcome — `ready`, or the draft PR's prefix — with the recorded Scope, files changed, `/test-issue` results, and assumptions. Only `ready` goes to `/ship`.

Key constraints:
- If the project has multiple sub-repos (e.g., backend + frontend), treat each as a separate git repo and commit in the right one
