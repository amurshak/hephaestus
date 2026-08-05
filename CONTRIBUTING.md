# Contributing

## Ground rules

- **Edit canonical sources, never generated adapters.** Workflows live in `.ai/workflows/`, agents in `.claude/agents/`. Everything in `.claude/commands/`, `.opencode/`, `.agents/skills/`, `.codex/agents/`, `.hermes/`, and `.cursor/` is generated — regenerate with:
  ```bash
  ./scripts/sync-agent-adapters.sh
  ./scripts/sync-opencode-adapters.sh
  ./scripts/sync-codex-adapters.sh
  ./scripts/sync-hermes-adapters.sh
  ./scripts/sync-cursor-adapters.sh
  ```
- **Run the gates before submitting:**
  ```bash
  ./tests/run.sh                               # integration suite
  ./scripts/sync-agent-adapters.sh --check     # Claude adapter drift
  ./scripts/sync-opencode-adapters.sh --check  # OpenCode adapter drift
  ./scripts/sync-codex-adapters.sh --check     # Codex adapter drift
  ./scripts/sync-hermes-adapters.sh --check    # Hermes adapter drift
  ./scripts/sync-cursor-adapters.sh --check    # Cursor adapter drift
  bash tests/check_composition.sh              # README composition drift
  ./scripts/collect-changelog.sh --check       # changelog fragment names
  bash scripts/verify-opencode-load.sh         # optional live OpenCode load (skips if CLI absent)
  bash scripts/verify-codex-load.sh            # optional live Codex load (skips if CLI absent)
  ```
- **Bash 3.2 compatibility** — scripts must run on stock macOS bash: no associative arrays, no `mapfile`, portable `sed -i.bak`.
- **No bloat** — replacements must be at least as concise as the original. Retry limits are defined once in CLAUDE.md; commands reference them, never hardcode.
- Every PR adds a changelog fragment: `changelog.d/<issue-or-slug>.<added|changed|fixed|removed>.md`, entry body only, no leading `- `. Do not edit `CHANGELOG.md` — `scripts/collect-changelog.sh <version>` assembles it at release. Validate with `./scripts/collect-changelog.sh --check`.

## What we most want

Hephaestus is an open protocol for agentic software development: the canonical specs in `.ai/` are the protocol, and each harness gets a generated rendering of them. No harness is privileged — a new one is a first-class target, not a port.

**Adapter generators for new harnesses.** The pattern is `scripts/sync-opencode-adapters.sh` / `scripts/sync-codex-adapters.sh` / `scripts/sync-cursor-adapters.sh`: a generator that emits your harness's format from the canonical specs, with sync + `--check` modes, stale-adapter detection, and tests mirroring `tests/test_opencode_adapters.sh`.

Pair it with a `scripts/verify-<harness>-load.sh` (see the OpenCode, Codex, and Hermes ones): skip when the CLI is absent, `--require` to fail. The two checks prove different halves of conformance — `--check` proves the rendering still matches the spec, the verifier proves a real install actually discovers and dispatches it. A harness with only the first is unverified: #139 found the Codex spawn form rested on documented signatures no one had run.

## Conduct

Be direct, cite evidence, assume good faith. Critique the work, not the person — the reviewer agent's standard applies to humans too: findings need evidence or they're questions.
