# AGENTS.md — agentic-scaffold

> **Purpose.** Persistent project context for Claude Code, Codex CLI, and
> other AI coding agents working in this repository. `CLAUDE.md` is the
> one-line `@AGENTS.md` import; edit this file. Read this before suggesting
> changes. `README.md` is for humans landing on the GitHub page; this file
> is for the agent that opens the repo and starts working.

---

## What this repo is

Project-bootstrap templates and agentic-workflow scaffolding for new
repos — a stack-neutral dual-client bootstrap under `generic/`, generic
contract/README templates, the new-project checklist, the GitHub About
checklist, and the full agentic-workflow scaffolding (subagents, workflows,
skills, hooks, bootstrap) authored once under `workflow/` and rendered per
stack from `stacks/<name>/` into `python/`, `typescript/`, and `custom/`.
This content moved here from `templates/` in the
`github.com/bbirkinbine/dotfiles` repo on 2026-06-09; pre-move history
is in that repo's log.

Where the ideas came from — borrowed features, the research behind specific
rules, and what was considered and rejected — is recorded in
[`docs/influences.md`](docs/influences.md). It applies the scaffold's own
external-reference provenance rule to the scaffold's own design; when a
change here is prompted by an outside source, credit it there in the same
commit rather than only in the commit message.

This repo is **public** on GitHub (`github.com/bbirkinbine/agentic-scaffold`).
Treat every change as world-readable: file contents, commit messages,
branch names, PR descriptions, and issue text are all indexed by search
engines. No secrets, no internal hostnames, no work-related context.

---

## Stack / scope

Markdown templates plus bash (the generic bootstrap, the shared stack
bootstrap body `scripts/bootstrap-stack.sh`, client-neutral hook sources
under `shared/hooks/` and `workflow/hooks/`, one gate runner per stack under
`stacks/<name>/toolchain.sh`, and validation under `scripts/`). No build or
deploy target — files here are consumed by copy into new repos, and smoke
tests validate those generated projects.

The language axis is deliberate: the workflow layer never names a tool.
Every gate consumer (Stop hook, edit hook, `/review-check`, consumer CI,
smoke tests) calls `.agentic/toolchain.sh` subcommands, and each stack
supplies that runner plus its manifest, tool configs, starter layout,
conventions rule, and skills. Adding a language means adding
`stacks/<name>/`, not touching `workflow/`. `stacks/custom/` is the stack
for a language with no adapter: the same loop, with the runner shipped as a
project-owned template that keeps every gate quiet until the project fills
and activates it.

**Everything in this repo is standards-setting.** A change here
propagates (by copy, via `bootstrap.sh` or the checklist) to every new
repo created from this machine, and `bootstrap.sh --update` pushes
MANAGED-file changes into existing projects. Edit deliberately and
explain the rationale in the commit message; don't tweak template
language casually.

**Out of scope:** actual dotfiles (those live in
`github.com/bbirkinbine/dotfiles`), machine-specific config, anything
that wouldn't be safe on the open internet.

`{{PLACEHOLDER}}` markers in `*.template` files are intentional — they
are filled in by the consumer, not here.

---

## Code / commit style

- **No `Co-Authored-By: Claude` (or any AI co-author) trailers** in commit
  messages. The top-level `README.md` already acknowledges AI tooling —
  that is the single source of attribution. This overrides Claude Code's
  default behavior.
- **No "Generated with Claude Code" footers** in commits or PR
  descriptions for the same reason.
- AI assistance is acknowledged **once**, at the top of `README.md`. Do
  not sprinkle AI-assist notices into individual files, commit messages,
  or comments.
- Match the existing log style: short imperative subject, body explaining
  the *why* when non-obvious. No conventional-commits prefixes
  (`feat:`, `fix:`, `chore:`) unless the existing log already uses them.
- Avoid emojis in repo files.
- Avoid the words *genuinely*, *straightforward*, *actually* in prose.
- Direct, technical tone.

