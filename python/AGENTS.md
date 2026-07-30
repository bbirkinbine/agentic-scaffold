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

<!-- agentic-scaffold:standing-rules:start -->

## Standing rules

These rules are authoritative for every client. They live here once
rather than in duplicate client-specific policy files. Do not
hand-edit this marked block;
`bootstrap.sh --update` refreshes it while preserving content outside
the markers.

---


# Write code that agents (including you) can verify

This codebase is maintained primarily through agentic sessions. Code
that an agent can read, run, and check its own work against beats code
that is merely clever. When choosing between equivalent designs, prefer
the one a fresh session can verify without tribal knowledge.

- **Descriptive names over clever abstractions.** A function named for
  what it does is documentation that cannot drift. Avoid metaprogramming,
  dynamic dispatch tricks, and indirection layers that make "who calls
  this?" unanswerable by reading.
- **Simple control flow.** Early returns over nested conditionals;
  explicit branches over flag arguments threaded through call stacks.
- **Rich, observable output.** Log meaningful state transitions to
  stdout/structlog so a session can run the code and *see* what happened
  rather than inferring it. Example: a dev-mode email sender that prints
  the message to stdout lets an agent verify a sign-up flow end-to-end
  with no mailbox access.
- **Make failure loud and specific.** Error messages should name the
  input and the expectation that failed — they are the feedback channel
  the next session debugs through.
- **Harden tools against misuse.** Internal scripts and CLI helpers get
  argument validation and a `--help` that states intent; assume a future
  agent will call them with plausible-but-wrong arguments.
- **Plain interfaces over frameworks** where the choice is free: a
  function that takes data and returns data is verifiable in one pytest;
  a framework hook is verifiable only inside the framework.

---

# Code / commit style

- **No AI `Co-Authored-By` trailers** in
  commit messages. The top-level `README.md` already acknowledges AI
  tooling — that is the single source of attribution.
- **No generated-by-client footers** in commits or PR
  descriptions for the same reason.
- AI assistance is acknowledged **once**, at the top of `README.md`. Do
  not sprinkle AI-assist notices into individual files, commit
  messages, or comments.
- Match the existing log style: short imperative subject, body
  explaining the *why* when non-obvious. No conventional-commits
  prefixes (`feat:`, `fix:`, `chore:`) unless the existing log already
  uses them.
- Reference the spec under `docs/specs/` when applicable.
- Avoid emojis in repo files.
- Avoid the words *genuinely*, *straightforward*, *actually* in prose.
- Direct, technical tone.

## Mistakes feed back into the rules

When the human corrects a recurring agent mistake — a convention you
keep missing, a tool you keep misusing, a path you keep touching — the
fix is not just the correction in-session: add a line to `AGENTS.md` in
the same change, so the next
session doesn't repeat it. Standing instructions are the error log that
compounds; a correction that lives only in chat history is lost at
session reset.

---

# Git workflow

The standing rule: **every change happens on its own branch — never
write feature or fix code on `main`.** Create the branch yourself, as
soon as there is a spec or an issue to work. Do not wait to be asked;
branching is not an optional courtesy step.

## Branch naming

- Spec work (default local mode) → `spec-NNNN-<slug>`, e.g.
  `spec-0007-add-user-prefs`, where `NNNN` is the spec's number under
  `docs/specs/`. The spec number and the branch number are the same
  number; that shared id ties spec ↔ branch ↔ PR together, and the
  specs themselves are the cross-session persistence layer.
- Untracked tiny work with no spec — XS fixes, chores, hotfixes →
  `<type>/<slug>`, where `<type>` is one of `feat` `fix` `chore` `docs`
  `refactor`, e.g. `chore/bump-ruff`. Do not invent a fake spec
  number.
- Issue mode (opt-in — for team repos or when the backlog should live
  as GitHub issues; record the choice in `AGENTS.md`): anything past XS
  gets a GitHub issue first, the spec is numbered by the issue, and the
  branch is `<issue-number>-<slug>`, e.g. `42-add-user-prefs`. Create
  it with `gh issue develop <N> --name <N>-<slug> --checkout`, which
  links the branch to the issue in GitHub's UI (plain
  `git switch -c <N>-<slug>` works but loses that linkage). In this
  mode issues are the cross-session persistence layer and
  spec ↔ issue ↔ branch ↔ PR all share one id.
- Either mode: the number is an identifier, not an execution order —
  gaps in `docs/specs/` are expected (in issue mode, numbers are also
  consumed by bugs and questions), and specs ship in whatever order
  triage dictates. See `docs/specs/README.md` → "Numbering".

One branch per spec / unit of work.

## Before the Implement phase

Check `git branch --show-current`. If it returns `main` or `master`,
stop and create the branch first. Two guardrails back this up — the
`no-commit-to-branch` pre-commit hook blocks commits on `main`, and a
SessionStart hook warns when a session opens on `main` — but a guardrail
firing means the branch was created too late. Branch at the right time;
treat the guardrails as a backstop.

## Commits and pushes

Never commit or push on your own. Each commit needs an explicit
"commit" instruction from the human in the current conversation; never
push without being explicitly asked, and never use `--force` without a
direct ask. Workflow: make the change, show `git status` and
`git diff`, then wait.

## Pull requests

Open with `gh pr create --fill --web`. In issue mode, the PR body must
contain a closing keyword line — `Closes #<issue-number>` — so the
merge auto-closes the issue. Closing keywords work in the PR body, not in
feature-branch commit messages. In the default local mode, omit the
closing keyword. Run `/review` before opening the PR.

### Close-tasks ride in the PR they belong to

