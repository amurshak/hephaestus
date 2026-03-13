Run the full autonomous pipeline for issue $ARGUMENTS. No human intervention required.

If no issue number is provided, pick the highest-priority open issue from `gh issue list --state open --repo <detected-repo>` (prefer bugs over enhancements, older over newer). If no open issues exist, run **Self-Triage** (Phase 0) to generate work.

## Autonomy Principles

- **Decide, don't ask.** Make reasonable assumptions and document them in the PR body. Only stop for irreversible risk (data loss, security, force-push).
- **Recover, don't report.** When something fails, try an alternative approach before escalating. Escalation is a last resort, not a first response.
- **Stop clean, not mid-flight.** Never leave uncommitted changes, half-done branches, or orphaned state. Every stopping point must be a valid checkpoint.
- **Create breadcrumbs.** When winding down, file issues for unfinished work so the next session can pick up seamlessly.

---

## Pipeline

### Phase 0: Self-Triage (only when no issues exist)

If no open issues are found:
1. Scan codebase for improvement opportunities:
   - `grep -r "TODO\|FIXME\|HACK\|XXX"` for flagged technical debt
   - Review CLAUDE.md for documented next steps
   - Check CHANGELOG.md for recent patterns suggesting follow-up work
   - Run explorer subagent(s) to identify code quality issues, missing tests, or architectural gaps
2. Rank findings by impact (bugs > missing tests > tech debt > enhancements)
3. Create the highest-impact issue via `gh issue create`
4. Continue pipeline with the newly created issue

### Phase 1: Orient
- Run `git status` and `git log --oneline -5` for recent context
- Detect repo via `git remote get-url origin`
- If working tree is dirty:
  - Stash changes: `git stash push -m "autopilot-pre-<issue-number>"`
  - Continue (do NOT stop to ask)

### Phase 2: Start
- Read the issue (`gh issue view`)
- Explore relevant codebase (explorer subagent(s) in parallel)
- Create feature branch: `git checkout -b issue-<number>-<short-description>`

### Phase 3: Plan-Critique Loop
1. **Plan**: Break the issue into concrete implementation steps with TodoWrite. Identify independent tasks for parallel coders.
2. **Critique the plan** (general critique mode): Evaluate logic, assumptions, completeness, trade-offs, risks.
3. **Refine**: Update the plan to address criticisms.
4. **Re-critique**: Evaluate the refined plan.
5. **Repeat** until verdict reaches **SOUND** (max 3 iterations).

If after 3 iterations the verdict is still not SOUND:
- **NEEDS REFINEMENT**: Proceed with the best version. Document the unresolved concerns as "Known Limitations" in the PR body.
- **RETHINK**: The plan has fundamental issues. Commit any useful exploration as a draft PR with `[WIP]` prefix, file a follow-up issue describing the conceptual blockers, then wind down cleanly (see Session Wind-Down).

### Phase 4: Implement
- Execute the plan using parallel coder subagents for independent tasks
- Sequential implementation for dependent changes
- Commit each logical unit of work separately
- If a coder subagent is blocked: attempt a different approach. If still blocked after one retry, skip that task, log it as a TODO comment in the code, and continue with remaining tasks.

### Phase 5: Pre-ship Critique Gate
- Launch reviewer subagent(s) for code critique
- **FAIL**: Fix blocking issues, re-critique (max 3 iterations). If still FAIL after 3:
  - Determine if blockers are fixable with a different approach — try once
  - If still blocked: commit progress, create a draft PR with `[BLOCKED]` prefix listing the unresolved issues, file a follow-up issue, wind down
- **PASS WITH CHANGES**: Fix blocking issues, proceed
- **PASS**: Proceed

### Phase 6: Test
- Launch tester subagent(s) for all quality gates per project CLAUDE.md
- Verify acceptance criteria from the issue

If tests fail:
- Analyze failure root cause before retrying — don't repeat the same approach
- **Go back to Phase 3** with failure context incorporated into the plan (max 2 plan-implement-test cycles)
- If still failing after 2 cycles:
  - Commit the current state on a branch
  - Create a draft PR with `[FAILING]` prefix and detailed failure analysis in the body
  - File a follow-up issue with the failure context and what was tried
  - Wind down cleanly

### Phase 7: Ship
- Update CHANGELOG.md
- Commit docs
- Push and create merge-ready PR (`gh pr create`)
- Merge the PR (`gh pr merge --squash --auto`)
- If auto-merge fails (e.g., branch protection, required reviews): leave the PR open and note in summary that manual merge is needed. Do NOT retry or force-push.

### Phase 8: Finish
- Close the issue with reference to the PR
- Delete merged branches (local only)
- Print one-line summary: issue number, PR number, what shipped

### Phase 9: Update Docs
- Update CLAUDE.md if architecture changed
- Commit doc updates
- If there are additional open issues suitable for immediate work and the session is still productive, loop back to Phase 1 with the next issue. Otherwise, wind down.

---

## Session Wind-Down Protocol

When the pipeline reaches a natural stopping point (after Phase 9) or is forced to stop early:

1. **Commit all work** — never leave uncommitted changes. Use descriptive commit messages.
2. **Push the branch** — even for incomplete work, push so progress is preserved remotely.
3. **Create breadcrumbs** — for any unfinished work, file GitHub issues with:
   - What was attempted
   - What failed or remains
   - Suggested next approach
4. **Clean local state** — delete merged branches, pop any stashes created during the session.
5. **Print session summary**:
   - Issues completed (with PR links)
   - Issues created (with links)
   - Outstanding work (with issue links)

---

## Guardrails

- **Hard stops** (truly irreversible risk): security vulnerabilities being shipped, data loss paths, force-push to protected branches
- **Soft stops** (proceed with documentation): ambiguous requirements (make assumption, document it), public API changes (implement with deprecation path, flag in PR), exhausted retries (commit progress, file follow-up issue)
- **Never**: force-push, rewrite published history, create PR with known security issues, delete remote branches that aren't yours
- Everything else runs autonomously.