---

## Commits and pushes require explicit approval

Don't run `git commit` or `git push` without an explicit "commit" or
"push" instruction from the user in this conversation. The workflow is:
make the change, show `git status` and `git diff`, then wait. Each
commit needs its own sign-off. Never push without being explicitly
asked, and never use `--force` without a direct ask.

---

## Close-tasks ride in the PR they belong to

Before opening or merging a PR, include every status and bookkeeping change
caused by its implementation: update the `AGENTS.md` open-work/current-state
section, spec status and dashboards, affected docs, and related TODO or
checklist entries. Review the implementation and its close-tasks together.
Do not open a follow-up PR only to record that the previous PR shipped; fold a
missed item into the next related PR unless it has independent standing value.

---

## Secrets and public-repo hygiene

**Treat this repo as public from commit #1.** Rewriting history after a
leak is destructive and incomplete — the cheapest fix is to never commit
the thing in the first place. The full rules (what never to commit,
what quietly slips through, the pre-flip checklist) live in
[`new-project-checklist.md`](new-project-checklist.md) and in the
hygiene section of [`AGENTS.md.template`](AGENTS.md.template); both
apply to this repo itself, not just to repos bootstrapped from it.

---

## Validation gates before claiming done

```bash
bash scripts/render-client-surfaces.sh   # after any change under workflow/, shared/, or stacks/
bash -n scripts/*.sh generic/bootstrap.sh shared/hooks/*.sh workflow/hooks/*.sh stacks/*/toolchain.sh stacks/*/stack.sh
shellcheck --severity=warning scripts/*.sh generic/bootstrap.sh shared/hooks/*.sh workflow/hooks/*.sh stacks/*/toolchain.sh stacks/*/stack.sh python/bootstrap.sh typescript/bootstrap.sh custom/bootstrap.sh
bash scripts/validate-codex-adapters.sh
bash scripts/smoke-test-generic.sh
bash scripts/smoke-test.sh <minimal|core|full> [--strict-hooks|--no-stop-gate]
bash scripts/smoke-test-typescript.sh [--strict-hooks|--no-stop-gate]
bash scripts/smoke-test-custom.sh
```

`scripts/smoke-test.sh` bootstraps a Python profile into a temp dir,
asserts the installed file set, fills the day-zero placeholders, runs the
fresh project's gate through the toolchain runner, and proves the gate goes
red on a defect with the failing step named. `scripts/smoke-test-typescript.sh`
does the same for the TypeScript flavor and also exercises the Stop hook's
block decision. `scripts/smoke-test-custom.sh` proves the custom flavor's
unfilled runner keeps the gates quiet, fills it with a small shell
toolchain, proves the gate and Stop hook then work, and proves `--update`
leaves the project-owned runner, CI workflow, and Dependabot config alone.
It also exercises generic-to-custom migration and ensures broken active
runners fail CI, edit/Stop hooks, and the custom pre-commit entries.
`scripts/smoke-test-generic.sh` covers the stack-neutral flavor, including
the branch warning on a repository with no commits. CI
(`.github/workflows/ci.yml`) runs the shell checks plus every
flavor/profile smoke test on each push and PR — a red run means the
template would ship broken projects. The TypeScript smoke test needs `node`
and `npm` and network access for the first install.

`{{PLACEHOLDER}}` markers throughout the repo (in template contracts
and in `python/AGENTS.md` / `python/pyproject.toml`) are intentional —
they are filled by the consumer, never here, so there is no
placeholder check on this repo itself.

Don't claim a change is "ready" without at least:

