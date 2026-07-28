Update hephaestus to the latest version.

<!-- requires: none -->
<!-- chains: none -->
<!-- generated from .ai/workflows/update-hephaestus.md; do not edit directly -->

> **Cursor:** run from the project root that contains `.cursor/`. Delegate to the subagents in `.cursor/agents/`; they share one working tree, so serialize file-modifying tasks.


## Steps

1. Detect the install:
   - `.heph-manifest` in the project root → **vendored** (its `# version:` line is the current version)
   - otherwise resolve the clone: `dirname $(dirname $(dirname $(readlink ~/.claude/commands/ship.md)))`, falling back to `$HEPHAESTUS_HOME` or `~/.hephaestus` → **user-level**
   - neither → **plugin** install: run `/plugin marketplace update hephaestus` and stop here.
2. Run the updater — it pulls, re-installs, and prints the version transition plus the commits in between:
   - user-level: `bash <clone>/update.sh`
   - vendored: `bash <clone>/update.sh --vendor .`
3. Report the version transition and what changed.
4. Vendored installs only — commit the refreshed copy:
   ```
   git add .heph-manifest .claude .opencode .agents .codex && git commit -m "chore: update hephaestus to <new_version>"
   ```
