# changelog.d/

One changelog entry per PR, as its own file. Parallel branches never edit a shared
anchor, so the changelog stops being a merge-conflict hotspot.

**Filename**: `<id>.<category>.md`

- `<id>` — the issue number (`129`) or a short slug for issue-less work (`worktrees-config`)
- `<category>` — one of `added`, `changed`, `fixed`, `removed`

**Content**: the entry body, without the leading `- `. Same prose style as the
existing CHANGELOG — bold title, issue reference, then what changed and why.

```
$ cat changelog.d/129.fixed.md
**Spawn CLI in `/worktrees` adapters** (#129): the Step 6 spawn block hardcoded
`claude`, leaking into the OpenCode and Codex adapters verbatim.
```

At release, `scripts/collect-changelog.sh <version>` folds every fragment into a
dated `## <version>` section in CHANGELOG.md and deletes them. Use
`--preview` to see the assembled section without writing, `--check` to validate
filenames in a quality gate.
