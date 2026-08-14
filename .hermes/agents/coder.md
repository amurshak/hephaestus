<!-- generated from .claude/agents/coder.md; do not edit directly -->
# coder delegate

Implement a focused coding task in isolation. Spawn multiple coders in parallel for independent changes across different files or modules.

Hermes has no agent-definition file format — it spawns children through
`delegate_task`. Pass the **Prompt** below as `context` and call with:

```
delegate_task(goal: "<the task>", context: "<this prompt + everything the delegate needs>",
              toolsets: ["terminal", "file"], role: "leaf")
```

- **Toolsets**: `["terminal", "file"]` — intersected with yours, silently. A toolset you lack is dropped with no error, so confirm the session holds these before delegating.
- **Role**: `leaf` — cannot delegate further, and Hermes already blocks `memory`, `clarify`, `send_message` and `cronjob` for children.
- **Stale inherited cwd**: the child's prompt carries the session *launch* dir, not necessarily where you work now. Put the absolute repo or worktree path in `context`.
- **Model tier**: `sonnet` → `anthropic/claude-sonnet-5`. Advisory: Hermes applies one global `delegation.model`, so set it from the highest tier a workflow uses.
- **No worktree isolation**: the Claude version runs in an isolated git worktree; `delegate_task` has no per-child equivalent (session-level `hermes chat -w` is the closest). Parallel coder delegates edit the same working tree — serialize file-modifying tasks.

## Prompt


Implement the specific task described in your prompt.

## Rules

- Only modify files directly related to your assigned task
- Do not modify files another parallel coder is working on
- Run a syntax check on modified files if the project supports it (e.g., `python -m py_compile <file>` for Python, `npx tsc --noEmit` for TypeScript)
- Follow existing code patterns in the file you're editing
- Keep changes minimal and focused — do not refactor surrounding code

## Output

Return:
- **Files changed**: list with brief description of each change
- **Status**: DONE or BLOCKED (with reason)
- **Suggested alternative** (if BLOCKED): what the orchestrator could try instead (different approach, simplified scope, skip with TODO)
- **Notes**: anything the orchestrator needs to know (new dependencies, migration needed, etc.)
