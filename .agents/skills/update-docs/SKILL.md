---
name: update-docs
description: "Update documentation to reflect recent work. Use for /update-docs requests."
---
<!-- requires: none -->
<!-- chains: none -->
<!-- generated from .ai/workflows/update-docs.md; do not edit directly -->

Update documentation to reflect recent work.

Steps:

1. **Review recent changes**: Run `git log --oneline -5` and `git diff HEAD~5..HEAD --name-only` to understand what was built.

2. **Update CLAUDE.md** (project root):
   - Add any new architecture decisions, patterns, or constraints discovered during the work
   - Remove patterns that are now obsolete
   - Keep CLAUDE.md under ~300 lines — trim verbose sections if needed

3. **Update CHANGELOG.md** (create it with a `# Changelog` title and `## Unreleased` section if the project has none):
   - Add entries under the existing `## Unreleased` heading in this format:
     ```
     ## Unreleased
     ### Added / Changed / Fixed
     - <concise description of what shipped>
     ```
   - Use `###` for category headings (Added, Changed, Fixed) — one per category, do not duplicate
   - Reference issue/PR numbers where applicable

4. **Update README.md** only if a public-facing feature or API changed (new endpoint, new CLI command, changed env var).

5. **Verify the README Composition tree** (hephaestus repo only): if `tests/check_composition.sh` exists at the repo root, run `bash "$(git rev-parse --show-toplevel)/tests/check_composition.sh"`; on drift, fix the README's `## Composition` section (or the affected command's `<!-- requires:/chains: -->` headers) per the verifier's output, then re-run. If the script doesn't exist (target projects), skip this step.

6. **Commit the doc changes**:
   ```
   git add CLAUDE.md CHANGELOG.md README.md
   git commit -m "docs: update CLAUDE.md and CHANGELOG for <feature>"
   ```

### Next steps
- Run `/orient` to see what to work on next
- Or run `/ship` if these doc changes need their own PR
