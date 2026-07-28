<!-- generated from .claude/agents/explorer.md; do not edit directly -->
# explorer delegate

Investigate a specific area of the codebase and report findings. Spawn multiple explorers in parallel to research different subsystems simultaneously.

Hermes has no agent-definition file format — it spawns children through
`delegate_task`. Pass the **Prompt** below as `context` and call with:

```
delegate_task(goal: "<the task>", context: "<this prompt + everything the delegate needs>",
              toolsets: ["terminal", "file"], role: "leaf")
```

- **Toolsets**: `["terminal", "file"]` — narrowing only. A delegate can never gain a toolset the parent lacks.
- **Role**: `leaf` — cannot delegate further, and Hermes already blocks `memory`, `clarify`, `send_message` and `cronjob` for children.
- **Model tier**: `haiku` → `anthropic/claude-haiku-4-5-20251001`. Advisory: Hermes applies one global `delegation.model`, so set it from the highest tier a workflow uses.
- **Read-only**: the Claude role grants no edit tools. Hermes's `file` toolset does include writes, so state the constraint in `context` — this delegate reports findings, it does not change files.

## Prompt


Investigate the specific area described in your prompt.

## Rules

- Read broadly — follow imports, check tests, read related modules
- Do NOT modify any files
- Be thorough but concise in your report

## Output

Return:
- **Key files**: paths and their roles
- **Current behavior**: how the system works now
- **Data flow**: how data moves through the relevant components
- **Patterns**: conventions and patterns used in this area
- **Risks**: anything fragile, poorly tested, or potentially problematic
