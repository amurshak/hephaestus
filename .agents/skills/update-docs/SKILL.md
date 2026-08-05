---
name: update-docs
description: "Update documentation to reflect recent work. Use for /update-docs requests."
---
<!-- requires: none -->
<!-- chains: none -->
<!-- generated from .ai/workflows/update-docs.md; do not edit directly -->

> **Codex:** this skill is the `/update-docs` adapter. Use Codex role agents from `.codex/agents/` when the runtime exposes them; otherwise perform the work directly and keep the same structured output.

Update documentation to reflect recent work.

Steps:

1. **Review recent changes**: Run `git log --oneline -5` and `git diff HEAD~5..HEAD --name-only` to understand what was built.

2. **Update CLAUDE.md** (project root):
   - Add any new architecture decisions, patterns, or constraints discovered during the work
   - Remove patterns that are now obsolete
   - Keep CLAUDE.md under ~300 lines — trim verbose sections if needed

3. **Record changelog entries**:
   - If `changelog.d/` exists, write one fragment per change: `changelog.d/<issue-or-slug>.<added|changed|fixed|removed>.md`, containing the entry body without the leading `- `. Never edit CHANGELOG.md directly — it is assembled at release by `scripts/collect-changelog.sh <version>`.
   - Otherwise update **CHANGELOG.md** (create it with a `# Changelog` title and `## Unreleased` section if the project has none):
     ```
     ## Unreleased
     ### Added / Changed / Fixed
     - <concise description of what shipped>
     ```
     Use `###` for category headings — one per category, do not duplicate.
   - Reference issue/PR numbers where applicable

4. **Update README.md** only if a public-facing feature or API changed (new endpoint, new CLI command, changed env var).

5. **Run the repo's doc-drift verifiers** — scripts that opt in by carrying a `# hephaestus:doc-verifier` marker, so a project's unrelated `tests/check_*.sh` is never executed here:
   ```
   vs=$(grep -l '# hephaestus:doc-verifier' "$(git rev-parse --show-toplevel)"/tests/check_*.sh 2>/dev/null)
   for v in $vs; do bash "$v"; done
   ```
   Each reports what drifted and where; fix the docs it names, then re-run it. A repo with no such scripts runs nothing and moves on — that is not a failure.

6. **Commit the doc changes**:
   ```
   git add CLAUDE.md README.md changelog.d/ CHANGELOG.md 2>/dev/null
   git commit -m "docs: update CLAUDE.md and changelog for <feature>"
   ```

### Next steps
- Run `/orient` to see what to work on next
- Or run `/ship` if these doc changes need their own PR
