# Project: {{PROJECT_NAME}}

{{ONE_PARAGRAPH_DESCRIPTION}}

This repo is **public** on GitHub (`github.com/bbirkinbine/{{PROJECT_NAME}}`)
or will become public after the first feature lands. Treat every change
as world-readable from commit #1.

`AGENTS.md` is the single client-neutral project contract. `CLAUDE.md` is a
thin Claude Code adapter containing `@AGENTS.md`, so both clients load that
same contract without duplicating policy. In a bootstrapped project, edit
`AGENTS.md`; leave the import adapter alone. In the scaffold, edit
`workflow/project-contract.md` and render the client surfaces.

> **Profiles.** This file ships in every bootstrap profile and describes
> the full workflow surface. Some workflow commands and `docs/` files it
> mentions install only under the richer profiles (`--python-core` or
> `--full`); on a thinner install, treat those as "available if enabled"
> rather than guaranteed present.

**Standing rules are included at the end of this contract.** When the human
corrects a recurring mistake in a bootstrapped project, encode the
project-specific fix outside the marked generated block in `AGENTS.md`.
Do not add an independent policy copy to a client-specific directory. In the
scaffold source repository, edit the relevant `workflow/` source and render
the adapters. Standing instructions are the error log that compounds.

**Workflow invocation differs by client.** This contract uses `/name` as
compact workflow notation. In Claude Code, invoke the matching slash command
(`/plan`). In Codex, invoke the repository skill (`$plan`) or select it from
`/skills`. Both adapters are rendered from the same workflow source and stop
at the same checkpoint.

## Shared workflow protocols

The phase workflows use the protocols below. They are client-neutral and
authoritative; a command or skill must not invent a different default.

### Active-spec resolution

Resolve the active feature spec in this order:

1. **Explicit path.** If the workflow arguments name a spec, require exactly
   one existing feature markdown path under `docs/specs/` and use it.
2. **Branch identity.** Otherwise, derive the work-item number from the current
   branch (`spec-NNNN-<slug>` in local mode or `<issue-number>-<slug>` in issue
   mode), zero-pad it, and require exactly one matching
   `docs/specs/NNNN-*.md`.
3. **In-flight status.** Otherwise, use the only spec whose header contains
   `**Status:** shipping`.

If an attempted step has zero matches, multiple matches, an ambiguous or
nonexistent explicit argument, or a branch number that does not resolve
uniquely, stop and list the candidates. Ask for an explicit spec path. Never
choose the highest-numbered spec: spec numbers are identities, not execution
order. The product spec `0000-product.md` is standing context, never the
active feature spec.

### Semantic change set

`/analyze`, `/review`, `/review-adversarial`, and enabled specialist reviews
must inspect the same complete change set by default:

1. Resolve the integration base, not the current feature branch's tracking
   ref: use an explicitly configured review/PR target when the project names
   one; otherwise use the remote default branch's symbolic ref, then local
   `main`, then local `master`. A tracking ref such as `origin/my-feature` is
   not the integration base merely because Git calls it the branch's
   "upstream." If there are multiple plausible remote defaults, or no base can
   be resolved, stop and ask for an explicit base.
2. Compute the merge-base of that ref and `HEAD`.
3. Inspect the one-endpoint diff from that merge-base to the current working
   tree (`git diff --find-renames <merge-base> --`). Unlike
   `<merge-base>..HEAD`, this includes committed branch changes plus staged and
   unstaged tracked changes.
4. Inspect `git status --short` and every path returned by
   `git ls-files --others --exclude-standard`. The patch in step 3 cannot show
   untracked files, so their contents are a required part of the review, not an
   optional add-on. If policy denies a file read, report that limitation rather
   than silently omitting the path.

Record the resolved spec path, base ref, merge-base, status output, and
untracked-path manifest in the review input so both reviewers see the same
snapshot. An explicit `<base>..<head>` argument requests a historical
committed-range review and may omit current working-tree changes; say so in the
result. Never use `git diff main...HEAD` or
`git diff $(git merge-base HEAD main)..HEAD` as the default pre-commit review:
both omit the work that is waiting to be reviewed.

**Personal preferences stay out of the shared files.** Machine-local or
per-person overlays belong in client-local ignored files, such as
`CLAUDE.local.md`, `.claude/settings.local.json`, or the user's Codex
configuration. `AGENTS.md`, `CLAUDE.md`, `.claude/`, `.agents/`, and
`.codex/` are team-shared; don't encode one person's editor, pace, or
verbosity preferences in them.

