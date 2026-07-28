---
name: research
description: "Conduct thorough research on: <argument> Use for /research requests."
---
<!-- requires: researcher, explorer -->
<!-- chains: none -->
<!-- generated from .ai/workflows/research.md; do not edit directly -->

> **Codex:** this skill is the `/research` adapter. Use Codex role agents from `.codex/agents/` when the runtime exposes them; otherwise perform the work directly and keep the same structured output.

> Codex does not substitute `$ARGUMENTS` — read it as the arguments given in the user's request.

Conduct thorough research on: $ARGUMENTS

**Always delegate to role agent(s)** — web search results are bulky and should not fill the main context window.

## Approach

Break the question into distinct facets and spawn parallel researcher role agents — one per facet — to investigate simultaneously. Each researcher searches independently in its own context and returns only structured findings. Synthesize their results in the main window.

For questions with both a technical and business dimension, run those as separate parallel tracks.

If codebase exploration is also needed, spawn explorer role agents in parallel with the researchers.

## Per-researcher instructions

Each researcher role agent should:
- Use multiple search queries to triangulate
- Cross-reference sources for accuracy
- Distinguish official docs from community advice from opinion
- Include source URLs for key claims

## Output

Synthesize all role agent findings into:

1. **Summary**: Direct answer to the research question (2-3 sentences)
2. **Key findings**: Organized by facet, with the most important points from each researcher
3. **Conflicting viewpoints**: Where sources disagree and which position is stronger
4. **Recommendations**: Actionable next steps based on the research
5. **Confidence**: HIGH / MEDIUM / LOW with brief justification (aggregate from researcher role agents)
6. **Sources**: URLs for the most authoritative references

Keep it concise and scannable. Bullets over prose.

### Next steps
- Run `/create-issue` to turn findings into actionable work
- Or run `/start-issue <#>` if an issue already exists for this topic
