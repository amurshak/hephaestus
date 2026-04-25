# Orient — [Project Name]

## Repo
`owner/repo` — one-line description of the project.

## Structure
- `src/` — application source
- `tests/` — test suite
<!-- List the key directories a new session needs to know about -->

## Development commands
```bash
# Test
npm test           # or: pytest, go test ./..., etc.

# Lint
npm run lint       # or: ruff check ., golangci-lint run, etc.

# Build
npm run build      # or: go build ./..., cargo build, etc.
```
<!-- These MUST match the "Development Commands" section in your CLAUDE.md -->

## Sync state
First, sync with remote and prune stale tracking refs (branches GitHub deleted on merge but git still has):
```
git fetch --prune origin
```

## Find work
```
gh issue list --state open --repo owner/repo
```

## Next action
Run `/autopilot` — it will pick the highest-priority open issue or self-triage if the queue is empty.

## Key constraints
<!-- Project-specific constraints, e.g.: -->
<!-- - Never modify the public API without a deprecation path -->
<!-- - Database migrations require review -->
