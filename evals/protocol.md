# Baseline evaluation protocol

Fixed before any result is read (#242). It measures whether hephaestus changes delivery outcomes against the native harness on the same tasks. Every redesign issue under #219 reports its change against this baseline, and the full comparison in #238 extends it.

## Question

On identical tasks, model, and harness, does the full hephaestus workflow produce accepted changes more often, or at lower cost to acceptance, than the native harness with the project's own instructions?

## Arms

| Arm | Setup | Prompt |
|---|---|---|
| **native** | No hephaestus. The project's CLAUDE.md is present, as in any repo. | Resolve issue #N (via `gh issue view N`), autonomously, verified, committed on a new branch; no push or PR. |
| **full** | hephaestus user-level install from a pinned revision (`HEPH_EVAL_PIN`, default HEAD — which carries the #220–#224 correctness fixes). | `/start-issue N` — the shipped workflow, which chains `/test-issue` and ends ready for `/ship`. |

Same model (`HEPH_EVAL_MODEL`), harness version, timeout, sandbox, and tools in both. Endpoint for both: the implementation on a local branch — merging and PR creation are out of scope, so the arms stop at the same place.

## Acceptance standard

Judged by the runner after the agent stops, never by the agent's own report:

1. **accepted** — the task's `accept.sh` passes against the final working tree. Checks assert behavior (exit codes, file state), never message wording, so any correct fix passes.
2. **regression** — the base revision's own tests for the touched area pass, restored from the base so an agent cannot edit them into passing. `na` where those tests pin behavior the reference fix legitimately changes; the task file says why.

**Primary metric:** paired acceptance rate — runs that are accepted with regression passing (or `na`), per arm. **Secondary:** cost per run and per accepted run, wall time, turns, timeouts, and committed-clean rate (work left uncommitted counts against the endpoint, not acceptance).

`evals/run.sh validate` proves each check is discriminating before it is used: it must reject the unfixed base and accept the upstream reference fix. A task that fails validation is not run.

## Controls

- **Fresh sandbox per run**: the repo exported at the task's base with no history beyond it, so the fix commit is unreachable; a local bare origin; an isolated `HOME`.
- **No harness adapters in the sandbox**: the repo's own generated `.claude/commands`, `.claude/agents`, and other harness directories are removed, so native is native and full sees only the pinned install.
- **Pinned install excludes answers**: the full arm's pinned copy carries only what a user-level install needs — no scripts under test, changelog, tests, or tasks.
- **No network through `gh`**: a shim serves the task's issue and refuses everything else.
- **Order**: every (task, arm, repeat) is shuffled by a recorded seed.
- **Denominator**: failed, timed-out, and budget-stopped runs are recorded as runs; nothing is dropped after the fact.

## Decision rule

The seed set is a pilot: 4 tasks × 2 arms × 3 repeats = 24 runs. It estimates variance and exposes large effects; it cannot establish small differences or rare failures. Report per-task results and pooled rates with the discordant pairs (tasks where one arm is accepted and the other is not), not a single headline.

For a later candidate (#225 onward) compared against this baseline: a candidate that loses more than **10 percentage points** of paired acceptance on the same tasks does not replace the full workflow, whatever its cost. Within that margin, lower cost per accepted run is the deciding measure. Native is an acceptable winner.

## Re-run triggers

Re-run the baseline, and the component comparisons that depend on it, when any of these change: the model, the harness major or minor version, or a shipped workflow or agent definition. Results record model, harness version, pin, seed, and base commit so two runs are comparable only when those match or the difference is the thing being measured.

## Limitations

- **One stratum.** All seed tasks are well-specified shell bugfixes from this repository, with issue texts that often name the fix. They under-represent features, ambiguity, unfamiliar code, and multi-file design, which is where planning and review would plausibly matter most. #238 widens the strata; add tasks in the format below.
- **Self-hosting.** The task repo is hephaestus; its CLAUDE.md describes the workflow to both arms. Tasks from public history may be in training data.
- **Residual leakage.** Agents run with full filesystem access. The sandbox withholds the fix, but a determined agent could find the evaluation checkout elsewhere on disk.
- **One harness.** The runner drives Claude Code headless; other harnesses need their own dispatch and cost parsing.
- **Budget overshoot.** The budget is checked between runs, so the last run can exceed it by one run's cost.

## Running

```bash
evals/run.sh validate                          # unbilled; must pass before any live run
ANTHROPIC_API_KEY=... evals/run.sh run --budget-usd 40 --repeats 3 --seed 1
evals/run.sh report evals/results/results-<stamp>-<seed>.tsv
```

Live runs are billed and opt-in: `run` refuses without `--budget-usd` and an `ANTHROPIC_API_KEY` (the isolated `HOME` has no stored login). Results and per-run sandboxes (transcript JSON, acceptance and regression logs, `gh.log`) land in `evals/results/`, which is gitignored.

## Adding a task

`evals/tasks/<id>/` holds `task.env` (`ISSUE`, `BASE`, `FIX`, `REGRESSION`, `STRATUM`), `issue.md` (the issue as the agent will read it), and an executable `accept.sh <repo-dir>` that exits 0 only for a correct fix. `BASE` is the fix's parent; the reference fix is `FIX`'s diff minus tests and docs. Run `evals/run.sh validate <id>` before committing it.
