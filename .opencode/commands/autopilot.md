---
description: "Run the full autonomous pipeline for issue $ARGUMENTS. No human intervention required."
---
<!-- requires: explorer -->
<!-- chains: /start-issue, /ship, /finish -->
<!-- generated from .ai/workflows/autopilot.md; do not edit directly -->

> **OpenCode:** start from the project root that contains `.opencode/`. Invoke nested workflows as slash commands (/start-issue, /ship, /finish) so their full templates load — do not paraphrase. Spawn role agents with the Task tool or @mentions.

Run the full autonomous pipeline for issue $ARGUMENTS. No human intervention required.

If no issue number is provided, pick the highest-priority open issue from `gh issue list --state open --repo <detected-repo>` (prefer bugs over enhancements, older over newer). If no open issues exist, run **Self-Triage** (Phase 0) to generate work.

## Autonomy Principles

- **Decide, don't ask.** Make reasonable assumptions and document them in the PR body. Only stop for irreversible risk (data loss, security, force-push).
- **Recover, don't report.** When something fails, try an alternative approach before escalating. Escalation is a last resort, not a first response.
- **Stop clean, not mid-flight.** Never leave uncommitted changes, half-done branches, or orphaned state. Every stopping point must be a valid checkpoint.
- **Create breadcrumbs.** When winding down, file issues for unfinished work so the next session can pick up seamlessly.

---

## Pipeline

`/autopilot` is a thin orchestrator. It chains the dedicated commands (`/start-issue`, `/ship`, `/finish`) end-to-end and adds the pre-flight orient + self-triage that those individual commands don't do. Each chained command preserves its own retry semantics, gates, and wind-down behavior.

### Phase 0: Self-Triage (only when no issues exist)

If no open issues are found:
1. Scan codebase for improvement opportunities:
   - `grep -r "TODO\|FIXME\|HACK\|XXX"` for flagged technical debt
   - Review CLAUDE.md for documented next steps
   - Check CHANGELOG.md for recent patterns suggesting follow-up work
   - Run @explorer agent(s) to identify code quality issues, missing tests, or architectural gaps
2. Rank findings by impact (bugs > missing tests > tech debt > enhancements)
3. Create the highest-impact issue via `gh issue create`
4. Continue pipeline with the newly created issue

### Phase 1: Orient
- Run `git status` and `git log --oneline -5` for recent context
- Detect repo via `git remote get-url origin`
- If working tree is dirty, capture the pre-existing changes (including untracked files) with this block. Retain the returned `task_stash_record` path in task context and pass it to `/finish` and any wind-down; never discover a record from another task. Its unique marker identifies the stash even if another worktree pushes a newer one concurrently. Capture failure stops implementation and reports the preserved changes/stash; do not guess an OID. Without a record, cleanup leaves all stashes alone.

<!-- task-stash-capture -->
```bash
capture_task_stash() {
  task_stash_record=
  local dirty stash_tree stash_gitdir stash_branch stash_head stash_oid
  dirty=$(git status --porcelain --untracked-files=all) || return
  [ -n "$dirty" ] || return 0
  stash_tree=$(pwd -P) || return
  stash_gitdir=$(git rev-parse --absolute-git-dir) || return
  stash_branch=$(git symbolic-ref -q HEAD) || { echo 'preserve dirty detached checkout'; return 1; }
  stash_head=$(git rev-parse HEAD) || return
  task_stash_record=$(mktemp "${TMPDIR:-/tmp}/heph-task-stash.XXXXXX") || return
  git stash push --include-untracked -m "$task_stash_record" || return
  stash_oid=$(git stash list --format='%H %gs' | awk -v marker=": $task_stash_record" \
    'substr($0, length($0)-length(marker)+1) == marker {print $1}') || return
  case "$stash_oid" in ''|*[!0-9a-f]*) echo 'stash identity uncertain; preserve and stop'; return 1 ;; esac
  printf '%s\n' "$stash_tree" "$stash_gitdir" "$stash_branch" "$stash_head" \
    "$stash_oid" captured > "$task_stash_record" || return
  printf 'task stash record: %s\n' "$task_stash_record"
}
capture_task_stash
```

### Phase 2: Start the issue → `/start-issue <#>`

Run `/start-issue <#>`. It handles plan-critique loop, parallel @coder Task invocations, implementation, and the test gate, and ends ready for `/ship`.

If `/start-issue` winds down early (`[WIP]`, `[BLOCKED]`, `[FAILING]` prefix on the draft PR it created), respect that wind-down — the breadcrumbs are filed; do not try to push past them.

### Phase 3: Ship → `/ship <#>`

Run `/ship <#>`. It runs the pre-push critique gate, runs all quality gates in parallel, updates CHANGELOG, pushes the branch, creates the PR, and auto-merges.

If `/ship` cannot auto-merge (branch protection, required reviewers): the PR is left open, the work is preserved, and `/ship` notes that manual merge is needed. Still run Phase 4 — `/finish` branches on PR state and performs safe cleanup for unmerged PRs without closing the issue or deleting the branch.

### Phase 4: Finish → `/finish <#>`

Run `/finish <#>`. It closes the issue, deletes branches, files follow-ups, runs `/update-docs` when the PR diff requires it, captures a retrospective, and prints the session summary.

If there are additional open issues suitable for immediate work and the session is still productive, loop back to Phase 1 with the next issue. Otherwise, wind down.

---

## Session Wind-Down Protocol

When the pipeline reaches a natural stopping point (after Phase 4) or is forced to stop early:

1. **Commit all work** — never leave uncommitted changes. Use descriptive commit messages.
2. **Push the branch** — even for incomplete work, push so progress is preserved remotely.
3. **Create breadcrumbs** — for any unfinished work, file GitHub issues with:
   - What was attempted
   - What failed or remains
   - Suggested next approach
4. **Clean local state** — use `/finish`'s task identity checks and exact stash restoration block, including on early wind-down; never sweep branches or pop the top stash. Preserve resources when identity is missing, and report deferred cleanup or restoration conflicts. Do not continue to another issue with an unresolved restoration.
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
