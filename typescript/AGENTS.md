# Project: {{PROJECT_NAME}}

{{ONE_PARAGRAPH_DESCRIPTION}}

Treat this repo (`github.com/bbirkinbine/{{PROJECT_NAME}}`) as **public**
from commit #1, whether or not it is yet: a private repo can flip to public
later, and its whole history flips with it.

`AGENTS.md` is the single client-neutral project contract. `CLAUDE.md` is a
Claude Code import containing only `@AGENTS.md`. In a bootstrapped project,
edit `AGENTS.md`, not the import. In the scaffold, edit `workflow/` sources
and render the client surfaces.

Some referenced workflows and docs require `--core` or `--full`; use
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

- TypeScript 7 on Node 24 LTS (pinned in `.nvmrc` and `package.json` → `engines`)
- {{ADD_PROJECT_SPECIFIC_LIBS — e.g., Hono / Fastify / Zod / Drizzle / logging choice}}
- Vitest
- Biome (lint + format) + `tsc --noEmit` (strict, `noUncheckedIndexedAccess`)

## How to run things

`.agentic/toolchain.sh` is the one place the gate's tools are named; the
hooks, `/review-check`, and CI call its subcommands. Use them too, so a
tool swap changes one file.

- Install: `.agentic/toolchain.sh install` (`npm ci`, or `npm install` before a lockfile exists)
- Run app: `node --experimental-strip-types src/index.ts` (or `npm run start` once defined)
- Run tests: `.agentic/toolchain.sh test` (`vitest run`)
- Single test: `.agentic/toolchain.sh test tests/index.test.ts` (or `-t "test name"`)
- Lint / format / type-check: `.agentic/toolchain.sh lint | format | typecheck`
  (biome lint, biome format, tsc on the whole project)
- The whole gate: `.agentic/toolchain.sh gate`

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

- `package.json` `engines` and the committed `package-lock.json` — ask first
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
  stdout or the project logger so a session can run the code and *see* what happened
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
  function that takes data and returns data is verifiable in one test;
  a framework hook is verifiable only inside the framework.

---

# Code / commit style

- No AI `Co-Authored-By`, generated-by-client, or other AI-attribution text in
  files, comments, commits, or PRs; the top-level README is the sole notice.
- Match the log: short imperative subject and a why-focused body when needed.
  Do not introduce conventional-commit prefixes unless the log uses them.
- Reference the spec under `docs/specs/` when applicable.
- Avoid emojis in repo files.
- Avoid the words *genuinely*, *straightforward*, *actually* in prose.
- Direct, technical tone.

## Mistakes feed back into the rules

Encode a human correction to a recurring agent mistake in `AGENTS.md` in the
same change. Review findings count: when `/review` or `/review-adversarial`
raises the same finding on a second feature, add the missing rule while fixing
it. One occurrence is a mistake; two indicate a missing rule. State the rule
as the correct action ("call the v2 client"), not only the prohibition
("don't call the v1 API"); a ban alone leaves the agent guessing what to do
instead.

---

# External-reference provenance (implement phase)

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

---

# Git workflow

**Every change gets its own branch; never edit feature or fix code on `main`.**
Create it as soon as a spec or issue exists, without waiting to be asked.

## Branch naming

- Local spec mode: `spec-NNNN-<slug>`, where `NNNN` is the spec number.
- XS work without a spec: `<type>/<slug>`, where type is `feat`, `fix`,
  `chore`, `docs`, or `refactor`; never invent a spec number.
- Opt-in issue mode (record it in `AGENTS.md`): work beyond XS gets an issue,
  matching spec number, and `<issue-number>-<slug>` branch. Prefer
  `gh issue develop <N> --name <N>-<slug> --checkout` to preserve GitHub
  linkage.
- In either mode, the shared number links the work item, branch, and PR. It is
  an identity, not execution order; gaps are expected. See
  `docs/specs/README.md` → "Numbering".

One branch per spec / unit of work.

## Before the Implement phase

Run `git branch --show-current`; on `main` or `master`, stop and branch. The
SessionStart warning and `no-commit-to-branch` hook are only backstops.

## Commits and pushes

Never commit or push autonomously. Each commit needs an explicit current-chat
instruction; pushing and `--force` each require a direct ask. Make the change,
show `git status` and `git diff`, then wait.

## Pull requests

