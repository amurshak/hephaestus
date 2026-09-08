---
name: ship
description: "Prepare, validate, and ship the current work. Issue number to close (optional): <argument> Use for /ship requests."
---
<!-- requires: tester -->
<!-- chains: /critique -->
<!-- generated from .ai/workflows/ship.md; do not edit directly -->

> **Codex:** this skill is the `/ship` adapter. For chained workflows (/critique), invoke the matching generated skill (for example `heph:<workflow>`) when it is available; otherwise read and follow `.agents/skills/<workflow>/SKILL.md`. Use Codex role agents from `.codex/agents/` when the runtime exposes them; otherwise perform the work directly and keep the same structured output.

> Codex does not substitute `$ARGUMENTS` — read it as the arguments given in the user's request.

Prepare, validate, and ship the current work. Issue number to close (optional): $ARGUMENTS

PRs must be **merge-ready** — all gates pass before creation, auto-merge after.

## Pipeline

### 1. Detect repo
Run `git remote get-url origin` to identify the target repo.

### 2. Pre-push critique gate → `/critique`

Resolve the task change scope below and pass the recorded Scope to `/critique` explicitly in Code Critique mode, including on a clean branch with committed work. Use that same scope for every gate; scope incomplete cannot satisfy the ship gate.

- **FAIL**: Fix blocking issues, re-run `/critique` (max 3 iterations). If still FAIL:
  - Separate fixable issues from fundamental design problems
  - If fixable: attempt one more targeted fix cycle
  - If fundamental: create a draft PR (`--draft`) with `[BLOCKED]` prefix, list unresolved issues in the body, file a follow-up issue, and proceed to wind-down
- **PASS WITH CHANGES**: Fix blocking issues, proceed
- **PASS**: Proceed

### 3. Run all quality gates in parallel
Launch as parallel role agents:
- **Tests**: pass the recorded Scope to the tester; run per project CLAUDE.md (test command, lint command, build command). If CLAUDE.md has no "Development Commands" section, infer commands from project manifests (package.json, Makefile, pyproject.toml, go.mod, etc.), mark each gate `INFERRED` in the report, and note the gap in the PR body.
- **Git state**: refresh the recorded Scope and inspect `git status`; list all task commits with `git log --oneline "$scope_merge_base..$scope_head"`. Preserve unrelated user work. Resolve the PR destination branch matching the recorded base; do not silently switch to the default branch for stacked work.

If any gate fails:
- Analyze root cause — don't blindly re-run
- Fix and re-run (max 2 cycles)
- If a gate still fails after retries:
  - If it's lint: auto-fix what you can, note remaining issues in PR body
  - If it's tests: create PR as draft with `[FAILING: <test-name>]` prefix and failure analysis
  - If it's build: this is a hard stop — do not create a PR with a broken build. Commit progress, file follow-up issue.

### 4. Update docs
- Record the change. If `changelog.d/` exists, write one fragment per PR: `changelog.d/<issue-or-slug>.<added|changed|fixed|removed>.md`, containing the entry body without the leading `- `. Distinct filenames mean parallel branches never collide. Otherwise append under `## Unreleased` in CHANGELOG.md.
- Commit task-owned changes, including docs. Refresh Scope after these edits and commits; repeat affected critique and test gates before pushing.

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

## Quality gates
- [x] All tests passing
- [x] Lint clean
- [x] Code critique: PASS
- [x] No regressions

## Known Limitations
- <any documented caveats from critique loops, or "None">

Closes #<issue number if provided>
EOF
)"
```

For gates that passed with caveats, use `[x]` with a suffix: `- [x] Lint clean (with caveats — see Known Limitations)`.

**Evidence gate** — before running `gh pr create`, verify the composed body: no unchecked `- [ ]` items, no surviving `<angle-bracket>` placeholders, and every `[x]` quality-gate line corresponds to a gate actually run in this session (a claimed gate with no run behind it is a violation). On violation: run the missing gate or fix the body — never ship a checklist that claims what didn't happen.

### 6. Auto-merge
```
gh pr merge --squash --auto
```

Read back what happened — where the base branch requires no status check, `--auto` has nothing to wait on and the command succeeds by merging on the spot:

```
gh pr view <pr-number> --repo <detected-repo> --json state,autoMergeRequest
```

- `OPEN` with `autoMergeRequest` set — armed as intended; it merges when checks pass.
- `MERGED` — it merged immediately. Step 3's local gates were the only thing between this branch and the base, and CI gated nothing. Report that rather than "auto-merge enabled", and name the cause: the base branch requires no status checks.
- Command failed, or any other state (branch protection, required reviewers) — do NOT retry or force-push. Note that manual merge is required. This is a valid stopping point; the work is preserved in the PR.

### 7. Return the PR URL.

## Task change scope

Use a supplied Scope; otherwise base it on explicit `--base` (stacked work), the PR base, or confirmed `origin/HEAD`, in that order—never a guess or `HEAD~1`. Scope is the unique merge-base-to-HEAD diff plus separate staged, unstaged, and relevant untracked changes (`git diff --no-renames`, `git diff --cached HEAD`, `git diff`, `git ls-files --others --exclude-standard`; inventory with `--name-only -z`). Report/pass root, base/merge-base/HEAD OIDs, included paths, exclusions/reasons, and ambiguity. A missing/conflicting base, multiple merge-bases, failed inspection, or unresolved relevance makes scope incomplete and cannot PASS/auto-pass. Retain the base across commits; repeat affected gates if it changes. Include deletions and both rename paths; never mutate files to inspect them.

### Next steps
- Run `/test-issue` to verify CI status if needed
- Run `/finish <#>` after merge to close the issue, clean up branches, and file follow-ups
- Or run `/orient` to see what's next
