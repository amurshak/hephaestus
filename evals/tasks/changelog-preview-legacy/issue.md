# collect-changelog.sh --preview omits the hand-written Unreleased body it calls a "real rehearsal"

Found while cutting 2.2.0 (#197).

Release mode merges hand-written `## Unreleased` content into the fragment sections by category:

```bash
render_fragments "$UNRELEASED_BODY" | awk ...
```

Preview mode does not — it calls `render_fragments` with no argument, so legacy entries are invisible:

```bash
if [ "$MODE" = "preview" ]; then
  ...
  [ -n "$VERSION" ] && printf '## %s — %s\n\n' "$VERSION" "$(date +%Y-%m-%d)"
  render_fragments
```

The comment directly above that line claims otherwise:

> Show the heading the release would write, so previewing a specific version is a real rehearsal rather than a bare list of entries.

It isn't a rehearsal while any hand-written Unreleased content exists — which is precisely the transition window the legacy-merge path was written for. In #197 the preview showed 41 entries and the release produced 46; the five-entry gap was the hand-written `### Added` block. Preview is the one safeguard before an irreversible, fragment-deleting operation, so under-reporting there is the worst place for it.

It also hides content bugs. #197's hand-written entry described the worktree config as `max: 3` serializing `install.sh` + `README.md` — stale on all three counts, and justified excluding `CHANGELOG.md` by a `/finish` rule that fragments had already made obsolete. A preview that rendered it would have shown that; instead it took reading `CHANGELOG.md` by hand to catch, and it would otherwise have shipped as fact in 2.2.0.

Fix: pass the extracted Unreleased body to `render_fragments` in preview mode too, and have the summary state both counts (fragments vs. merged legacy entries) so the gap is legible. Add a test that a preview with both fragments and hand-written Unreleased content renders every entry release mode would.
