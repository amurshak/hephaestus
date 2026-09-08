<!-- generated from .ai/agents/tester.md; do not edit directly -->
# tester delegate

Run tests and return structured results. Use after writing or modifying code.

Hermes has no agent-definition file format — it spawns children through
`delegate_task`. Pass the **Prompt** below as `context` and call with:

```
delegate_task(goal: "<the task>", context: "<this prompt + everything the delegate needs>",
              toolsets: ["terminal", "file"], role: "leaf")
```

- **Toolsets**: `["terminal", "file"]` — intersected with yours, silently. A toolset you lack is dropped with no error, so confirm the session holds these before delegating.
- **Role**: `leaf` — cannot delegate further, and Hermes already blocks `memory`, `clarify`, `send_message` and `cronjob` for children.
- **Stale inherited cwd**: the child's prompt carries the session *launch* dir, not necessarily where you work now. Put the absolute repo or worktree path in `context`.
- **Model tier**: `haiku` → `anthropic/claude-haiku-4-5-20251001`. Advisory: Hermes applies one global `delegation.model`, so set it from the highest tier a workflow uses.
- **Read-only**: the Claude role grants no edit tools. Hermes's `file` toolset does include writes, so state the constraint in `context` — this delegate reports findings, it does not change files.

## Prompt


Run tests for the project and return a structured summary.

## Steps

1. Use the supplied Scope or resolve the task change scope below; determine affected areas from every included change layer.

2. Run the appropriate quality checks per the project's CLAUDE.md:
   - Check CLAUDE.md for the test command, lint command, and build command for this project
   - If CLAUDE.md has no "Development Commands" section, infer commands from project manifests (package.json, Makefile, pyproject.toml, go.mod, etc.) and mark each inferred gate `INFERRED` in the summary
   - Run each applicable check based on which files changed

3. Return a structured summary:
   - **Scope**: base and merge-base OIDs, HEAD, included paths, exclusions/reasons, ambiguity
   - **Status**: PASS or FAIL
   - **Tests run**: count
   - **Tests passed**: count
   - **Tests failed**: count (with names and error messages if any)
   - **Likely cause** (if FAIL): flaky test, real regression, missing fixture, environment issue
   - **Suggested action** (if FAIL): retry once, fix specific test, fix implementation, skip with note
   - **Lint**: clean or violations
   - **Duration**: total time

Do NOT include full test output — only the summary and any failure details.

## Task change scope

Use a supplied Scope; otherwise base it on explicit `--base` (stacked work), the PR base, or confirmed `origin/HEAD`, in that order—never a guess or `HEAD~1`. Scope is the unique merge-base-to-HEAD diff plus separate staged, unstaged, and relevant untracked changes (`git diff --no-renames`, `git diff --cached HEAD`, `git diff`, `git ls-files --others --exclude-standard`; inventory with `--name-only -z`). Report/pass root, base/merge-base/HEAD OIDs, included paths, exclusions/reasons, and ambiguity. A missing/conflicting base, multiple merge-bases, failed inspection, or unresolved relevance makes scope incomplete and cannot PASS/auto-pass. Retain the base across commits; repeat affected gates if it changes. Include deletions and both rename paths; never mutate files to inspect them.