Run `/review`, then open with `gh pr create --fill --web`. In issue mode, put
`Closes #<issue-number>` in the PR body; omit it in local mode.

### Close-tasks ride in the PR they belong to

Finish bookkeeping on the feature branch before opening or merging its PR:
mark the spec `shipped`, regenerate `docs/specs/README.md`, update the
`AGENTS.md` current-state block, and tick related items. In an open PR,
`shipped` means "ships when merged."

Run `.agentic/hooks/closeout-check.sh` before opening the PR. CI rejects
numbered feature branches whose spec remains `draft`/`shipping` or dashboard
is stale; it does not verify the current-state prose.

Do not open a cleanup-only PR after merge. Fold missed bookkeeping into the
next related PR unless the cleanup adds independent standing value.

---

# Secrets and public-repo hygiene

Treat the repository as public from commit #1, even while private. These rules
cover files and diffs; commits and tags; branch names; PRs and reviews; issues,
Discussions, wikis, and releases; CI logs; and author/committer identities.
Commit identities must use the public GitHub identity, never a work address.

**Never commit:**

- Credentials: tokens, passwords, private/signing keys, OAuth secrets,
  cookies, or JWTs. Rotate immediately if committed; assume compromise.
- `.env*` except value-free `.env.*.example`; ignore `.env.*` and explicitly
  allow only the examples.
- Internal hostnames, IPs, subnets, or URLs; VPN endpoints; private chat links.
- Non-consenting coworker, manager, or customer names.
- Private tracker IDs or internal document links.
- Employer references, identity-leaking paths, or personal information.
- Unscrubbed tool output. Build, test, and tool logs print absolute paths, so
  they carry the local username and directory layout; commit a summary or
  scrub first (`git grep -nE '/(Users|home)/'` finds them).

Before making a private repo public, audit its entire history and all surfaces:

- Inspect `git log -p` and `git log --format='%an <%ae>'`.
- Inspect branches, tags, PRs, issues, and CI logs.
- Run `gitleaks detect`; confirm only value-free `.env.*.example` files are
  tracked.

Do not change visibility until clean. History rewrites change every SHA and
cannot retract copies already held by forks, caches, or clones.

## Secrets must not enter the context window either

Tool output enters the transcript. Client policy denies `.env`/`.env.*`,
`*.pem`, and `*.key` reads anywhere in the tree, including example env files.
Never bypass it with `cat`, `env`, `printenv`, sourcing, or echoing credential
variables. The human can paste a value-free example file when needed. If
output could expose a credential, ask the human to run the command outside
the session.

---


# TypeScript code conventions

- **Files ≤ 300 lines.** Split aggressively; one concept per file.
- **ESM only.** `import`/`export`; no `require`. Named exports; a default
  export only where a framework demands one.
- **Explicit return types on exported functions.** Inferred types are fine
  inside a module; the public surface states its contract.
- **No `any` and no `!` non-null assertion without a comment** on the same
  line saying why the type system cannot express it. Prefer `unknown` plus a
  narrowing check.
- **Handle `noUncheckedIndexedAccess`.** Index reads are `T | undefined`;
  narrow them, do not assert them away.
- **Errors carry the input and the expectation.** Throw `Error` subclasses
  with a message that names what was received and what was required; never
  throw strings.
- **Async:** every promise is awaited or explicitly `void`ed with a comment;
  Biome's floating-promise rule is the backstop, `tsc` is not.
- **Logging:** follow the project choice in `AGENTS.md`. `console.log` only
  in CLIs; a structured logger for services.

## Test-first

- Runner: Vitest, through `.agentic/toolchain.sh test [target]`; a focused
  target is a test file path, or `-t "<test name>"`.
- Shared fixtures live in `tests/helpers/` and in `setupFiles` named by
  `vitest.config.ts`; the test-first phase may edit those and `tests/`,
  nothing else.
- An expected red is `TypeError: ... is not a function` or a `ReferenceError`
  for the missing export (Vitest transpiles without type checking, so a
  missing export arrives as `undefined`), a not-implemented stub throwing,
  or a behavior-level `expect` failure. `tsc --noEmit` failing on the same
  missing export is also expected at this phase. A syntax error in the test
  file, a failed import of the test file itself, or a setup-file error is
  not a red; it is a broken test.

<!-- agentic-scaffold:standing-rules:end -->