## Stack

- Python 3.12 (managed by `uv`)
- {{ADD_PROJECT_SPECIFIC_LIBS — e.g., FastAPI / Pydantic v2 / SQLAlchemy 2.0 / httpx / lxml / logging choice}}
- pytest + pytest-asyncio
- ruff (lint + format) + mypy (strict)

## How to run things

- Install: `uv sync`
- Run app: `uv run python -m {{PACKAGE_NAME}}.main` (or `uv run {{ENTRY_POINT}}`)
- Run tests: `uv run pytest`
- Lint: `uv run ruff check . && uv run ruff format --check .`
- Type-check: `uv run mypy src/`
- Single test: `uv run pytest path/to/test.py::test_name -xvs`

## Your role: orchestrator

Hold the active spec and drive the loop, not just the edit. Delegate for
independence (fresh reviewers must not inherit implementation reasoning) and
context hygiene (wide searches, raw test output, and log scraping return as
summaries rather than displacing the goal).

Delegation decision rules — apply these without being asked:

| Situation | Route to |
| --- | --- |
| Task touches > 3 files, or you'd say "go figure out X and report back" | `/plan` — the `planner` subagent |
| About to implement anything past trivial | `/test-first` before any implementation code |
| Implementation done and `/review-check` is green | `/review` (and `/review-adversarial` on meaningful features) |
| Need full test output, a wide survey, or doc fetches | A focused subagent |
| A change would touch > 5 files | Stop and ask the human first |

Re-read the active spec at every phase boundary and after context drift. If a
session grows long, write the phase handoff before starting a fresh one.

Verify claims the gate cannot see with a concrete check before reporting
them. A green code gate does not prove that a scrub, migration, deployment, or
file comparison worked.

Scale the loop to the task — heavyweight process on trivial work is its
own failure mode:

| Task size | The loop |
| --- | --- |
| Trivial — rename, typo, ≤ ~10 lines | Branch optional; skip spec and plan; just do it. |
| Small — one function, one file | Branch; spec = one sentence; skip `/plan`; `/test-first` still required. |
| Medium — 3–10 files | Full loop. |
| Large — refactor or new subsystem | Record the cross-cutting technical decision as an ADR (`/adr`) first; full loop; split into medium tasks; do not run it all in one session. |

## Workflow expectations (Spec → Plan → Test-first → Implement → Verify)

The human-facing walkthrough lives in `WORKFLOW.md`; the rendered
diagram is in `docs/workflow-diagram.md`. Honor each phase — don't run
open-ended.

**Autodrive between checkpoints.** Spec authoring has its own ownership
checkpoint: a newly drafted spec is not approved merely because it exists.
For Medium and Large work after that, stop at two implementation checkpoints:
after `/plan` for plan approval, and after the complete Verify loop below for
authorization to commit. A green `/review-check` is not the final checkpoint.
After plan approval, persist the approved plan and mark the spec `shipping`,
then drive `/test-first` → implement → docs sync → gate → fresh review →
fix/gate/re-review without waiting for a per-phase prompt. Never commit on your
own (see the **Git workflow** standing rule below). If `/test-first`, the gate,
or a reviewer shows the spec is wrong, stop and raise it rather than coding
around it. Trivial and Small work keep the scaled-down loop above.

