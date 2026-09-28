# collect-changelog.sh: a locally-modified fragment survives the fold, and release mode still reports success

Found while cutting 2.2.0 (#197).

Release mode consumes fragments with `git rm --quiet` per file:

```bash
if git -C "$REPO_ROOT" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
  git -C "$REPO_ROOT" rm --quiet "$f"
```

`git rm` refuses a file with unstaged modifications (`error: the following file has local modifications ... use --cached to keep the file, or -f to force removal`). The script runs under `set -uo pipefail` with no `-e` and never checks the status, so:

1. the fragment's content **is** folded into the new `## <version>` section,
2. the fragment file **survives** on disk,
3. the script still prints `✓ released <version> — folded N fragment(s)`.

The next release then folds the same entry a second time. It is not silent — `git rm` writes to stderr — but the success line is what a release run is read for, and the leftover is a valid fragment name that `--check` happily passes.

Hit it for real in #197: `worktree-cap.changed.md` had been edited on the release branch to reconcile it with a stale hand-written `## Unreleased` entry. The edit was unstaged when `collect-changelog.sh 2.2.0` ran, so it published and stayed. Caught by diffing the leftovers against the assembled section; without that check it would have appeared again in 2.3.0.

Suggested fix: check the `git rm` status and either fail the release or fall back to `git rm -f` (the content is already published, so the file is provably consumed). Either way the closing summary must not claim a clean fold when fragments remain. Worth asserting in `tests/test_changelog_fragments.sh`: modify a tracked fragment, release, and require `changelog.d/` to hold only `README.md`.
