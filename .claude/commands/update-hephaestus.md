<!-- requires: none -->
Update the hephaestus submodule to the latest version.

## Steps

1. Record the current version: `cat .hephaestus/VERSION 2>/dev/null || echo "unknown"`
2. Pull the latest: `git submodule update --remote .hephaestus`
3. Record the new version: `cat .hephaestus/VERSION 2>/dev/null || echo "unknown"`
4. Re-run install to pick up new commands/agents: `bash .hephaestus/install.sh --clean .`
5. Show what changed: `git -C .hephaestus log --oneline ORIG_HEAD..HEAD 2>/dev/null || echo "(first update — no previous ref)"`
6. Print version transition and suggest commit:
   ```
   Updated hephaestus: <old_version> → <new_version>
   Commit: git add .hephaestus .claude .codex && git commit -m "chore: update hephaestus to <new_version>"
   ```