A change's own bookkeeping — flipping the spec's `**Status:**` to
`shipped`, regenerating the `docs/specs/README.md` dashboard, updating the
`AGENTS.md` "current state" block, ticking a todo/checklist item — belongs
**in the feature branch itself**, committed before the PR is opened (or
pushed to the same branch before it merges), so one merge completes the
work. `shipped` in an open PR means "ships when this PR merges" — that is
the intended reading, not a lie about current state.

**Do not open a separate follow-up PR after merge** just to mark the spec
shipped or do small post-merge cleanup — that is a wasted PR and a wasted
review. If such cleanup was missed and its feature PR is already merged,
fold it into the next PR that touches the same area rather than spawning a
standalone one; a standalone cleanup PR is justified only when it carries
real standing value on its own (e.g. it also changes a rule or doc that
outlives the cleanup).

---

# Secrets and public-repo hygiene

**Treat this repo as public from commit #1, even if it is currently (or
was recently) private.** Many of my repos start private and flip to
public after a feature lands. Rewriting history after that flip is
destructive — every commit SHA changes, existing clones break, and the
old state may already be archived by forks, GitHub's network view, or
anyone who cloned before the rewrite. The cheapest fix is to never
commit the thing in the first place.

The rules below apply across every public surface, not just file
contents:

- File contents and diffs
- Commit messages (subject + body) and tag annotations
- Branch names and tag names
- PR titles, descriptions, review comments
- Issue titles, bodies, comments; Discussions; wiki pages; release notes
- CI workflow logs (echoed env vars, full paths, stack traces are all
  public for public repos)
- Author + committer email on every commit — history is forever

**Never commit:**

- Live credentials of any kind — API tokens, passwords, private keys,
  signing keys, OAuth secrets, session cookies, JWTs. If one ever lands
  in a commit, **rotate it immediately**; assume any value that touched
  history is compromised the moment it lands.
- `.env*` files other than `.env.*.example` (which must contain no real
  values). Gitignore `.env.*` with an explicit `!.env.*.example`
  whitelist.
- Internal hostnames, IPs, subnets, internal URLs, VPN endpoints,
  private Slack/Discord links, IRC channels.
- Names of coworkers, managers, customers, or anyone else who hasn't
  opted in to having their name attached to this repo.
- Private-tracker identifiers — Linear/Jira/Asana ticket IDs, internal
  doc URLs, Notion share links.
- Employer references in commit messages, comments, or repo metadata.
- File paths that leak identity or employer.
- Personal info — home address, phone, personal email, ID numbers.

If the repo is currently private and a flip to public is on the table,
do a full pre-flip scrub before clicking "Change visibility." The flip
exposes all of history, not just the current working tree, so re-audit
every surface in the "never commit" list above across the whole repo:

- `git log -p` — secrets, internal hostnames, employer references, and
  real names hiding in old diffs and commit messages.
- `git log --format='%an <%ae>'` — author and committer identity on every
  commit must be the public GitHub identity, not a work address.
- Branch and tag names, PR/issue titles and bodies, and any CI logs.
- A secret sweep (`gitleaks detect`) and an `.env*` check — only
  `.env.*.example`, carrying no real values, should be tracked.

A hit means either rewriting history (destructive — every SHA changes,
and forks or caches may already hold the old state) or, better, not
flipping until it is clean. Catching it before the flip is the cheap
path.

## Secrets must not enter the context window either

A secret that never lands in a commit can still leak by being *read*:
anything a tool prints enters the conversation context, and transcripts
travel further than the repo (pasted into issues, shared session logs,
bug reports). Two layers keep secrets out of context:

- **Mechanical:** `.claude/settings.json` and the Codex permission profile
  in `.codex/config.toml` deny reads of `.env` / `.env.*` files and
  `*.pem` / `*.key` material anywhere in the tree. This intentionally also blocks
  `.env.*.example` — an example file is small; the human pastes its
  contents into chat on the rare occasion the agent needs to see one.
- **Behavioral (this rule):** a runtime override can weaken a client default.
  Do not route around it — no `cat .env`, `printenv`, `env`, sourcing
  env files, or echoing credential-bearing variables through Bash. If a
  command's output could contain a live credential, don't run it;
  describe what you need and let the human run it outside the session.

---


# Python code conventions

- **Files ≤ 300 lines.** Split aggressively; one concept per file. The
  `python-module-split` skill auto-invokes when a file approaches this.
- **Type hints required** on every function signature. `Any` requires a
  comment justifying it.
- **No bare `except:`**. Catch specific exceptions or `Exception` with a
  re-raise/log.
- **Docstrings:** Google-style. One-liner for trivial helpers; full
  args/returns/raises for public functions.
- **Imports:** absolute imports inside the package; relative only inside
  `__init__.py`.
- **Logging:** follow the project choice in `AGENTS.md` / `pyproject.toml`.
  `structlog` is a good default for services; stdlib `logging` is fine for
  small libraries and CLIs. Avoid `print` for non-CLI diagnostics.

## External-reference provenance (implement phase)

Any value or claim whose correctness depends on matching an external
authority — listed in the spec's `## External references` section — must
be populated by an in-session retrieval from the declared source URL,
with the retrieval date + license pinned in a header comment near where the value is
defined. Reconstructing such values from training is the fabrication
failure the spec template warns against — if the source isn't fetchable,
the spec's provenance is wrong; fix the spec, not the code.

Copyleft-licensed sources (GPL/AGPL/LGPL) are consult-only in a
permissive repo: do not copy their content verbatim and do not check the
project into `vendor/`. See `docs/specs/README.md` `## External
references` for the categories this covers and the license
compatibility rules.

<!-- agentic-scaffold:standing-rules:end -->
