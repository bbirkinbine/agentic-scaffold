# Project: {{PROJECT_NAME}}

{{ONE_PARAGRAPH_DESCRIPTION}}

This repo is **public** on GitHub (`github.com/bbirkinbine/{{PROJECT_NAME}}`)
or will become public after the first feature lands. Treat every change
as world-readable from commit #1.

An `AGENTS.md` stub sits alongside this file as a portable pointer for
non-Claude agents (Codex, Cursor, Gemini, etc.). `CLAUDE.md` is the
source of truth; `AGENTS.md` points back here.

> **Profiles.** This file ships in every bootstrap profile and describes
> the full workflow surface. Some slash commands and `docs/` files it
> mentions install only under the richer profiles (`--python-core` or
> `--full`); on a thinner install, treat those as "available if enabled"
> rather than guaranteed present.

**Standing rules are split between this file and `.claude/rules/`.**
Rules without a `paths` frontmatter load every session (git workflow,
commit style, public-repo hygiene); path-scoped rules load when matching
files are touched (Python code conventions, agent-legible code,
external-reference provenance). Both carry the same authority as this
file. When the human corrects a recurring mistake, encode the fix in
this file or the relevant rule in the same change — standing
instructions are the error log that compounds.

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

You are the orchestrator for this repo — not only a coder. Your standing
job is to hold the high-level goal (the active spec) and drive the loop,
delegating focused or verbose work to subagents so your own context
stays clean enough to keep that goal in view. Context that fills with
raw test output and file dumps is context that has lost the plot.

Two distinct reasons to delegate — both matter:

- **Independence.** A reviewer that has already seen the implementation
  reasoning is not an independent reviewer. Hand the diff to a fresh
  subagent that has not.
- **Context hygiene.** Verbose work — codebase-wide searches, full test
  output, doc fetches, log scraping — burns the context you need for
  the goal. Push it into a subagent; only the summary returns.

Delegation decision rules — apply these without being asked:

| Situation | Route to |
| --- | --- |
| Task touches > 3 files, or you'd say "go figure out X and report back" | `/plan` — the `planner` subagent |
| About to implement anything past trivial | `/test-first` before any implementation code |
| Implementation done and `/review-check` is green | `/review` (and `/review-adversarial` on meaningful features) |
| Need full pytest output, a wide codebase survey, or doc fetches | A subagent — keep the verbose output out of your own context |
| "Who calls this?" / symbol nav on a *large* repo, with `serena` enabled | The `serena` MCP — query the index, don't grep-storm |
| A change would touch > 5 files | Stop and ask the human first |

**Re-anchor on the spec.** `docs/specs/NNNN-*.md` is the source of truth
for *what* you are building. Re-read the active spec at the start of
each phase, and any time the conversation has drifted from it. If your
context is getting long mid-feature, stop at a phase boundary and
`/clear` — see `WORKFLOW.md` → "Phase handoff".

**Verify before you report.** `/review-check`, the Stop-gate hook when
`--strict-hooks` is enabled, and CI mechanically verify the *code* — but
a claim the gate can't see ("the scrub worked", "these two files are
duplicates", "the service came back up") is only true once you have
proven it. Before you state an outcome,
run the concrete check that confirms it and show the output. "Looks
done" with no command behind it is a guess, and a confident wrong claim
costs more than the check would have.

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

**Autodrive between checkpoints.** When handed a spec to implement,
drive the loop yourself end to end — branch, `/test-first`, implement to
green, `/review-check` — without waiting for a per-phase prompt. Stop
and surface output at exactly two human checkpoints: after `/plan`
(before tests), and after `/review-check` passes (before commit). Never
commit on your own (see `.claude/rules/git-workflow.md`). If
`/test-first` or the gate shows the spec is wrong, stop and raise it
rather than coding around it. This applies to Medium and Large tasks;
Trivial and Small keep the scaled-down loop above.

**Handling review findings.** `/review` and `/review-adversarial` tag
each finding: `[auto-fix]` (mechanical — apply it, re-run
`/review-check`), `[no-op]` (informational), or `[ask-user]` (challenges
a deliberate spec decision or changes product behavior). During
autodrive, resolve `[auto-fix]` findings yourself; an `[ask-user]`
finding is a hard stop — surface it verbatim and wait. The one exception
is an explicit instruction to run unattended ("just ship it"), which is
standing consent to resolve `[ask-user]` findings too.

