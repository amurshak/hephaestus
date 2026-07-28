---
name: update-hephaestus
description: "Update the hephaestus submodule to the latest version."
platforms: [linux, macos, windows]
metadata:
  hermes:
    category: hephaestus
    tags: [hephaestus, delivery, update-hephaestus]
    requires_toolsets: [terminal]
    related_skills: []
---
<!-- requires: none -->
<!-- chains: none -->
<!-- generated from .ai/workflows/update-hephaestus.md; do not edit directly -->

> **Hermes:** this skill is the `/update-hephaestus` adapter.

Update the hephaestus submodule to the latest version.

## Steps

0. If `.hephaestus/` does not exist, this isn't a submodule install — stop here. Plugin installs update via `/plugin marketplace update hephaestus`; manual copy installs update by re-copying the files from the hephaestus repo.
1. Record the current version: `cat .hephaestus/VERSION 2>/dev/null || echo "unknown"`
2. Capture the current submodule HEAD: `OLD_HEAD=$(git -C .hephaestus rev-parse HEAD 2>/dev/null)`
3. Pull the latest: `git submodule update --remote .hephaestus`
4. Capture the new submodule HEAD: `NEW_HEAD=$(git -C .hephaestus rev-parse HEAD 2>/dev/null)`
5. Record the new version: `cat .hephaestus/VERSION 2>/dev/null || echo "unknown"`
6. Re-run install to pick up new commands/agents: `bash .hephaestus/install.sh --clean .`
7. Show what changed: `git -C .hephaestus log --oneline $OLD_HEAD..$NEW_HEAD 2>/dev/null || echo "(first update — no previous ref)"`
8. Print version transition and suggest commit:
   ```
   Updated hephaestus: <old_version> → <new_version>
   Commit: git add .hephaestus .claude && git commit -m "chore: update hephaestus to <new_version>"
   ```
