# collect-changelog.sh silently ignores every argument after the first — '<version> --preview' performs a real release

Hit live while checking whether 2.2.0 was ready to cut. `scripts/collect-changelog.sh 2.2.0 --preview` **deleted all 26 changelog fragments and rewrote CHANGELOG.md with a dated `## 2.2.0` section.** No preview, no confirmation, no dry run.

## Cause

`scripts/collect-changelog.sh:162-168` inspects only `$1`:

```bash
case "${1:-}" in
  --check)   MODE="check" ;;
  --preview) MODE="preview" ;;
  "")        die "usage: ..." ;;
  -*)        die "unknown flag: $1" ;;
  *)         VERSION="$1" ;;
esac
```

`$2` onward is never read. So `2.2.0 --preview` matches `*)`, sets `VERSION=2.2.0`, leaves `MODE=release`, and `--preview` evaporates. The `-*)` unknown-flag guard has the same blind spot: `collect-changelog.sh 2.2.0 --dry-run`, `--check`, `-n`, or any typo'd flag also performs a real release.

## Why this argument order is the likely one

The usage header documents the two forms separately:

```
#   scripts/collect-changelog.sh <version>    Fold fragments into a dated section
#   scripts/collect-changelog.sh --preview    Print what would be folded, change nothing
```

But `--preview` alone cannot show the version heading it would write, so wanting to preview *a specific release* leads directly to `collect-changelog.sh 2.2.0 --preview`. That is the destructive path, and it is the natural thing to type. The flag documented as "change nothing" is the one that gets ignored.

Compounding it: the release path prints its output to stdout, so a caller who pipes through `grep`/`head` to skim the preview sees nothing alarming while the fragments are being deleted underneath.

## Blast radius

Recoverable here only because everything was committed — `git checkout -- CHANGELOG.md changelog.d/` restored all 26 fragments. In a tree with uncommitted fragments (the normal state mid-PR, since `/ship` writes a fragment as part of the branch), those fragments are **unrecoverable**. Target projects that adopted `--changelog-fragments` ship this same script, so the exposure is not limited to this repo.

## Fix

- Parse all arguments in a `while` loop rather than a single `case` on `$1`.
- Reject unknown flags and extra positionals wherever they appear, not just in first position.
- Let `--preview` take an optional version so `--preview 2.2.0` and `2.2.0 --preview` both render the real heading and both change nothing.
- Consider requiring the release path to be explicit (`--release <version>`), leaving a bare version as an error, so no typo lands on the destructive branch.

## Acceptance

- `<version> --preview`, `--preview <version>`, and `--preview` alone all change nothing on disk
- Any unrecognized flag in any position exits non-zero without touching `changelog.d/` or `CHANGELOG.md`
- Extra positionals are an error, not silently dropped
- `tests/test_changelog_fragments.sh` covers argument-order permutations and asserts the fragment count is unchanged after every non-release invocation
