# Issue Template

## Title

Use a short imperative title, for example: `Fix token refresh race condition`.

## Body

```markdown
## Problem
<2-3 sentences on what is broken or missing and impact>

## Acceptance Criteria
- [ ] <criterion 1>
- [ ] <criterion 2>
- [ ] <criterion 3>

## Technical Notes
- Relevant files: `<path1>`, `<path2>`
- Context: <implementation details and boundaries>

## Labels
- <bug|enhancement>
- <backend|frontend>
```

## Creation Command

1. Check available labels first: `gh label list --repo <owner/repo>`
2. Create the issue with label flags:

```bash
gh issue create --repo <owner/repo> --title "<title>" --body "<body>" --label "<label1>" --label "<label2>"
```

Only pass `--label` flags for labels that exist in the repo (from step 1). If no matching labels exist, omit the flags.
