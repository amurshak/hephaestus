# Hephaestus workflow assessment and redesign proposal

Status: proposed; no runtime behavior changed. Assessed 2026-09-07 against `a121813` (2.2.0).

Tracked in [#219](https://github.com/amurshak/hephaestus/issues/219), with implementation issues #220–239 and existing related work #168, #207, and #217. The tracker contains the complete coverage index and dependency sequence.

**Decision.** Replace the universal eight-phase execution prescription with a small delivery contract, native harness execution, and optional procedures for specific uncertainties. Retain the useful distribution and recovery work. Treat the reduced design as a candidate to evaluate, not an established improvement.

The strongest case for Hephaestus is reducing the human effort needed to coordinate, verify, deliver, and resume agent work. Its weakest assumption is that a prescribed decomposition into phases and roles reliably improves those outcomes. The current tests establish substantial confidence in installer and adapter behavior; they do not establish that the full workflow beats native harness behavior.

All 13 canonical workflows and all five canonical agents are covered below. Skills and slash commands are generated representations of these workflows, not separate product capabilities. This assessment also covers the conventions, templates, generators, installer, scheduler, and verification strategy.

**Evidence and confidence.** The preceding assessment ran all 16 test files successfully, all five adapter drift checks, composition and conventions checks, and changelog validation on this revision. No comparative delivery evaluation was run. Local contradictions below are direct findings; efficiency and organizational adoption recommendations are hypotheses.

Relevant external evidence:

- [Evaluating AGENTS.md, June 2026 revision](https://arxiv.org/html/2602.11988v2): in the studied Python tasks, context files produced no statistically significant overall task-resolution improvement, while increasing cost. Generated files increased average cost by 20–23%; developer files also added cost. This concerns repository context, not Hephaestus or complete organizational delivery, and does not settle security or maintainability outcomes.
- [Anthropic's long-running application experiments](https://www.anthropic.com/engineering/harness-design-long-running-apps): extra planning and evaluation improved selected application outcomes at substantial cost; some scaffolding became unnecessary as models improved. These examples are not a controlled comparison at equal resource budgets.

These findings support testing additions and removing obsolete procedures. They do not establish that either minimal or elaborate workflows always win.

**The proposed contract.** A task must identify its intended outcome, applicable project requirements, authorized endpoint, and evidence of completion. These are obligations, not seven mandatory reporting stages:

1. Work on the requested outcome. Accept a direct task, issue, or existing PR; do not require a new issue as an admission ticket.
2. Honor the user's and project's existing authorization. Continue through already-authorized actions without repeated confirmation. Distinguish implementation, PR creation, merge, and deployment; one does not automatically authorize every later endpoint.
3. Preserve unrelated work. Reuse valid existing branches and worktrees. Never make an arbitrary dirty checkout clean by committing, stashing, or publishing someone else's work.
4. Identify the actual change under consideration. Include branch commits, staged and unstaged changes, and relevant untracked files; use the appropriate base for ordinary and stacked work. State exclusions rather than silently omitting them.
5. Satisfy applicable acceptance criteria and project gates. An unresolved required behavior remains incomplete even if it has a TODO, follow-up issue, or documented limitation. Optional improvements can be deferred explicitly.
6. Report evidence honestly: what ran, against which revision, with what result and limitations. Unrun, blocked, and inapplicable checks have distinct meanings. Reuse evidence only while its code and relevant environment remain applicable.
7. Stop at the requested endpoint, or preserve enough task-specific state to resume a blocked attempt. No-work and useful partial progress are valid outcomes. Use existing PRs, issues, commits, or local notes as appropriate; do not create every artifact on every exit.

The organization owns policy and acceptance criteria. The harness chooses exploration, planning, editing, tool use, and delegation within that contract. Critical merge and access conditions belong in repository controls, CI, and harness permissions when enforceable there. Natural-language requirements still need behavioral evaluation; calling them a contract does not make them mechanically enforced.

**The execution pattern.** Start with the task and available evidence. Take the smallest useful action, inspect its result, and continue until the outcome is verified or a concrete blocker is established. A useful action may be an experiment, a plan, code, a test, research, or independent review. There is no required order among those methods beyond genuine dependencies and project policy.

Default to execution in the current agent. Add a delegate when there is a bounded independent question, worthwhile parallel work, substantial context to isolate, or a required independent check. Do not create a separate planning step merely to justify skipping other planning steps. For straightforward work, the selection should cost essentially nothing.

Keep finite failure bounds. Replace nested phase counters with one task-level recovery policy, using a finite attempt ceiling and no-progress detection. Stop repeating an approach without new evidence; preserve the blocker when the remaining alternatives exceed the authorized budget. The initial ceiling is an operational default to test, not a universal optimum. Unattended wall-time and repeated-session-failure limits must be enforced by the runner where possible; unavailable token accounting must not be advertised as a hard token limit.

**Disposition of every agent.** None is mandatory merely because a workflow was invoked. Retain existing role adapters during migration; do not rename or merge roles solely to reduce their count.

| Agent | Useful purpose | Current weakness | Proposed disposition |
|---|---|---|---|
| [coder](../../.ai/agents/coder.md) | Execute an independently scoped implementation task. | Delegation is prescribed even when the parent already has all the context. Syntax checking is weaker than validating the assigned behavior. Isolation differs by harness. | Optional implementation delegate. Parent may implement directly. Require explicit ownership and relevant behavioral evidence. Use actual harness isolation when available; otherwise respect shared-workspace constraints. |
| [explorer](../../.ai/agents/explorer.md) | Answer a bounded codebase question without filling the parent's context. | Broad reading and a five-part report can turn a simple lookup into a subsystem survey. | Optional investigation delegate. Ask a concrete question; return the answer, evidence, and unresolved uncertainty. Let the parent perform short searches directly. |
| [researcher](../../.ai/agents/researcher.md) | Investigate external facts with traceable sources. | Fixed multi-query/multi-source rules and a full report apply even to narrow lookups. The injection instruction says to stop, letting hostile source text derail the research. | Optional research delegate. Match depth to uncertainty. Ignore hostile instructions, use another source when necessary, and continue the authorized research. Keep source provenance and relevant limitations. |
| [reviewer](../../.ai/agents/reviewer.md) | Seek independent evidence of correctness failures and material risks. | Review scope is uncommitted changes; numeric scoring and prescribed investigation fractions suggest unmeasured precision. A second agent is not statistically independent merely because its context is separate. | Retain as an optional or policy-required adversarial check. Supply an explicit change scope and risk question. Report evidenced findings, severity, unresolved questions, and scope limits. Remove aggregate numerical ship scores. |
| [tester](../../.ai/agents/tester.md) | Execute lengthy checks or investigate ambiguous failures in isolated context. | Ordinary command execution is forced through an LLM delegate elsewhere. The role's change scope differs from the caller's, and PASS/FAIL cannot accurately describe blocked or incomplete checks. | Make test execution tool-first. Keep this delegate for costly output interpretation, independent acceptance checking, or long-running suites. Preserve exit status and distinguish failing behavior from unavailable infrastructure. |

Role-specific access restrictions remain useful when the harness enforces them. A shell-bearing agent instructed to be read-only is not a security boundary. Test runners need artifact writes; that does not imply permission to edit source. Prefer native capabilities and a concise statement of actual access over simulated tool restrictions. Model tiers remain optional routing configuration; their performance and cost should be measured rather than presumed optimal from role names.

**Disposition of every workflow and generated skill/command.** Preserve names initially where useful. Reduce compulsory execution before changing discovery or compatibility surfaces.

| Workflow | Decision | Resulting behavior and rationale |
|---|---|---|
| [orient](../../.ai/workflows/orient.md) | Keep; narrow. | Inspect current state and relevant project requirements. Report missing setup and resumable work. Move scaffolding to installation/setup and destructive reaping to explicit cleanup. Orientation should not become an unsolicited maintenance run. |
| [create-issue](../../.ai/workflows/create-issue.md) | Keep as optional artifact utility. | Establish problem and acceptance criteria with proportionate investigation. No mandatory explorer for already-specified work. Create an issue only when requested or already authorized by the workflow's scope; issue creation is not a prerequisite for coding. |
| [start-issue](../../.ai/workflows/start-issue.md) | Rewrite as the primary adaptive execution procedure. | Resolve the task, relevant context, and current branch; act and verify. Plan or delegate when useful. Reuse existing work rather than blindly creating another branch. Do not silently treat a skipped requirement as completion. Preserve the implementation-ready endpoint. |
| [autopilot](../../.ai/workflows/autopilot.md) | Reduce to a thin driver of the same procedure. | Select authorized work and continue to the authorized delivery endpoint. Stop on an empty or ineligible queue. Remove automatic invention of work and implicit expansion into additional issues. Broad maintenance remains available when explicitly requested as the objective. |
| [critique](../../.ai/workflows/critique.md) | Keep; replace scoring ceremony with findings. | Evaluate a supplied proposal or change scope. Use explicit invocation intent rather than dirty-state-only mode detection. Review lockfile and documentation changes according to their consequences, not an unconditional file-type exemption. Additional reviewers need a distinct question or demonstrated benefit. |
| [test-issue](../../.ai/workflows/test-issue.md) | Keep as a verification entry point. | Run required gates, verify applicable criteria, and report evidence. Share change-scope rules with review and delivery. Delegate only when warranted. Do not repeat an unchanged check solely because another command has been invoked. |
| [ship](../../.ai/workflows/ship.md) | Keep; separate delivery requirements from method. | Establish final revision and applicable evidence, complete required docs before final validation, and create/update the PR. Merge when authorized and policy conditions are satisfied. Optional review is never reported as performed when omitted. No generic claim that there are no regressions. |
| [finish](../../.ai/workflows/finish.md) | Keep; sharply reduce its mutation scope. | Reconcile observed PR/issue state and clean only task-owned resources with unchanged expected identities. Restore only the exact task-owned stash when safe. Remove repository-wide branch sweeps, automatic new work, and routine post-merge doc changes. |
| [refactor](../../.ai/workflows/refactor.md) | Fold execution into the shared procedure; retain a thin specialty entry point. | Supply behavior-preservation constraints and characterization tests where useful. Require a stated maintenance or architectural benefit. Line count and function count are optional diagnostics, not success criteria. Do not maintain another delivery pipeline. |
| [research](../../.ai/workflows/research.md) | Keep as optional evidence-gathering utility. | Answer the question with sufficient sources and uncertainty. Directly handle narrow lookups; delegate independent substantial facets. No automatic conversion of every finding into development work. |
| [update-docs](../../.ai/workflows/update-docs.md) | Keep; scope to a supplied change. | Accept a revision range, PR, or explicit topic rather than assuming the last five commits. Follow project doc policy. Update affected documentation before delivery and stage only owned edits. Do not automatically append more ambient agent instructions after every task. |
| [update-hephaestus](../../.ai/workflows/update-hephaestus.md) | Retain as a thin maintenance wrapper. | Invoke install-aware update tooling, report the actual version transition, and scope staging to owned paths. Prefer an approved revision/release for organizations; avoid changing the active workflow mid-task. |
| [worktrees](../../.ai/workflows/worktrees.md) | Keep as an opt-in operations utility. | Preserve status/cleanup modes and bounded parallelism. Separate workspace preparation, scheduling, and launch decisions. Check current branch identities and dirty/unpushed state before reaping. Do not assume shared services or disjoint files imply independent execution. |

This leaves one implementation procedure, delivery/reconciliation utilities, and optional task-specific methods. Existing command names can remain useful entry points without each carrying its own mandatory process. An internal common procedure must be available in every installation mode; do not create an unresolved source-only include or duplicate the same prose into hand-maintained workflows.

**Rules to remove from the default path.** Mandatory plan-critique rounds; mandatory explorer/coder/tester delegation; aggregate numerical verdicts; automatic self-triage on an empty queue; unconditional issue creation on wind-down; global branch cleanup; arbitrary five-commit documentation scope; and refactoring success measured by shrinking code. Remove unconditional lockfile auto-pass separately as a correctness fix. Keep required project checks, authorization, honest evidence, and preservation of unrelated work.

**Supporting surfaces.** These are part of the product's economics and reliability even though they are not agent roles.

| Surface | Decision |
|---|---|
| [.ai/conventions.md](../../.ai/conventions.md) | Rewrite around the delivery contract and stopping conditions. Retire the universal eight-phase claim. Keep a concise shipped restatement where installations need it. |
| Harness generators and generated adapters | Keep canonical generation and drift checks. Prefer native discovery and roles. Separate harness-specific mechanics from workflow semantics so incidental wording is not an API. Make changes only after probing the installed CLI; no speculative universal adapter framework. |
| Installer, updater, uninstaller | Preserve ownership manifests, idempotence, environment-root handling, and tests. Narrow setup to the chosen harness and missing project requirements. Do not make broad distribution rewrites a prerequisite for the workflow experiment. |
| Model mappings | Retain optional overrides. Compare inherited/default routing with role-specific routing; do not make a naming migration part of the redesign. |
| Project templates | Prefer existing project instructions. Keep tool commands and unusual constraints concise. Stop generating redundant command/role catalogs into ambient context when native discovery suffices. Preserve existing CLAUDE.md compatibility without requiring that filename in every future installation. |
| Hooks and CI | Use existing enforceable controls for required gates. Document actual coverage: Edit/Write hooks do not cover arbitrary shell writes, and matching the text `git commit` does not intercept every way to commit. Avoid claiming a template hook is a sandbox. |
| [loop.sh](../../loop.sh) | Retain only for intentionally scheduled work. Add operational bounds for sessions and repeated failures, propagate meaningful outcomes, and stop or idle on no eligible work according to scheduling policy. A fresh context is a recovery option, not a universal performance improvement. |
| Tests | Preserve installer/generator regression coverage. Replace obsolete phase-count/prose contracts as the spec changes. Add behavioral scenarios that execute real helpers or inspect actual agent traces and repository outcomes; a test-only model of the desired logic is insufficient proof. |
| README and plugin metadata | Explain the delivery contract, supported endpoints, and optional methods. Remove claims of deterministic agent compliance or universal workflow optimality. Lead with one practical example; keep the OODA analogy optional historical context. |

**Correctness work justified without an efficiency benchmark.**

- [Implementation commits its work](../../.ai/workflows/start-issue.md), while [review reads only uncommitted diffs](../../.ai/agents/reviewer.md). Establish and pass explicit scope; a clean checkout must not make a nonempty branch change disappear from review.
- [Finish deletes by historical branch names](../../.ai/workflows/finish.md) and searches for any matching stash before popping the top stash. Restrict cleanup to the task and verify exact current identities; ambiguous ownership means leave the resource in place and explain why.
- [Critique auto-passes lockfiles](../../.ai/workflows/critique.md). Dependency changes can alter runtime behavior, so file extension alone is not sufficient evidence to bypass required review.
- [Start-issue can skip blocked tasks with TODOs](../../.ai/workflows/start-issue.md). Separate optional work from required acceptance criteria and report partial work accurately.
- [Ship modifies docs after quality gates](../../.ai/workflows/ship.md), and later repairs can also change reviewed code. Tie evidence to the delivered revision and rerun affected checks when intervening changes invalidate it.
- [Ship's failure paths](../../.ai/workflows/ship.md) need explicit terminal dispositions. An exhausted fix attempt or failed required gate must not fall through into an ordinary merge-ready PR or unconditional merge step.

Implement these as focused changes with scenario tests. Do not use a large redesign to obscure or postpone them.

**Evaluation before organizational rollout.** Compare three variants on representative task strata: native harness with existing project controls; the proposed minimal contract; and the full workflow with the same correctness fixes. Freeze model/harness versions, task scope, environments, available tools, authorization, and organizational requirements. Keep changes isolated and prevent cross-run leakage of solutions or review feedback.

Include routine fixes, moderate features, unfamiliar debugging, behavior-preserving refactors, high-consequence changes, and work requiring session recovery. Separately test organizational cases: dirty starting tree, clean committed change, stacked branch, reused branch name, missing credentials, failing required gate, merge pending, interrupted run, and no eligible work. A syntax-only benchmark will not measure the intended product.

Measure accepted completion, human intervention minutes, elapsed time, inference expenditure, reviewer repair effort, invalid completion claims, preservation failures, and subsequent corrections. Retain failed, timed-out, and abandoned runs in the denominator. Require the same acceptance standard for every variant; validate outcomes independently of the workflow's self-reported verdict. Include human review because tests alone miss maintainability and requirement errors.

Use an initial paired pilot of roughly 30–50 tasks to estimate variance and identify large effects; it is not enough to prove rare-event safety or small quality differences. Repeat runs where stochastic outcomes matter, randomize order, report uncertainty and per-task-class results, and expand sample size according to the differences the organization considers material. Evaluate both equal-budget success and cost to reach a common acceptance standard.

Choose the primary measure and acceptable quality margin before looking at results. A reasonable organizational objective is total delivery cost, including human coordination and correction, subject to required quality and policy constraints. Tokens are a component, not the objective by themselves. A faster workflow that shifts work to reviewers has not necessarily improved delivery.

Then remove or add one component at a time: explicit plans, independent review, delegated implementation, delegated testing, and recovery artifacts. Retain components where they improve relevant outcomes enough to justify their cost, or where an explicit organizational obligation requires them. Native execution is an acceptable winner. Repeat the comparison after material model/harness upgrades rather than preserving old scaffolding indefinitely.

**Implementation sequence.**

| Stage | Work | Exit criterion |
|---|---|---|
| 1. Establish scope and evidence | Fix review/test scope, revision binding, completion truth, and cleanup identity checks in focused changes. | Concrete failure scenarios covered; existing suite and all drift gates pass. |
| 2. Build one reduced candidate | Revise the conventions and primary execution procedure; remove compulsory delegation and scoring; make autopilot a thin authorized-endpoint driver; make empty queues valid. | A routine task completes without compulsory planning/delegation; required project controls still hold; full-workflow baseline retained as a pinned revision. |
| 3. Consolidate optional methods | Apply the agent/workflow dispositions above; reuse verification evidence; scope docs and cleanup; update generated adapters and templates. | Existing entry points resolve with documented behavior, all installation modes work, no hidden source-only dependencies. |
| 4. Evaluate and select | Run the paired pilot and component comparisons. | Publish task-class outcomes, costs, uncertainty, failures, and the chosen default with reasons. |
| 5. Roll out and prune | Migrate defaults with release notes and a recoverable prior version; remove obsolete prose/tests; retain explicit policy requirements. | Organizations can adopt or roll back without losing project-owned configuration; future upgrades have a scheduled reevaluation path. |

Workflow implementation should occur in an isolated checkout because the main clone is linked into live harness configurations. Change the spec and canonical workflows first, adjust affected convention/composition tests, update README and contributor docs where required, add changelog fragments, and regenerate all adapters together. Run the full integration suite and every drift check. Probe affected harness mechanics locally before changing their generator assumptions.

No new workflow DSL, database, router service, or sprawling configuration schema is justified by this assessment. Add small deterministic helpers only where actual identity, status, evidence, or bounded-execution requirements need enforcement. Use existing Git/PR artifacts to preserve state. Version the shipped instructions so a task does not silently change policy halfway through execution.

**Adversarial check of this proposal.** The reduced contract could merely replace one layer of verbose instructions with another. It could also remove helpful prompts for weaker models, under-trigger independent review, or move coordination work back to people. A supposedly small helper layer could grow into the orchestration platform this project intentionally avoids. These are reasons to keep the candidate small, retain comparable baselines, measure human effort, and permit task-specific procedures. The strongest objection to immediate adoption is the same as for the current system: favorable reasoning is not outcome evidence.

General-critique dimensions for the current universal-pattern claim (judgment, not measured performance): logic 6/10, assumptions 4/10, completeness 5/10, trade-offs 5/10, evidence 4/10, second-order effects 5/10, timing/context 6/10. Overall verdict: RETHINK as a mandatory organization-wide execution pattern. The reduced proposal is SOUND as a bounded experiment, with its production advantage still unproven.

The next implementation unit is Stage 1. It protects current users, makes the later comparison fairer, and establishes the change/evidence boundary needed by every candidate workflow.