**Handling review findings.** `/review` and `/review-adversarial` tag
each finding: `[auto-fix]` (mechanical — apply it, re-run
the full gate and obtain a focused fresh re-review), `[no-op]`
(informational), or `[ask-user]` (challenges a deliberate spec decision or
changes product behavior). During autodrive, resolve `[auto-fix]` findings
yourself, sync any docs the fix affects, run the complete gate, then ask a
fresh reviewer to verify the resolutions and inspect the fix delta. A
substantial fix gets a full fresh review. Repeat until no must-fix finding
remains. An `[ask-user]` finding is a hard stop — surface it verbatim and
wait. The one exception is an explicit instruction to run unattended ("just
ship it"), which is standing consent to resolve `[ask-user]` findings too.

- **Spec.** Before non-trivial work, create
  `docs/specs/NNNN-<feature>.md` with the goal, success criteria, non-goals,
  and declared external references. A drafted spec still stops for human
  ownership before `/plan`; use `/scope-check` or `/clarify` when ambiguity
  remains. Product direction belongs in `0000-product.md`; a costly,
  cross-cutting technical decision belongs in an ADR.
- **Plan.** For tasks that touch > 3 files: `/plan` first. Review the
  proposed plan before any implementation or test writes happen. When the
  human approves it, the orchestrator (not the read-only planner) copies the
  approved file-by-file plan verbatim into the active spec under
  `## Approved implementation plan`, updates `**Last updated:**`, and changes
  `**Status:** draft` to `shipping`. Persist this before `/test-first`,
  compaction, a client switch, or a phase handoff. If plan is skipped for a
  Small task, mark the human-approved spec `shipping` immediately before
  `/test-first`.
- **Test-first.** Tests come before implementation. `/test-first` writes
  failing pytest tests from the spec; the orchestrator audits the subagent's
  before/after file fingerprints, rejects any implementation-path edit, and
  independently re-runs the focused tests to show the expected failure.
  Only then implement. If installed, `/analyze` after tests cross-checks
  spec ↔ tests coverage in a fresh read-only context before implementation.
- **Implement.** You must already be on a feature branch (see the
  **Git workflow** standing rule below). Write the minimum code to make
  the tests pass. External-authority values follow **Python code
  conventions** → "External-reference provenance".
- **Docs sync.** Before the gate and semantic review, update every `docs/`
  statement the change made false. Change the README only when the pitch,
  install path, or user-facing surface changed. Add a new doc only for
  standing explanation that fits neither an existing doc nor a docstring.
  Close the work on the same branch: mark the active spec `shipped` and
  regenerate its dashboard before final review, not in a follow-up PR.
- **Verify.** After docs sync, run `/review-check` (ruff lint, ruff format,
  mypy, pytest), then `/review` over the complete semantic change set;
  `/review-adversarial` as well on meaningful features when installed. Add
  `/security` and/or `/performance` if the opt-in subagent and command are
  installed and the diff trips its triggers. If the product itself contains
  an LLM/AI surface and the `evaluator` subagent plus `/eval` command are
  installed, `/eval` is part of Verify too — it judges output quality a test
  can't assert (`docs/evals.md`). Deterministic projects ship no LLM surface
  and skip it. Apply `[auto-fix]` findings, resync affected docs, rerun the
  complete gate, and obtain a focused fresh re-review; repeat until clear.
  Only then stop at the final human checkpoint before commit.
- **Bug fixes — confirm the cause before the fix.** Reproduce the
  failure first, then have `/test-first` write a test that fails *for
  the reason you believe is the cause*. A reproducing test that fails
  for a different reason means the diagnosis is wrong — fix the
  diagnosis, not the symptom. Don't commit until that test goes
  red → green.
- **Phase handoff on multi-day features.** Append a `## Phase handoff`
  section to the spec at each phase boundary, then start a fresh session
  and resume from it — see `WORKFLOW.md` → "Phase handoff".
- If a change would touch > 5 files, stop and ask first.

## Detailed workflow guidance

Keep the root contract focused on decisions that must apply in every turn.
Load the phase's command or skill for its procedure. `WORKFLOW.md` owns the
human walkthrough and hook behavior; `docs/project-types.md` owns the profile,
agent, skill, and command inventory; `docs/codex-cli.md` owns client-specific
startup and trust; `docs/parallel-agents.md` owns worktrees and unattended
runs when installed. If those references disagree with this contract, stop
and surface the drift.

Hooks, client permissions, pre-commit, and CI are defense in depth, not
authorization and not proof of correctness. The behavioral rules still apply
when a hook is unavailable or bypassed, and the complete gate plus fresh
semantic review remain required.

## Don't-touch list

- `pyproject.toml` `[tool.uv]` section — ask first
- {{ADD_PROJECT_SPECIFIC_DONT_TOUCH — e.g., `src/{{PACKAGE_NAME}}/migrations/` if Alembic; vendored upstream files under `sources/`; generated artifacts under `out/`}}

## Open work / current state (updated {{YYYY-MM-DD}})

- {{WHAT_IS_IN_PROGRESS_OR_BLOCKED}}
- {{WHAT_THE_NEXT_SPEC_IS — e.g., "Spec for the next feature lives at `docs/specs/0001-<feature>.md`"}}
