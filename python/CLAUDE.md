# Project: {{PROJECT_NAME}}

{{ONE_PARAGRAPH_DESCRIPTION}}

This repo is **public** on GitHub (`github.com/bbirkinbine/{{PROJECT_NAME}}`)
or will become public after the first feature lands. Treat every change
as world-readable from commit #1. See the "Secrets and public-repo
hygiene" section below.

An `AGENTS.md` stub sits alongside this file as a portable pointer for
non-Claude agents (Codex, Cursor, Gemini, etc.) that look for that
filename by convention. `CLAUDE.md` is the source of truth; `AGENTS.md`
points back here.

## Stack

- Python 3.12 (managed by `uv`)
- {{ADD_PROJECT_SPECIFIC_LIBS — e.g., FastAPI / Pydantic v2 / SQLAlchemy 2.0 / httpx / lxml / structlog}}
- pytest + pytest-asyncio
- ruff (lint + format) + mypy (strict)

## How to run things

- Install: `uv sync`
- Run app: `uv run python -m {{PACKAGE_NAME}}.main` (or `uv run {{ENTRY_POINT}}`)
- Run tests: `uv run pytest`
- Lint: `uv run ruff check . && uv run ruff format --check .`
- Type-check: `uv run mypy src/`
- Single test: `uv run pytest path/to/test.py::test_name -xvs`

## Conventions

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
- **Logging:** `structlog`, not `print` or `logging` directly. Get a
  logger via `log = structlog.get_logger()`.

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
| "Who calls this?" / symbol nav on a *large* repo, with `serena` enabled | The `serena` MCP — query the index, don't grep-storm. See "Code navigation" |
| A change would touch > 5 files | Stop and ask the human first |

**Re-anchor on the spec.** `docs/specs/NNNN-*.md` is the source of truth
for *what* you are building. Re-read the active spec at the start of
each phase, and any time the conversation has drifted from it. If your
context is getting long mid-feature, that is the signal to stop at a
phase boundary and `/clear` — see `WORKFLOW.md` → "Phase handoff".

**Verify before you report.** `/review-check`, the Stop-gate hook, and
CI mechanically verify the *code* — but a claim the gate can't see ("the
scrub worked", "these two files are duplicates", "the service came back
up") is only true once you have proven it. Before you state an outcome,
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
| Large — refactor or new subsystem | Full loop; split into medium tasks; do not run it all in one session. |

## Workflow expectations (Spec → Plan → Test-first → Implement → Verify)

This is the agentic loop documented in
`Research/Programming/Agentic Programming/02 Agentic Methodology Loop.md`
in my Obsidian vault. The human-facing walkthrough with worked examples
lives in `WORKFLOW.md` at the repo root; a rendered diagram of the whole
machine — loop, guardrails, and subagent delegation — is in
`docs/workflow-diagram.md`. Honor each phase — don't run open-ended.

**Autodrive between checkpoints.** When handed a spec to implement (a
`docs/specs/NNNN-*.md` path, or `implement <feature>`), drive the loop
yourself end to end — branch, `/test-first`, implement to green,
`/review-check` — without waiting for a per-phase prompt. Stop and surface
output at exactly two human checkpoints: after `/plan` (before tests), and
after `/review-check` passes (before commit). Never commit on your own (see
Git workflow and Code / commit style). If `/test-first` or the gate shows
the spec is wrong, stop and raise it rather than coding around it. This
applies to Medium and Large tasks; Trivial and Small keep the scaled-down
loop above.

