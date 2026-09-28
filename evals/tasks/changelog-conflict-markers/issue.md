# collect-changelog.sh: a fragment left conflicted mid-merge publishes its conflict markers

Follow-up from the #205 review. `validate_fragments` checks filename shape and non-emptiness but not content, so a fragment carrying unresolved merge conflict markers passes `--check` and release mode publishes the markers verbatim into the new `## <version>` section — and (post-#205) `git rm -f` then deletes the conflicted file without protest. The file is tracked, so the content is recoverable from history, and the publish half predates #205; but a `grep -q '^<<<<<<< '` (and `^>>>>>>> `) in `validate_fragments` would fail the release before anything is written. Worth a case in `tests/test_changelog_fragments.sh`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