- **Spec.** Before any non-trivial work, write a short spec under
  `docs/specs/NNNN-<feature>.md` (see `docs/specs/README.md` for the
  numbering, local-only mode, required sections, and
  `## External references` provenance). One paragraph minimum: goal,
  success criteria, non-goals.
  On ambiguous features, use `/scope-check` before and `/clarify` after
  the draft if those commands are installed. Product-level direction
  lives in `docs/specs/0000-product.md` (written by the `/product-spec`
  interview, if present); feature specs
  link to it rather than restating product rationale. Cross-cutting
  *technical* decisions — ones costly to reverse that several features
  inherit (storage engine, async/sync boundary, public API shape, auth
  model) — go in an ADR (`/adr`, see `docs/adr/README.md`), not the
  feature spec.
- **Plan.** For tasks that touch > 3 files: `/plan` first. Review the
  plan before any writes happen.
- **Test-first.** Tests come before implementation. `/test-first` writes
  failing pytest tests from the spec; show the failing-test output.
  Only then implement. If installed, `/analyze` after tests cross-checks
  spec ↔ tests coverage before the implementation work starts.
- **Implement.** You must already be on a feature branch (see
  `.claude/rules/git-workflow.md`). Write the minimum code to make the
  tests pass. External-authority values follow
  `.claude/rules/python-code.md` → "External-reference provenance".
- **Verify.** Run `/review-check` (ruff lint, ruff format, mypy,
  pytest), then `/review` on the diff; `/review-adversarial` as well on
  meaningful features when installed. Add `/security` and/or
  `/performance` if the opt-in subagent and command are installed and the
  diff trips its triggers. If the product itself contains an LLM/AI
  surface and the `evaluator` subagent plus `/eval` command are installed,
  `/eval` is part of Verify too — it judges output quality a test can't
  assert (`docs/evals.md`). Deterministic projects ship no LLM surface
  and skip it.
- **Bug fixes — confirm the cause before the fix.** Reproduce the
  failure first, then have `/test-first` write a test that fails *for
  the reason you believe is the cause*. A reproducing test that fails
  for a different reason means the diagnosis is wrong — fix the
  diagnosis, not the symptom. Don't commit until that test goes
  red → green.
- **Phase handoff on multi-day features.** Append a `## Phase handoff`
  section to the spec at each phase boundary, then `/clear` and resume
  fresh — see `WORKFLOW.md` → "Phase handoff".
- If a change would touch > 5 files, stop and ask first.

## Code navigation (optional: `serena` MCP)

Default to the built-in tools — `grep` / `glob` / `read`, with a
subagent for wide surveys. **Do not enable `serena` on a fresh or small
repo.** Enable it only once a repo is large or long-lived — when the
agent burns most of its turns re-reading files to rebuild the same
structural map every session. Setup, verification, update, teardown:
`docs/serena-setup.md` (installed with `--full` / `--advanced-docs`).

## Subagents (in `.claude/agents/`)

- `planner` — read-only; produces a plan in markdown.
- `test-first` — writes failing pytest tests from a spec; never writes
  implementation.
- `reviewer` — independent diff reviewer; checks spec match, test
  quality, edge cases, file size, public-repo hygiene.
- `reviewer-adversarial` — same independence, adversarial framing;
  argues against the change. Pair with `reviewer` on meaningful
  features; same output schema for side-by-side reading.

