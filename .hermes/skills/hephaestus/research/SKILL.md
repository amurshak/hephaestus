---
name: research
description: "Conduct thorough research on: <argument>"
platforms: [linux, macos, windows]
metadata:
  hermes:
    category: hephaestus
    tags: [hephaestus, delivery, research]
    requires_toolsets: [terminal]
    related_skills: []
---
<!-- requires: researcher, explorer -->
<!-- chains: none -->
<!-- generated from .ai/workflows/research.md; do not edit directly -->

> **Hermes:** this skill is the `/research` adapter.
> Where a step below names a role (researcher, explorer), you **must** call `delegate_task` for it rather than doing that step yourself — measured: orchestrators otherwise inline the whole workflow and never delegate. Each role's toolsets, cap and prompt are in `.hermes/agents/<role>.md`. A delegate inherits **none** of your conversation, and the cwd it does inherit is frozen at session **launch** — confidently stale if you work in a worktree — so give `context` absolute paths plus every constraint and prior finding it needs. Delegates get no per-child worktree, so parallel ones share one working tree: serialize file-modifying work.

> Hermes does not substitute `$ARGUMENTS` — read it as the arguments given in the user's request.

Conduct thorough research on: $ARGUMENTS

**Always delegate to delegate(s)** — web search results are bulky and should not fill the main context window.

## Approach

Break the question into distinct facets and spawn parallel researcher delegates — one per facet — to investigate simultaneously. Each researcher searches independently in its own context and returns only structured findings. Synthesize their results in the main window.

For questions with both a technical and business dimension, run those as separate parallel tracks.

If codebase exploration is also needed, spawn explorer delegates in parallel with the researchers.

## Per-researcher instructions

Each researcher delegate should:
- Use multiple search queries to triangulate
- Cross-reference sources for accuracy
- Distinguish official docs from community advice from opinion
- Include source URLs for key claims

## Output

Synthesize all delegate findings into:

1. **Summary**: Direct answer to the research question (2-3 sentences)
2. **Key findings**: Organized by facet, with the most important points from each researcher
3. **Conflicting viewpoints**: Where sources disagree and which position is stronger
4. **Recommendations**: Actionable next steps based on the research
5. **Confidence**: HIGH / MEDIUM / LOW with brief justification (aggregate from researcher delegates)
6. **Sources**: URLs for the most authoritative references

Keep it concise and scannable. Bullets over prose.

### Next steps
- Run `/create-issue` to turn findings into actionable work
- Or run `/start-issue <#>` if an issue already exists for this topic
