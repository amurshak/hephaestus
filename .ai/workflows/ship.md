---
name: ship
requires: tester
chains: /critique
---
Prepare, validate, and ship the current work. Issue number to close (optional): $ARGUMENTS

PRs must be **merge-ready** — all gates pass before creation, auto-merge after.

## Pipeline

### 1. Detect repo
Run `git remote get-url origin` to identify the target repo.

### 2. Pre-push critique gate → `/critique`

Run `/critique` (Code Critique mode auto-detects on uncommitted/staged changes; the reviewer subagent absorbs the verbose diff context). This is the last quality check before the code goes out.

- **FAIL**: Fix blocking issues, re-run `/critique` (per CLAUDE.md retry limits). If still FAIL:
  - Separate fixable issues from fundamental design problems
  - If fixable: attempt one more targeted fix cycle
  - If fundamental: create a draft PR (`--draft`) with `[BLOCKED]` prefix, list unresolved issues in the body, file a follow-up issue, and proceed to wind-down
- **PASS WITH CHANGES**: Fix blocking issues, proceed
- **PASS**: Proceed

### 3. Run all quality gates in parallel
Launch as parallel subagents:
- **Tests**: run per project CLAUDE.md (test command, lint command, build command). If CLAUDE.md has no "Development Commands" section, infer commands from project manifests (package.json, Makefile, pyproject.toml, go.mod, etc.), mark each gate `INFERRED` in the report, and note the gap in the PR body.
- **Git state**: `git status` (all staged) + detect base branch (`BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || git remote show origin 2>/dev/null | awk '/HEAD branch/{print $NF}' || echo master)`), then `git log --oneline origin/$BASE..HEAD` (commits ready)

If any gate fails:
- Analyze root cause — don't blindly re-run
- Fix and re-run (per CLAUDE.md retry limits)
- If a gate still fails after retries:
  - If it's lint: auto-fix what you can, note remaining issues in PR body
  - If it's tests: create PR as draft with `[FAILING: <test-name>]` prefix and failure analysis
  - If it's build: this is a hard stop — do not create a PR with a broken build. Commit progress, file follow-up issue.

### 4. Update docs
- Update CHANGELOG.md with the changes
- Commit doc changes

### 5. Push and create PR
```
git push -u origin HEAD
```

```
gh pr create --repo <detected-repo> \
  --title "<concise title>" \
  --body "$(cat <<'EOF'
## Summary
- <bullet 1>
- <bullet 2>

## Assumptions Made
- <any assumptions made during autonomous operation, or "None">

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

If auto-merge cannot be enabled (branch protection, required reviewers, etc.):
- Do NOT retry or force-push
- Note in the session summary that manual merge is required
- This is a valid stopping point — the work is preserved in the PR

### 7. Return the PR URL.

### Next steps
- Run `/test-issue` to verify CI status if needed
- Run `/finish <#>` after merge to close the issue, clean up branches, and file follow-ups
- Or run `/orient` to see what's next