**Handling review findings.** `/review` and `/review-adversarial` tag each
Issue and Concern with an action: `[auto-fix]` (mechanical, one correct fix —
apply it yourself, then re-run `/review-check`), `[no-op]` (informational —
nothing to do), or `[ask-user]` (challenges a deliberate spec decision or
changes product behavior — a call that is the human's, not yours). During
autodrive, resolve `[auto-fix]` findings on your own and skip `[no-op]` ones,
but an `[ask-user]` finding is a hard stop: surface it to the human verbatim —
its locus and full description, not a paraphrase or a pre-judged answer — and
wait. Autodrive consent covers mechanical progress and `[auto-fix]` findings;
it does not extend to overriding the author's intent. The one exception is an
explicit instruction to drive the entire run unattended ("just ship it", "don't
check back"), which is standing consent to resolve `[ask-user]` findings too.

- **Spec.** Before any non-trivial work, write a short spec under
  `docs/specs/NNNN-<feature>.md` (see `docs/specs/README.md` for the
  numbering convention and required sections, including
  `## External references` for the provenance of any registries,
  protocol tables, or vendor constants the feature depends on). One
  paragraph minimum: goal, success criteria, non-goals.
- **Plan.** For tasks that touch > 3 files: use the `planner` subagent
  first. It reads the spec + relevant code and produces a markdown
  plan. Review the plan before any writes happen.
- **Test-first.** Tests come before implementation. Use the `test-first`
  subagent to write failing pytest tests from the spec. Show me the
  failing-test output. Only then proceed to implementation.
- **Implement.** You must already be on a feature branch — see
  **Git workflow** below; never implement on `main`. Main session
  writes the minimum code to make the tests pass. Any value or claim
  whose correctness depends on matching
  an external authority — listed in the spec's `## External references`
  section — must be populated by `WebFetch` in-session with the source
  URL + retrieval date + license pinned in a header comment near where
  the value is defined. Reconstructing such values from training is the
  fabrication failure the spec template warns against — if the source
  isn't fetchable, the spec's provenance is wrong; fix the spec, not
  the code. Copyleft-licensed sources (GPL/AGPL/LGPL) are consult-only
  in a permissive repo: do not copy their content verbatim and do not
  check the project into `vendor/`. See `docs/specs/README.md`
  `## External references` for the categories this covers and the
  license compatibility rules.
- **Verify.** Before invoking the `reviewer` subagent, run
  `/review-check` to confirm the local quality gate passes (ruff lint,
  ruff format, mypy, pytest). Then use the `reviewer` subagent on the
  diff. It has not seen the implementation reasoning and reads only the
  diff + spec. For meaningful features, also run `/review-adversarial`
  on the same diff and read both side-by-side. Add `/security` and/or
  `/performance` if the relevant opt-in subagent is installed and the
  diff trips its triggers.
- **Bug fixes — confirm the cause before the fix.** The loop above is
  feature-shaped; a bug fix has a different failure mode: wiring up a fix
  against a *guessed* cause. Reproduce the failure first, then have
  `/test-first` write a test that fails *for the reason you believe is the
  cause*. A reproducing test that fails for a different reason than your
  hypothesis means the diagnosis is wrong — fix the diagnosis, not the
  symptom. Don't commit until that test goes red → green. A fix committed
  on a hunch is the revert-and-history-rewrite cycle the public-repo
  hygiene section calls the expensive case.
- **Phase handoff on multi-day features.** If the loop spans more than
  one session, append a `## Phase handoff` section to the spec at each
  phase boundary (state + entry conditions for the next phase), then
  run `/clear` and resume in a fresh session. Main-session context past
  the U-curve degrades review quality; the handoff section is how the
  fresh session picks up without re-deriving context from the chat.
- If a change would touch > 5 files, stop and ask first.

## Git workflow

The standing rule: **every change happens on its own branch — never
write feature or fix code on `main`.** Create the branch yourself, as
soon as there is a spec or an issue to work. Do not wait to be asked;
branching is not an optional courtesy step.

**Branch naming:**

- Work tracked by a GitHub issue → `<issue-number>-<slug>`, e.g.
  `42-add-user-prefs`. Create it with
  `gh issue develop <N> --name <N>-<slug> --checkout`, which links the
  branch to the issue in GitHub's UI. Plain `git switch -c <N>-<slug>`
  also works but loses that linkage.
- Untracked tiny work with no issue — XS fixes, chores, hotfixes →
  `<type>/<slug>`, where `<type>` is one of `feat` `fix` `chore` `docs`
  `refactor`, e.g. `chore/bump-ruff`. Do not invent a fake issue
  number.
- Anything past XS should get a GitHub issue first — issues are the
  cross-session persistence layer. The spec number, the issue number,
  and the branch number are the same number; that shared id ties
  spec ↔ issue ↔ branch ↔ PR together.

One branch per spec / unit of work.

**Before the Implement phase**, check `git branch --show-current`. If it
returns `main` or `master`, stop and create the branch first. Two
guardrails back this up — the `no-commit-to-branch` pre-commit hook
blocks commits on `main`, and a SessionStart hook warns when a session
opens on `main` — but a guardrail firing means the branch was created
too late. Branch at the right time; treat the guardrails as a backstop.

**Pull requests.** Open with `gh pr create --fill --web`. The PR body
must contain a closing keyword line — `Closes #<issue-number>` — so the
merge auto-closes the issue. Closing keywords work in the PR body, not
in feature-branch commit messages. Run `/review` before opening the PR.

Commit *message* style is unchanged — see "Code / commit style" below.
This section governs branches and PRs only.

## Code navigation (optional: `serena` MCP)

Default to the built-in tools — `grep` / `glob` / `read`, with a subagent
for wide surveys. For a single-language repo that fits in a context
window that is enough: an index layer buys clarity, not token savings,
and adds a moving part. **Do not enable `serena` on a fresh or small
repo** — the payoff scales with corpus size and how often you re-query.

Enable the `serena` MCP only once a repo is **large or long-lived** —
when the agent burns most of its turns re-reading files to rebuild the
same structural map every session. `serena` is LSP / symbol-level, so
there is no stale graph file to maintain (it resolves symbols live), and
it exposes find-symbol / find-referencing-symbols / "who calls this?"
over MCP. When enabled, prefer a `serena` symbol query over a repo-wide
grep for navigation — see the delegation table in "Your role:
orchestrator."

Setup, verification (new or existing), update/pin, and teardown:
[`docs/serena-setup.md`](docs/serena-setup.md). Rationale and tool
comparison: `Research/Programming/Code Graphs for Coding Agents — Cheat
Sheet.md` in my Obsidian vault.

## Subagents (in `.claude/agents/`)

- `planner` — read-only; produces a plan in markdown.
- `test-first` — writes failing pytest tests from a spec; never writes
  implementation.
- `reviewer` — independent diff reviewer; checks spec match, test
  quality, edge cases, file size, public-repo hygiene.
- `reviewer-adversarial` — independent diff reviewer with adversarial
  framing; argues against the change rather than for it. Use alongside
  `reviewer` on meaningful features for A/B comparison. Same section
  structure as `reviewer` so both can be read side-by-side.

Opt-in subagents (copy from
`~/Downloads/src/agentic-scaffold/python/.claude/agents/optional/`
into `.claude/agents/` per project):

- `security-reviewer` — application-security review of a diff. Enable
  when the project has a network surface, auth, processes untrusted
  input, handles secrets, or deserializes external data.
- `performance-reviewer` — performance review of a diff (N+1, accidental
  O(n²), sync I/O in async, missing pagination, allocation churn,
  migration-locking patterns). Enable when the project has a hot path,
  DB queries on user-sized data, or runs under load.

## Skills (in `.claude/skills/`)

- `python-module-split` — auto-invoked when a `.py` file approaches 300
  lines. Splits a module into a package while preserving the public API.
- `python-docstrings` — auto-invoked when a new public function, class,
  or module is added or touched. Enforces Google-style docstrings; bans
  tautological docs and missing `Raises:` sections.
- `dependency-hygiene` — auto-invoked when a new entry is added to
  `[project] dependencies` or `[tool.uv] dev-dependencies` in
  `pyproject.toml`. Flags abandoned packages, single-maintainer risk,
  license conflicts, stdlib alternatives, and advisories before the
  dep is added.

## Slash commands (in `.claude/commands/`)

One-keystroke entry points to the workflow loop. The commands invoke
the subagents and quality gate so the methodology is muscle memory
instead of manual invocation.

- `/scope-check <feature description>` — optional pre-spec phase. Five
  forcing questions to clarify goal and scope on ambiguous features.
  Output feeds the spec's `## Goal` and `## Non-goals` sections. Skip
  on features where the goal is already concrete.
- `/spec <feature name>` — creates `docs/specs/NNNN-<slug>.md` with
  status header + goal / success / non-goals scaffolding; stops there
  for human edit.
- `/specs-status [filter]` — prints the status table for every spec
  under `docs/specs/` (draft / shipping / shipped / paused / abandoned).
  Read-only aggregator over the `**Status:**` field in each spec.
- `/plan [spec-path]` — invokes the `planner` subagent on the named
  spec, or the most recent one if blank.
- `/test-first [spec-path]` — invokes the `test-first` subagent.
- `/review [<base>..<head>]` — invokes the `reviewer` subagent on the
  current diff (or the named range).
- `/review-adversarial [<base>..<head>]` — invokes the
  `reviewer-adversarial` subagent on the same diff. Pair with `/review`
  on meaningful features for A/B comparison; same output schema.
- `/security [<base>..<head>]` — invokes `security-reviewer` if
  installed; otherwise tells you how to enable it.
- `/performance [<base>..<head>]` — invokes `performance-reviewer` if
  installed; otherwise tells you how to enable it.
- `/review-check` — runs the local quality gate (ruff lint, ruff
  format, mypy, pytest) and refuses to declare the gate passed on any
  failure. Run before `/review`. Does not mean "feature done" — only
  "local checks pass."

## Hooks

`.claude/settings.json` runs `ruff format`, `ruff check`, and `mypy`
after every `Edit`/`Write` via a PostToolUse hook. Fix lint/type errors
immediately rather than declaring victory with a broken build.

A `Stop` hook (`.claude/hooks/gate-on-stop.sh`) fires when the session
tries to finish a turn. If `src/` has pending changes and `ruff`/`mypy`/
`pytest` don't all pass, it returns `decision: block` so the session cannot
declare done on a red gate — the `/review-check` discipline made automatic.
Two guards keep it quiet: it does nothing when `src/` has no pending
changes, and it steps aside (with a warning) if a gate genuinely can't pass
rather than looping. It backstops the case where you forget to run
`/review-check`; it does not replace `/review`.

A PreToolUse hook (`.claude/hooks/block-destructive.sh`) runs before
every `Bash` call and blocks catastrophic / unrecoverable commands —
`rm -rf /` (and `~`, `$HOME`, `*`), `git clean -fd`, `git filter-repo`,
`mkfs.* /dev/...`, `dd of=/dev/...`, `terraform destroy`,
`gh repo delete`, `DROP TABLE` on a DB client, `chmod 777 /`,
`shutdown`, forkbombs, and a few more. The line it draws is
*unrecoverable*: things the reflog, a re-clone, or `git revert` can't
bring back. Deliberately **not** on the list are operations that are
recoverable or already policy-gated — `git push --force` (gated by the
explicit-approval rule above) and `git reset --hard` (recoverable via
the reflog) are covered by policy, not by this mechanical backstop, so
the deny-list stays narrow and false-positive-free. To bypass for a
legitimate need, run the command outside the agent session or
temporarily disable the hook in `.claude/settings.json`; do not
silently edit the deny-list to allow a one-off.

A SessionStart hook (`.claude/hooks/branch-check.sh`) warns when a
session opens on `main`/`master` — your cue to branch before
implementing. The `no-commit-to-branch` hook in
`.pre-commit-config.yaml` mechanically blocks `git commit` on
`main`/`master`; the one expected exception is the day-zero scaffolding
commit (`git commit --no-verify`). `.pre-commit-config.yaml` also runs
secret scanning (`gitleaks`, `detect-private-key`) — the "never commit
credentials" rule made mechanical rather than left to vigilance.

The full local gate (lint + format + types + tests) is gated behind the
explicit `/review-check` slash command, not the auto-hook — tests are
too slow to run on every edit but they're non-optional before invoking
`/review`.

CI (`.github/workflows/ci.yml`) runs the full gate — ruff, mypy,
pytest — on every pull request. It is the non-skippable backstop: local
hooks and `/review-check` can be bypassed, CI cannot. A red CI check
means the PR is not mergeable.

## Don't-touch list

- `pyproject.toml` `[tool.uv]` section — ask first
- {{ADD_PROJECT_SPECIFIC_DONT_TOUCH — e.g., `src/{{PACKAGE_NAME}}/migrations/` if Alembic; vendored upstream files under `sources/`; generated artifacts under `out/`}}

## Code / commit style

- **No `Co-Authored-By: Claude` (or any AI co-author) trailers** in
  commit messages. The top-level `README.md` already acknowledges AI
  tooling — that is the single source of attribution. This overrides
  Claude Code's default behavior.
- **No "Generated with Claude Code" footers** in commits or PR
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

## Secrets and public-repo hygiene

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
walk the pre-flip checklist in
`~/Downloads/src/agentic-scaffold/new-project-checklist.md` before
clicking "Change visibility."

## Open work / current state (updated {{YYYY-MM-DD}})

- {{WHAT_IS_IN_PROGRESS_OR_BLOCKED}}
- {{WHAT_THE_NEXT_SPEC_IS — e.g., "Spec for the next feature lives at `docs/specs/0001-<feature>.md`"}}
