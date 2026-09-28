<!-- requires: tester -->
<!-- chains: /critique -->
<!-- generated from .ai/workflows/ship.md; do not edit directly -->

Prepare, validate, and ship the current work. Issue number to close (optional): $ARGUMENTS

PRs must be **merge-ready** — every required gate passed on the delivered revision before creation, auto-merge after.

## Pipeline

### 1. Detect repo
Run `git remote get-url origin` to identify the target repo.

### 2. Update docs
- Record the change. If `changelog.d/` exists, write one fragment per PR: `changelog.d/<issue-or-slug>.<added|changed|fixed|removed>.md`, containing the entry body without the leading `- `. Distinct filenames mean parallel branches never collide. Otherwise append under `## Unreleased` in CHANGELOG.md.
- Make any other doc updates the project requires, then commit task-owned changes — docs come before the gates so every gate checks the delivered state.

### 3. Pre-push critique gate → `/critique`

Resolve the task change scope below and pass the recorded Scope to `/critique` explicitly in Code Critique mode, including on a clean branch with committed work. Use that same scope for every gate; scope incomplete cannot satisfy the ship gate.

- **FAIL**: Fix blocking issues, re-run `/critique` (max 3 iterations). If still FAIL:
  - Separate fixable issues from fundamental design problems
  - If fixable: attempt one more targeted fix cycle; if it still fails, take the fundamental path
  - If fundamental: create a draft PR (`--draft`) with `[BLOCKED]` prefix, list unresolved issues in the body, file a follow-up issue, and proceed to wind-down
- **PASS WITH CHANGES**: Fix blocking issues, proceed
- **PASS**: Proceed

### 4. Run quality gates
Run each gate command directly with tools — in parallel where independent — keeping its exit status and an evidence record (below); reuse a covering record instead of rerunning. Delegate to a tester, passing the recorded Scope, only for long or ambiguous output or an independent acceptance check.
- **Gates**: the test, lint, and build commands in the project CLAUDE.md. If CLAUDE.md has no "Development Commands" section, infer commands from project manifests (package.json, Makefile, pyproject.toml, go.mod, etc.), mark each gate `INFERRED` in the report, and note the gap in the PR body.
- **Git state**: refresh the recorded Scope and inspect `git status`; list all task commits with `git log --oneline "$scope_merge_base..$scope_head"`. Preserve unrelated user work. Resolve the PR destination branch matching the recorded base; do not silently switch to the default branch for stacked work.

If any gate fails:
- Analyze root cause — don't blindly re-run
- Fix and re-run (max 2 cycles)
- If a gate still fails after retries:
  - If it's lint: auto-fix what you can; remaining violations → draft PR `[FAILING: lint]`
  - If it's tests: create PR as draft with `[FAILING: <test-name>]` prefix and failure analysis
  - If a gate could not run (blocked): draft PR `[BLOCKED: <gate> unavailable]` naming the missing prerequisite
  - If it's build: draft PR `[FAILING: build]` with the build error

A draft PR ends `/ship`: commit task-owned changes, open it with every gate's evidence including the failed and blocked ones, file a follow-up issue, skip step 6 — a draft is never auto-merged — and report the prefix as the outcome.

Any commit after a gate or critique ran — a fix, a doc edit, a rebase — invalidates the records it touches: refresh Scope and repeat affected critique and test gates before pushing.

### 5. Push and create PR
```
git push -u origin HEAD
```

```
gh pr create --repo <detected-repo> \
  --base "<resolved-base-branch>" \
  --title "<concise title>" \
  --body "$(cat <<'EOF'
## Summary
- <bullet 1>
- <bullet 2>

## Assumptions Made
- <any assumptions made during autonomous operation, or "None">

## Scope
- <base ref/OID, merge-base OID, HEAD OID, included paths, exclusions/reasons, ambiguity>

## Evidence
| Check | Command or method | Outcome | Revision |
|---|---|---|---|
| <gate or critique> | <command, or reviewer and depth> | <outcome> | <HEAD OID and tree state, or the covering record it reuses> |

## Known Limitations
- <any documented caveats from critique loops, or "None">

Closes #<issue number if provided>
EOF
)"
```

**Evidence gate** — before running `gh pr create`, verify the composed body: no surviving `<angle-bracket>` placeholders; a row for the critique and every required gate; for a merge-ready PR, every required row passed at the delivered HEAD or through a covering record the row names. A row claiming a run that did not happen is a violation; an optional check not executed is listed as not run, never passed. On violation: run the missing gate or fix the body — never ship evidence that claims what didn't happen.

### 6. Auto-merge
```
gh pr merge --squash --auto
```

Read back what happened — where the base branch requires no status check, `--auto` has nothing to wait on and the command succeeds by merging on the spot:

```
gh pr view <pr-number> --repo <detected-repo> --json state,autoMergeRequest
```

- `OPEN` with `autoMergeRequest` set — armed as intended; it merges when checks pass.
- `MERGED` — it merged immediately. Step 4's local gates were the only thing between this branch and the base, and CI gated nothing. Report that rather than "auto-merge enabled", and name the cause: the base branch requires no status checks.
- Command failed, or any other state (branch protection, required reviewers) — do NOT retry or force-push. Note that manual merge is required. This is a valid stopping point; the work is preserved in the PR.

### 7. Return the PR URL.

## Task change scope

Use a supplied Scope; otherwise base it on explicit `--base` (stacked work), the PR base, or confirmed `origin/HEAD`, in that order—never a guess or `HEAD~1`. Scope is the unique merge-base-to-HEAD diff plus separate staged, unstaged, and relevant untracked changes (`git diff --no-renames`, `git diff --cached HEAD`, `git diff`, `git ls-files --others --exclude-standard`; inventory with `--name-only -z`). Report/pass root, base/merge-base/HEAD OIDs, included paths, exclusions/reasons, and ambiguity. A missing/conflicting base, multiple merge-bases, failed inspection, or unresolved relevance makes scope incomplete and cannot PASS/auto-pass. Retain the base across commits; repeat affected gates if it changes. Include deletions and both rename paths; never mutate files to inspect them.

## Evidence records

Each check yields one record: check, scope, command or method, outcome, and revision — HEAD OID and clean or dirty tree — plus any environment it depends on (tool versions, services, credentials). Outcome is passed, failed, blocked (could not run), not run, or not applicable; only passed satisfies a required gate. A record covers the delivered state while nothing it reads has changed: code, dependencies, configuration, environment, or — for doc checks — the docs. Reuse a covering record, including one handed over by another command; rerun the rest, and rerun when unsure what a check reads. Keep exit status and failure output; never report a check that did not run as passed.

### Next steps
- Run `/test-issue` to verify CI status if needed
- Run `/finish <#>` after merge to close the issue, clean up branches, and file follow-ups
- Or run `/orient` to see what's next
