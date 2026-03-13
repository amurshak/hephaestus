Update documentation to reflect recent work. Supersedes /document.

Steps:

1. **Review recent changes**: Run `git log --oneline -5` and `git diff HEAD~5..HEAD --name-only` to understand what was built.

2. **Update CLAUDE.md** (project root):
   - Add any new architecture decisions, patterns, or constraints discovered during the work
   - Remove patterns that are now obsolete
   - Keep CLAUDE.md under ~300 lines — trim verbose sections if needed

3. **Update CHANGELOG.md**:
   - Add a new entry at the top in this format:
     ```
     ### [Unreleased] - YYYY-MM-DD
     #### Added / Changed / Fixed
     - <concise description of what shipped>
     ```
   - Reference issue/PR numbers where applicable

4. **Update README.md** only if a public-facing feature or API changed (new endpoint, new CLI command, changed env var).

5. **Commit the doc changes**:
   ```
   git add CLAUDE.md CHANGELOG.md README.md
   git commit -m "docs: update CLAUDE.md and CHANGELOG for <feature>"
   ```
