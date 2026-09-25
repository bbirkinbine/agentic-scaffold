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
checklist, and the full Python agentic-workflow scaffolding under
`python/` (subagents, workflows, skills, hooks, `bootstrap.sh`).
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

Markdown templates plus bash (both bootstrap scripts, client-neutral hook
sources under `shared/hooks/`, rendered Python hooks under
`python/.agentic/hooks/`, and validation under `scripts/`). No build or
deploy target — files here are consumed by copy into new repos, and smoke
tests validate those generated projects.

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
bash -n python/bootstrap.sh
bash -n generic/bootstrap.sh shared/hooks/*.sh python/.agentic/hooks/*.sh scripts/*.sh
shellcheck --severity=warning generic/bootstrap.sh python/bootstrap.sh shared/hooks/*.sh python/.agentic/hooks/*.sh scripts/*.sh
bash scripts/validate-codex-adapters.sh
bash scripts/smoke-test-generic.sh
bash scripts/smoke-test.sh <profile>   # for changes to bootstrap.sh, pyproject.toml,
                                       # hooks, or anything the bootstrap copies
```

`scripts/smoke-test.sh` bootstraps a Python profile into a temp dir,
asserts the installed file set, fills the day-zero placeholders, and runs
the fresh project's full quality gate. `scripts/smoke-test-generic.sh`
covers the stack-neutral flavor. CI (`.github/workflows/ci.yml`) runs the
shell checks plus every flavor/profile smoke test on each push and PR — a
red run means the template would ship broken projects.

`{{PLACEHOLDER}}` markers throughout the repo (in template contracts
and in `python/AGENTS.md` / `python/pyproject.toml`) are intentional —
they are filled by the consumer, never here, so there is no
placeholder check on this repo itself.

Don't claim a change is "ready" without at least:

1. A clean run of the checks above for the affected file(s).
2. An updated `README.md` (this repo's, `python/README.md`, or both) if
   the change adds/removes files or changes how the scaffolding is used.

---

## Don't touch

- `.git/` — obviously.
- `LICENSE` — MIT, created with the repo.

---

## Generated surfaces: edit the source, then re-render

`python/workflow/` and top-level `shared/` are the client-neutral source of
truth. `python/.claude/`, `python/.agents/`, and `python/.codex/` are
generated by `scripts/render-client-surfaces.sh`, which prunes any file it
does not own — a file added straight to a generated directory disappears on
the next run. This file is authored directly and is not rendered.

---

## How consumers use this repo

A Claude Code or Codex session is pointed at the latest checkout, installs
the scaffold into the new repo, and pre-fills the templates from the
founding conversation. Consumer projects are snapshots: `bootstrap.sh
--update` is rarely run, so a change here reaches projects at their next
bootstrap, not retroactively. The methodology behind the scaffold is kept in
personal notes outside this repo.

---

## Current state (updated 2026-09-25)

The scaffold is dual-client (Claude Code and Codex CLI) since 2026-08-11 and
validated in day-to-day use across multiple real projects, both flavors.
Corrections feed back here as they surface. History lives in `git log`;
each squash-merge body explains its change. Borrowed ideas, the sources
behind specific rules, and decisions already considered and rejected are in
`docs/influences.md` — check it before proposing a change prompted by an
outside source, since several (contract length, a post-red test-tamper
check, agent-configuration re-runs) are settled there.

Open:

- Add `generic-smoke` to this repo's `protect-main` required status
  checks. The job runs on every PR but is not required, so it can go red
  without blocking a merge.
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
