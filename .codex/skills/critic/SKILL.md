---
name: critic
description: Run adversarial critique workflows for code changes and non-code proposals. Use when the user asks for review, critique, risk assessment, architecture evaluation, pass/fail ship gate decisions, or plan validation.
---

# Critic

## Overview

Apply strict critique modes with calibrated severity and explicit verdicts.

## Mode Selection

1. Run `code critique` when there are uncommitted or recent code changes.
2. Run `general critique` for strategy, architecture, plans, or product proposals.
3. Run both when code and decision quality are both in scope.

## Code Critique Workflow

1. Collect change scope:
- `git diff --stat`
- `git diff`
- `git diff --cached`

2. Read full changed files and evaluate:
- correctness and edge cases
- security risks
- architecture fit
- performance risks
- error handling
- test adequacy

3. Return exactly:
- `Blocking`
- `Non-blocking`
- `Verdict: PASS | PASS WITH CHANGES | FAIL`

## General Critique Workflow

1. Restate the core claim in one sentence.
2. Steelman the strongest case for it.
3. Evaluate logic, assumptions, completeness, trade-offs, evidence, second-order effects, and timing.
4. Return:
- `Strongest point`
- `Weakest point`
- `Blind spots`
- `Alternative framing`
- `Verdict: SOUND | NEEDS REFINEMENT | RETHINK`

## Calibration Rules

- Mark as blocking only when ship risk is real.
- Do not inflate style nits into blockers.
- Do not invent issues if the work is solid.
- Prefer concrete evidence over abstract warnings.

## References

- Use `references/code-checklist.md` for code gate criteria.
- Use `references/general-checklist.md` for plan/strategy critique criteria.
