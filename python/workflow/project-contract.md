# Project: {{PROJECT_NAME}}

{{ONE_PARAGRAPH_DESCRIPTION}}

This repo is **public** on GitHub (`github.com/bbirkinbine/{{PROJECT_NAME}}`)
or will become public after the first feature lands. Treat every change as
world-readable from commit #1.

`AGENTS.md` is the single client-neutral project contract. `CLAUDE.md` is a
Claude Code import containing only `@AGENTS.md`. In a bootstrapped project,
edit `AGENTS.md`, not the import. In the scaffold, edit `workflow/` sources
and render the client surfaces.

Some referenced workflows and docs require `--python-core` or `--full`; use
them only when installed.

Standing rules are included below. Put project-specific additions outside the
marked generated block; never duplicate shared policy in a client directory.

This contract writes workflows as `/name`. Claude Code uses that slash command;
Codex uses `$name` or `/skills`. Both render from the same source.

## Shared workflow protocols

These defaults are authoritative for every phase workflow.

### Active-spec resolution

Resolve the active feature spec in this order:

1. If the arguments name a spec, require exactly one existing feature markdown
   path under `docs/specs/`.
2. Otherwise derive the number from `spec-NNNN-<slug>` (local mode) or
   `<issue-number>-<slug>` (issue mode), zero-pad it, and require exactly one
   `docs/specs/NNNN-*.md` match.
3. Otherwise require exactly one feature spec with `**Status:** shipping`.

On zero, multiple, ambiguous, or nonexistent matches, stop, list candidates,
and request an explicit path. Never choose the highest number: numbers are
identities, not sequence. `0000-product.md` is context, never the active spec.

### Semantic change set

All semantic reviews (`/analyze`, both reviewers, and enabled specialists) use
the same complete change set:

1. Resolve the integration base: configured review/PR target, else the remote
   default branch's symbolic ref, else local `main`, then `master`. A feature
   branch's tracking ref is not its integration base. If no unique base
   resolves, stop and request one.
2. Compute the merge-base of that ref and `HEAD`.
3. Inspect `git diff --find-renames <merge-base> --`, including committed,
   staged, and unstaged tracked changes.
4. Inspect `git status --short` and the contents of every path from
   `git ls-files --others --exclude-standard`; report policy-denied reads.

Pass the spec path, base, merge-base, status, and untracked manifest to each
reviewer. An explicit `<base>..<head>` requests a committed-range review that
may omit working-tree changes; disclose that limitation. Never default to
`git diff main...HEAD` or a merge-base-to-`HEAD` diff because both omit current
work.

Keep personal preferences in ignored local overlays (`CLAUDE.local.md`,
`.claude/settings.local.json`, or user Codex configuration), not shared
`AGENTS.md`, `CLAUDE.md`, `.claude/`, `.agents/`, or `.codex/` files.

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

Hold the active spec and drive the loop. Delegate for independent review and
to keep wide searches or noisy output out of the main context.

| Situation | Route to |
| --- | --- |
| Task touches > 3 files, or needs an exploratory report | `/plan` (`planner`) |
| About to implement anything past trivial | `/test-first` before any implementation code |
| Implementation done and `/review-check` is green | `/review` (and `/review-adversarial` on meaningful features) |
| Need full test output, a wide survey, or doc fetches | A focused subagent |
| A change would touch > 5 files | Stop and ask the human first |

Re-read the spec at phase boundaries and after context drift. Write a phase
handoff before changing sessions. Verify claims outside the gate (for example,
migrations or file comparisons) with a concrete check.

| Task size | The loop |
| --- | --- |
| Trivial: rename, typo, ≤ ~10 lines | Branch optional; skip spec and plan. |
| Small: one function/file | Branch; one-sentence spec; skip `/plan`; use `/test-first`. |
| Medium: 3–10 files | Full loop. |
| Large: refactor/new subsystem | `/adr` first; full loop; split into medium tasks and sessions. |

## Workflow expectations (Spec → Plan → Test-first → Implement → Verify)

`WORKFLOW.md` owns the walkthrough and `docs/workflow-diagram.md` the diagram.
For Medium/Large work, stop after drafting the spec for ownership, after
`/plan` for approval, and after Verify for commit authorization. Once the
plan is approved and persisted, autodrive test-first → implement → docs →
gate → review → fixes/re-review. Stop if tests, gates, or review invalidate
the spec. Never commit without approval.

Review findings are `[auto-fix]`, `[no-op]`, or `[ask-user]`. Apply
`[auto-fix]`, sync docs, rerun the complete gate, and obtain a fresh focused
review (full review for substantial fixes) until clear. Surface `[ask-user]`
verbatim and stop unless the human explicitly authorized unattended shipping.

- **Spec:** Before non-trivial work, create `docs/specs/NNNN-<feature>.md`
  with goal, criteria, non-goals, and external references. Use `/scope-check`
  or `/clarify`; put product direction in `0000-product.md` and costly
  cross-cutting decisions in ADRs.
- **Plan:** For >3 files, run `/plan` before tests or implementation. After
  approval, the orchestrator copies its file-by-file plan verbatim into
  `## Approved implementation plan`, updates the date, and marks the spec
  `shipping` before `/test-first`, compaction, client switch, or handoff.
  For Small work, mark the approved spec `shipping` before `/test-first`.
- **Test-first:** `/test-first` writes failing tests from the spec. Audit
  its file fingerprints, reject implementation edits, and rerun the focused
  test to confirm the expected failure. If installed, run `/analyze` before
  coding.
- **Implement:** Be on a feature branch; write the minimum passing code. For
  external-authority values, follow "External-reference provenance."
- **Docs:** Before review, correct affected docs. Change README only for pitch,
  installation, or user-facing changes. Add a doc only for standing guidance
  that fits no existing doc or docstring. Mark the spec `shipped` and
  regenerate its dashboard before final review.
- **Verify:** Run `/review-check`, then `/review`; add
  `/review-adversarial` for meaningful features. Add installed `/security` or
  `/performance` when their triggers match, and installed `/eval` for LLM
  products. Resolve and re-review fixes; then stop for commit authorization.
- **Bugs:** Reproduce first. The test must fail for the diagnosed cause before
  implementation and pass afterward.
- **Multi-day work:** Append `## Phase handoff` at each phase boundary and
  resume in a fresh session.
- If a change would touch > 5 files, stop and ask first.

## Detailed workflow guidance

Load each phase's workflow for procedure. `WORKFLOW.md` owns the walkthrough
and hooks; `docs/project-types.md` the inventory; `docs/codex-cli.md` startup
and trust; and installed `docs/parallel-agents.md` worktrees and unattended
runs. Surface conflicts with this contract.

Hooks, permissions, pre-commit, and CI neither grant authorization nor prove
correctness. The rules, complete gate, and fresh semantic review still apply.

## Don't-touch list

- `pyproject.toml` `[tool.uv]` section — ask first
- {{ADD_PROJECT_SPECIFIC_DONT_TOUCH — e.g., `src/{{PACKAGE_NAME}}/migrations/` if Alembic; vendored upstream files under `sources/`; generated artifacts under `out/`}}

## Open work / current state (updated {{YYYY-MM-DD}})

- {{WHAT_IS_IN_PROGRESS_OR_BLOCKED}}
- {{WHAT_THE_NEXT_SPEC_IS — e.g., "Spec for the next feature lives at `docs/specs/0001-<feature>.md`"}}
