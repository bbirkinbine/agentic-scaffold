# Workflow — how to use this scaffolding

Companion to `CLAUDE.md`. `CLAUDE.md` is what the agent reads every turn
(the rules); this file is the human's step-by-step — what to run, in
order, with a one-line reason for each step.

The whole thing is five phases: **Spec → Plan → Test-first → Implement →
Verify.** Each slash command runs one phase and stops, so you stay in
control. New to the terms? A *spec* is a short design note; a *subagent*
is a fresh agent with its own clean context.

## Day zero (once per project)

1. **Run bootstrap.** `bash path/to/agentic-scaffold/python/bootstrap.sh`
   (wherever you cloned this repo) — drops the default `--python-core`
   scaffolding into your repo. Use `--minimal` for a thinner starter,
   `--full` for the author's full workflow bundle, and `--strict-hooks`
   only if you want edit hooks to run lint/type checks and the Stop gate.
2. **Fill the placeholders.** `rg '\{\{' .`, then replace every `{{...}}`
   — the agent reads `CLAUDE.md` every turn, so a leftover placeholder
   misleads it. One placeholder is the starter package directory
   `src/{{PACKAGE_NAME}}/` — rename it to your package name. Hand-edit the
   `CLAUDE.md` content yourself (description, don't-touch list,
   conventions); don't have the agent regenerate it — AI-written context
   files measurably hurt agent performance (see `python/README.md` →
   "Don't"). Mechanical fills like the project name in `pyproject.toml`
   are fine to delegate.
3. **Set up git identity and GitHub.** `git config user.email` must be
   your GitHub noreply address — it is baked into the first commit
   forever. Then add the README AI-acknowledgement line and fill the
   GitHub "About" sidebar. (A fuller checklist, including the
   private→public hygiene scrub, lives in the agentic-scaffold repo as
   `new-project-checklist.md` — it is not copied into your project.)
4. **Decide opt-in reviewers now.** Security and performance reviewers
   are off by default; turn them on if the project needs them (see
   `python/README.md` → "Opt-in subagents").
5. **Install the dev tools.** `uv sync && uv run pre-commit install` —
   dependencies plus the commit guard that keeps work off `main`.
6. **Create the GitHub issue labels** the issue forms use: `feature`,
   `bug`, `spec-needed`, `triage` (e.g. `gh label create spec-needed`).
   Skip this in local-only mode; specs then use the next local number
   instead of a GitHub issue number.
7. **Optional — `/product-spec` if installed.** Interviews you and writes
   `docs/specs/0000-product.md`, the product-level "what is this, and who
   is it for." Skip it for a small project.

## Every feature (the loop)

Run these in order. Steps marked *optional* are skippable when the answer
is already obvious.

1. **Create a GitHub issue** unless the repo is explicitly local-only.
   An issue is a work item — like a Jira or Linear ticket, not just a bug
   report (`feature` is one of its labels). Its number names the spec,
   the branch, and the PR — one id ties them together. In local-only mode,
   `/spec` uses the next local `docs/specs/NNNN-*.md` number instead.
2. **`/spec <name>`** — write a short spec: goal, success criteria,
   non-goals. This is the source of truth every later step checks
   against.
   - *Optional, if installed:* `/scope-check` before (fuzzy goal),
     `/clarify` after (open questions) to sharpen it.
3. **Make a branch** named `<issue#>-<slug>` in GitHub-backed mode, or
   `spec-NNNN-<slug>` / `<type>/<slug>` in local-only mode. Never build on
   `main`.
4. **`/plan`** — the agent lists the files to touch and the order.
   Review it before any code; a wrong approach is cheap to fix here.
5. **`/test-first`** — writes failing tests from the spec. Tests written
   *after* the code just rubber-stamp whatever you built.
   - *Optional, if installed:* `/analyze` confirms every success criterion has a test.
6. **Implement.** Write the minimum code to make the tests pass.
7. **`/review-check`** — runs ruff + mypy + pytest. Must be green before
   moving on.
8. **`/review`** (and `/review-adversarial` on bigger changes, if
   installed) — a fresh agent reads the diff against the spec, catching
   what the gate can't.
   - *Optional:* `/security` and `/performance` if you installed them.
   - *LLM/AI-surface projects only, if installed:* `/eval` runs the eval
     suite — the quality gate for non-deterministic output that
     `/review-check` can't assert. Most projects ship no LLM surface and
     skip this entirely; install the full/advanced docs for the detailed
     decision rule.
9. **Commit, then open the PR.** You write the commit message. In
   GitHub-backed mode, the PR body says `Closes #<issue>` so merging
   closes the issue; local-only mode omits the closing keyword.

## Scale to the task

Don't run the full loop on tiny work.

| Task | Do |
| --- | --- |
| Trivial — rename, typo, ≤10 lines | Just do it. Skip spec/plan; branch optional. |
| Small — one function | Branch + one-sentence spec; `/test-first`; skip `/plan`. |
| Medium — 3–10 files | The full loop above. |
| Large — new subsystem | Capture the cross-cutting technical decision in an ADR (`/adr`) first, then split into medium pieces, one issue + spec each. |

A throwaway script needs none of this — just write the code.

## Phase handoff (multi-day features)

A feature that spans sessions reviews badly when one session carries all
the spec, plan, test, and implementation context. At a phase boundary,
append a `## Phase handoff` block to the spec, run `/clear`, and resume
fresh. Boundaries worth a reset: after `/plan` is approved, and after
`/review-check` is green. Section shape: `docs/specs/README.md`.

## The completion ladder

"The agent said done, but it wasn't" has layered fixes — use more the
longer nobody is watching:

1. Success criteria written as a runnable command.
2. `/goal` — a completion check run by a separate evaluator.
3. The Stop hook, if `--strict-hooks` is enabled — blocks ending a turn on a red gate.
4. A fresh-context `/review` — the only rung that catches "gate green but
   feature wrong."

Detail and the autonomy tiers: `docs/parallel-agents.md`. (`/goal`,
`/loop`, and `/sandbox` are Claude Code built-ins, not commands in
`.claude/commands/`.)

## Good to know

- **`CLAUDE.md` is re-read every turn** — edit it mid-feature to
  course-correct (e.g. add a path to the don't-touch list).
- **Subagents don't see your chat.** Put anything the reviewer needs in
  the spec, not in a message.
- **Specs are permanent** — they are the design log, not deleted after a
  feature ships.
- **CI is the gate you can't skip.** Local hooks can be bypassed; a red
  PR is not done.

## Going deeper

Some files below depend on the bootstrap profile. `--minimal` installs the
core loop; `--python-core` adds ADR/status/workflow docs; `--full` or
`--advanced-docs` adds the advanced doctrine docs.

- `docs/workflow-diagram.md` — the same loop as a visual map.
- `docs/specs/README.md` — spec numbering, local-only mode, the product spec, section shapes.
- `docs/adr/README.md` — architecture decision records: when a choice is
  cross-cutting and costly to reverse, log the decision and its rationale
  (spec-vs-ADR table, numbering, template). Mostly for Large work.
- `docs/evals.md` — what "eval" means (two senses): the review/analyze
  work you already do for any project, plus the opt-in product-eval layer
  for a product that contains an LLM/AI surface.
- `docs/parallel-agents.md` — autonomy tiers, worktrees, unattended runs.
- `docs/agent-handoff.md` — operational runbook: risks, rollback, "when X breaks."
- `CLAUDE.md` + `.claude/rules/` — the rules the agent follows every turn.
