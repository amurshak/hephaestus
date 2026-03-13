Prepare, validate, and ship the current work. Issue number to close (optional): $ARGUMENTS

PRs must be **merge-ready** — all gates pass before creation, auto-merge after.

## Pipeline

### 1. Detect repo
Run `git remote get-url origin` to identify the target repo.

### 2. Pre-push critique gate
Launch reviewer subagent for code critique. This is the last quality check before the code goes out.
- **FAIL**: fix blocking issues, re-critique (max 3 iterations)
- **PASS WITH CHANGES**: fix blocking issues, proceed
- **PASS**: proceed

### 3. Run all quality gates in parallel
Launch as parallel subagents:
- **Tests**: run per project CLAUDE.md (test command, lint command, build command)
- **Git state**: `git status` (all staged) + `git log --oneline origin/master..HEAD` (commits ready)

If any gate fails: fix, re-run. If tests fail, go back to the critique gate with failure context.

### 4. Update docs
- Update CHANGELOG.md with the changes
- Commit doc changes

### 5. Push and create PR
```
gh pr create --repo <detected-repo> \
  --title "<concise title>" \
  --body "$(cat <<'EOF'
## Summary
- <bullet 1>
- <bullet 2>

## Quality gates
- [x] All tests passing
- [x] Lint clean
- [x] Code critique: PASS
- [x] No regressions

Closes #<issue number if provided>
EOF
)"
```

### 6. Auto-merge
```
gh pr merge --squash --auto
```

### 7. Return the PR URL.
