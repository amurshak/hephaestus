---
name: worktrees
description: "Orchestrate parallel multi-session development: survey existing worktrees, reap finished ones, plan a wave of non-conflicting issues, create sibling worktrees, and spawn a seeded… Use for /worktrees requests."
---
<!-- requires: none -->
<!-- chains: none -->
<!-- generated from .ai/workflows/worktrees.md; do not edit directly -->

> **Codex:** this skill is the `/worktrees` adapter. Use Codex role agents from `.codex/agents/` when the runtime exposes them; otherwise perform the work directly and keep the same structured output.

> Codex does not substitute `$ARGUMENTS` — read it as the arguments given in the user's request.

Orchestrate parallel multi-session development: survey existing worktrees, reap finished ones, plan a wave of non-conflicting issues, create sibling worktrees, and spawn a seeded Claude Code session per issue. Run autonomously.

Modes from `$ARGUMENTS`: no args = full cycle (survey → reap → plan → create → spawn). `status` = survey report only. `cleanup` = survey + reap only.

## Step 1 — Config

Detect the repo (`git remote get-url origin`) and read the optional `## Worktrees` section of the project's CLAUDE.md:
- `max:` — concurrent-session cap (default **3**)
- `serialize_paths:` — files where issues collide **semantically** (a shared schema, an installer, a generated bundle); issues likely touching the same listed path are never scheduled in the same wave. Do not list a file every PR touches by construction (a changelog, a version manifest) — serializing it blocks every pair and pins concurrency at 1. Fix those structurally instead, with one file per PR.
- `setup:` — per-worktree setup command (deps, env), run after creation

## Step 2 — Survey

`git worktree list --porcelain`, then for each worktree on an `issue-<N>-*` branch, one batched call: branch, dirty state, ahead/behind, linked PR (`gh pr list --head <branch> --state all`), linked issue state. Classify:
- **Finished** — PR merged AND working tree clean AND no unpushed commits
- **Stale** — no open linked issue or PR, no commits ahead
- **Active** — everything else (assume a session may be attached)

## Step 3 — Reap

Remove **Finished** and **Stale** worktrees: `git worktree remove <path>` + `git branch -D <branch>` (force is safe — the PR is merged or the branch has nothing ahead) + `git worktree prune`. Never touch a worktree that is dirty or has unpushed commits — list those under "Attention needed" with what's blocking. Freed slots: `available = max − active`.

## Step 4 — Wave plan

Candidates: open issues with no existing branch, worktree, or PR (`gh issue list --state open`), ranked by priority (bugs > features, older > newer). Pairwise conflict tests:
1. Explicit dependency — "blocked by #N" / "depends on #N" in the issue body, or sub-issues of the same parent
2. `serialize_paths` collision — both issues plausibly touch the same listed hotspot
3. Likely file overlap — issue text names the same module/area, or similar past PRs (`gh pr list --search`) show heavy overlap

**Wave 1** = the largest mutually non-conflicting set that fits `available`. When in doubt, prefer parallel and note the risk in the report; each deferral must name its blocking issue or path. Remaining candidates queue for the next `/worktrees` run.

## Step 5 — Create

For each Wave-1 issue, as a sibling of the primary checkout:
```
git worktree add ../<repo>-issue-<N> -b issue-<N>-<slug> origin/<base-branch>
```
Then propagate config the branch doesn't carry: copy `.claude/settings.local.json` and `.mcp.json` if present; symlink gitignored env files (detect via `git status --ignored --porcelain`, match `.env*`) back to the primary so credentials stay single-sourced. Run the configured `setup:` command if any. Never start a second service stack (ports/DBs collide) — sessions share the primary's services unless the project's CLAUDE.md says otherwise.

## Step 6 — Spawn

macOS: one batch of `osascript` Terminal launches, each:
```
tell application "Terminal"
  activate
  do script "cd <worktree> && claude --permission-mode default \"/start-issue <N>\""
  set custom title of front window to "issue-<N>"
end tell
```
`activate` is required (windows can silently fail to appear without it); the custom title survives Claude Code's title rewrites; `--permission-mode default` prevents spawned sessions inheriting plan mode and stalling. Non-macOS or on failure: print the `cd <worktree> && claude "/start-issue <N>"` commands for manual launch and continue.

## Step 7 — Report

Reaped (worktree → why), launched (issue → path), deferred (issue → named blocker), attention needed (dirty/unpushed worktrees), slots in use vs `max`.

## Safety

- Never remove dirty or unpushed worktrees; never force-delete a branch without a merged PR or zero commits ahead
- The cap is a hard limit — cap-overflow issues queue, they don't stretch the cap
- Spawned sessions run the normal `/start-issue` pipeline with all its gates; this command only orchestrates