Opt-in (copy from the scaffold's `.claude/agents/optional/`):
`security-reviewer` (network surface, auth, untrusted input, secrets,
deserialization), `performance-reviewer` (hot paths, DB queries on
user-sized data, async, load), and `evaluator` (only when the *product*
contains an LLM/AI surface — authors and runs evals that judge output
quality against a rubric; see `docs/evals.md`).

## Skills (in `.claude/skills/`)

- `python-module-split` — auto-invoked when a `.py` file approaches 300
  lines; splits a module into a package preserving the public API.
- `python-docstrings` — auto-invoked when a public symbol is added or
  touched; enforces Google-style docstrings.
- `dependency-hygiene` — auto-invoked when `pyproject.toml` adds a dep;
  surfaces maintenance/license/advisory checks before the dep lands.

## Slash commands (in `.claude/commands/`)

Bootstrap profiles decide which commands are installed. `--minimal`
includes only `/spec`, `/plan`, `/test-first`, `/review-check`, and
`/review`; `--python-core` adds the attended workflow helpers;
`--full` adds the optional-reviewer stubs.

| Command | Purpose |
| --- | --- |
| `/product-spec [name]` | Optional: interview to create/refresh `docs/specs/0000-product.md` (the product-level spec) |
| `/scope-check <desc>` | Optional pre-spec: five forcing questions on ambiguous features |
| `/spec <name>` | Create `docs/specs/NNNN-<slug>.md` scaffold; stops for human edit |
| `/clarify [spec]` | Interrogate a draft spec's underspecified areas; writes answers back in |
| `/adr <title>` | Record an architecture decision at `docs/adr/NNNN-<slug>.md` (independent numbering; for large/cross-cutting technical choices) |
| `/specs-status [filter]` | Refresh the `## Status` dashboard in `docs/specs/README.md` and print the status table in chat |
| `/plan [spec]` | Invoke `planner` on the spec |
| `/test-first [spec]` | Invoke `test-first` |
| `/analyze [spec]` | Read-only consistency check: spec ↔ tests ↔ diff ↔ standing rules |
| `/review-check` | Local quality gate (ruff, format, mypy, pytest); refuses to pass on failure |
| `/review [range]` | Invoke `reviewer` on the diff |
| `/review-adversarial [range]` | Invoke `reviewer-adversarial` on the same diff |
| `/security`, `/performance [range]` | Opt-in reviewers, if installed |
| `/eval [spec]` | Opt-in: author/run the eval suite for an LLM/AI feature, if `evaluator` is installed |

## Hooks and guardrails

Defense in depth, soft to hard — each is one layer, none is a guarantee:

- **SessionStart** (`branch-check.sh`) warns when a session opens on
  `main`.
- **PreToolUse** (`block-destructive.sh`) blocks unrecoverable Bash
  commands (`rm -rf /`, `git clean -fd`, `mkfs`, `dd of=/dev/`, …). To
  bypass for a legitimate need, run the command outside the session or
  temporarily disable the hook — do not edit the deny-list for a
  one-off. OS-level sandboxing (`/sandbox`) and permission modes sit
  above this layer; prefer them for unattended runs.
- **PostToolUse** runs `ruff format` after every Edit/Write by default;
  `/review-check` and CI remain the hard gates. If bootstrap was run with
  `--strict-hooks`, this hook also runs `ruff check` + `mypy` after every
  edit. A second PostToolUse hook (`specs-status.sh`) regenerates the
  `## Status` dashboard in `docs/specs/README.md` whenever a spec file
  under `docs/specs/` is created or edited, so the struck-through/live
  status list stays current without a manual step. It only ever rewrites
  its own generated block; the spec `**Status:**` lines remain the source
  of truth.
- **PreCompact** injects a reminder to preserve the active spec path,
  branch, and modified-file list through compaction.
- **Stop** (`gate-on-stop.sh`, strict-hooks only) blocks ending a turn
  while `src/` has pending changes and ruff/mypy/pytest are red —
  `/review-check` made mechanical. Note: Claude Code overrides a Stop
  hook after 8 consecutive blocks, so the gate is a strong nudge, not an
  unbounded guarantee; `/goal` and a fresh verification subagent sit
  above it (see `WORKFLOW.md` → "The completion ladder").
- **pre-commit** blocks commits on `main` (`no-commit-to-branch`) and
  scans for secrets (`gitleaks`, `detect-private-key`). A `commit-msg`
  hook (`strip-ai-attribution.sh`) is the mechanical backstop for the
  no-AI-attribution rule in `.claude/rules/commit-style.md`: it strips
  any `Co-Authored-By: Claude` trailer or "Generated with Claude Code"
  footer from the message. `uv run pre-commit install` wires both hook
  types (`default_install_hook_types` in `.pre-commit-config.yaml`).
- **CI** (`.github/workflows/ci.yml`) runs the full gate on every PR —
  the non-skippable backstop. A second `audit` job runs `pip-audit`
  against the locked dependency tree, so a known CVE fails the PR;
  Dependabot (`.github/dependabot.yml`) opens the weekly update PRs that
  fix them. For an unfixable transitive advisory, ignore it explicitly
  with `pip-audit --ignore-vuln GHSA-...` and a comment.

## Beyond a single session

Parallel agents in git worktrees, agent teams, and unattended runs
(`/goal`, `/loop`, `/sandbox` — Claude Code built-ins, not commands in
`.claude/commands/` — and autonomous loops) are covered in
`docs/parallel-agents.md` when the full/advanced docs are installed. The
normal default remains tier 1: one attended session driving the loop;
parallelize only with partitioned file ownership.

## Don't-touch list

- `pyproject.toml` `[tool.uv]` section — ask first
- {{ADD_PROJECT_SPECIFIC_DONT_TOUCH — e.g., `src/{{PACKAGE_NAME}}/migrations/` if Alembic; vendored upstream files under `sources/`; generated artifacts under `out/`}}

## Open work / current state (updated {{YYYY-MM-DD}})

- {{WHAT_IS_IN_PROGRESS_OR_BLOCKED}}
- {{WHAT_THE_NEXT_SPEC_IS — e.g., "Spec for the next feature lives at `docs/specs/0001-<feature>.md`"}}
