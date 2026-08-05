# AGENTS.md

<!-- Index of agents available in this project. Customize the Local section;
     the Shared section lists what hephaestus provides. -->

## Development Commands
See CLAUDE.md "Development Commands" — agents read test/lint/build commands from there.

## Local Agents
<!-- Project-specific agents in .claude/agents/ that this project owns. -->
| Agent | Role |
|---|---|
| _(none yet)_ | |

## Shared Agents (hephaestus)
| Agent | Role | Access |
|---|---|---|
| **coder** | Implements a focused task; parallel coders for independent changes | Edit + shell, isolated worktree |
| **reviewer** | Adversarial code review — evidence-cited findings, 0–100 score | Read + shell (instructed read-only) |
| **tester** | Runs quality gates, returns structured pass/fail | Read + shell (instructed read-only) |
| **explorer** | Investigates the codebase, reports findings | Read + shell (instructed read-only) |
| **researcher** | Web research with source cross-referencing | Web + read, no shell |

## Conventions
- Agents return structured output (status, files, verdicts) — never raw logs.
- Only the coder modifies files; review and implementation stay separated.
- Retry limits and wind-down rules are carried by the commands themselves. Add a `## Workflow Rules` section to CLAUDE.md only to override them.
