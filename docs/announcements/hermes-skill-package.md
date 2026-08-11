<!-- Announcement copy for the Hermes integration (#108, shipped in #141; filed by #142).
     Lift verbatim into the next release body as its own section — do not fold it into
     the file-drop adapter beat — or publish standalone. -->

# Hermes: hephaestus as a skill package

Hephaestus now runs on [Hermes Agent](https://github.com/NousResearch/hermes-agent) (Nous Research) — the first integration that is not a markdown-file drop.

- **A skill package, not a commands directory.** Claude Code, OpenCode, Codex, and Cursor all consume hephaestus as command files in a config dir. Hermes's extension surface is a skills system, so the unit of distribution changes: 13 skills under a `hephaestus` category plus 5 `delegate_task` briefs, discovered through `~/.hermes/skills` or `skills.external_dirs`. The generator pattern held anyway — `scripts/sync-hermes-adapters.sh` emits the whole package from the same canonical `.ai/workflows/` and `.claude/agents/` sources, drift-checked with `--check` like every other harness. A new distribution unit cost a new target format (SKILL.md frontmatter, category metadata, `chains` → `related_skills`), not a new architecture.

- **The five agent roles become real toolset narrowing.** On every other harness, least-privilege is prose. Hermes's `delegate_task` accepts per-call `toolsets` — narrowable, never widenable — so the roles compile to enforcement for the first time: researcher runs `["file", "web"]` with no shell, every child runs `role: "leaf"` with `memory`, `clarify`, and `send_message` blocked. Where enforcement flattens, the briefs say so instead of pretending: Hermes has no read-only file toolset, so reviewer, explorer, and tester carry the same `["terminal", "file"]` as coder, with read-only stated behaviorally. Model tiers render advisory for the same reason — Hermes applies one global `delegation.model`.

- **Two memories, one doctrine.** Hermes is the first harness with its own persistent memory, so the repo-as-memory doctrine had to be reconciled rather than assumed. The split: Hermes memory is profile-scoped, capped, and frozen into the system prompt at session start — use it for durable preferences. The repo stays canonical — issues, PRs, and git history are the memory that survives a machine change, so what a workflow decided lands there, never in `~/.hermes/memories/`.

- **Kanban is not the work queue.** Hermes ships a kanban toolset, but no GitHub issue sync exists upstream, so GitHub issues remain the single work queue. Kanban is optional scratch space for one session's fan-out — nothing the delivery loop depends on may live only on a local board.

- **Measured, not read.** Two widely-repeated claims about Hermes turned out to be false against a live v0.15.1 install: project-local skill discovery does not exist (so install prints the one-time `external_dirs` wiring, and `scripts/verify-hermes-load.sh` checks it — `--live` adds one billed probe proving a skill body actually loads), and per-call `toolsets` *does* work (the docs only say toolsets cannot be widened). The integration encodes what the CLI does, not what secondary sources say it does.

Install with `./install.sh`; the README's Hermes section covers wiring, the delegate briefs, and the doctrine notes in full.
