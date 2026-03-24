---
name: critic
description: Run adversarial critique workflows for code changes and non-code proposals. Use when the user asks for review, critique, risk assessment, architecture evaluation, pass/fail ship gate decisions, or plan validation.
---

# Critic

Apply strict adversarial critique with calibrated severity and explicit verdicts. Supports two modes: code critique (for diffs and recent changes) and general critique (for plans, architecture, and strategy).

## Workflow

Follows the same workflow as the corresponding Claude command:

- **critique** -- Run code critique, general critique, or both depending on scope

Code critique returns: Blocking issues, Non-blocking issues, Verdict (PASS / PASS WITH CHANGES / FAIL).
General critique returns: Strongest point, Weakest point, Blind spots, Alternative framing, Verdict (SOUND / NEEDS REFINEMENT / RETHINK).

See `CLAUDE.md` for retry limits and verdict handling rules.

## References

- `references/code-checklist.md` -- code gate evaluation criteria
- `references/general-checklist.md` -- plan/strategy critique criteria