1. A clean run of the checks above for the affected file(s).
2. An updated `README.md` (this repo's, `stacks/<name>/README.md`, or both)
   if the change adds/removes files or changes how the scaffolding is used.

---

## Don't touch

- `.git/` — obviously.
- `LICENSE` — MIT, created with the repo.

---

## Generated surfaces: edit the source, then re-render

`workflow/` (the loop: contract, commands, roles, rules, workflow hooks,
client config, docs), `shared/` (safety hooks, Codex policy), and
`stacks/<name>/` (one toolchain: runner, manifest, tool configs, starter,
conventions rule, skills) are the sources of truth. `python/`,
`typescript/`, and `custom/` are generated whole by `scripts/render-client-surfaces.sh`,
which replaces each flavor directory on every run — a file added straight
to a flavor directory disappears on the next render. The stack's `AGENTS.md`
is the workflow contract with `contract-stack.md` and
`contract-dont-touch.md` spliced in at the markers. This file is authored
directly and is not rendered.

---

## How consumers use this repo

A Claude Code or Codex session is pointed at the latest checkout, chooses
the stack from the project description using the rubric in
`workflow/docs/project-types.md` (section 1), installs the scaffold into
the new repo, and pre-fills the templates from the founding conversation.
The prompt that starts that session is in the top-level `README.md` and
`new-project-checklist.md`; keep the two copies identical. Consumer projects are snapshots: `bootstrap.sh
--update` is rarely run, so a change here reaches projects at their next
bootstrap, not retroactively. The methodology behind the scaffold is kept in
personal notes outside this repo.

---

## Current state (updated 2026-09-30)

The scaffold is dual-client (Claude Code and Codex CLI) since 2026-08-11 and
validated in day-to-day use across multiple real projects, both flavors.
Corrections feed back here as they surface. History lives in `git log`;
each squash-merge body explains its change. Borrowed ideas, the sources
behind specific rules, and decisions already considered and rejected are in
`docs/influences.md` — check it before proposing a change prompted by an
outside source, since several (contract length, a post-red test-tamper
check, agent-configuration re-runs) are settled there.

Open:

- The multi-stack split is on `main` (2026-09-30): `workflow/` +
  `stacks/<name>/` rendered into `python/`, `typescript/`, and `custom/`,
  one `.agentic/toolchain.sh` gate runner per stack, the `--core` profile
  with `--python-core` as an alias, and smoke tests for every flavor in CI.
  [Design](docs/multi-stack-scaffold.md), [evidence](docs/multi-stack-research.md).
  It merged without a rendered-stack field trial; the first real project
  (2026-09-29, FPGA feasibility) took the generic flavor, and its feedback
  produced the custom stack. Still open, to be closed as projects adopt the
  flavors rather than as merge blockers: live hook trials of the TypeScript
  and custom flavors in both clients (the Codex acceptance scripts still
  target the Python flavor), a real TypeScript consumer project, and a real
  project that fills the custom runner. Go and Rust are designed for in the
  runner seam, not built.
- Revisit local execution with Codex CLI as orchestrator and a pinned local
  model as bounded coder. Keep one canonical scaffold: send the local model a
  self-contained `/delegate` packet, deny direct worktree/tool access, and add
  an adapter only after model/quantization/runtime-specific evaluation. Start
  with Qwen3.8-27B dense and Qwen3.6-35B-A3B.
- `docs/influences.md` records the provenance row for
  `python/docs/local-executor.md` without URLs or a retrieval date. The
  Terminal-Bench 2.0 figures in that doc are live leaderboard values the
  argument rests on; pin a source or soften the claim. Independent of the
  local-execution item and much cheaper.
- The portability plan is not complete by its own definition. Hook and
  execpolicy enforcement is verified live against Codex CLI 0.146.0
  (`scripts/acceptance-codex-live.sh`; evidence in
  `docs/codex-portability.md` → implementation order, item 9), but the
  authenticated `scripts/acceptance-workflow-live.sh` run, the trusted
  hook-load flow, and the remaining negative acceptance fixtures are still
  manual and unrun. Both live harnesses are opt-in and cost tokens; CI does
  not run them, so a green CI is narrower than it looks.
