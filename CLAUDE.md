# CLAUDE.md — agentic-scaffold

> **Purpose.** Persistent project context for Claude Code (and other AI
> coding agents) working in this repository. Read this before suggesting
> changes. `README.md` is for humans landing on the GitHub page; this file
> is for the agent that opens the repo and starts working.

---

## What this repo is

Project-bootstrap templates and agentic-workflow scaffolding for new
repos — generic `CLAUDE.md` / `README.md` /
`AGENTS.md` templates, the new-project checklist, the GitHub About
checklist, and the full Python agentic-workflow scaffolding under
`python/` (subagents, slash commands, skills, hooks, `bootstrap.sh`).
This content moved here from `templates/` in the
`github.com/bbirkinbine/dotfiles` repo on 2026-06-09; pre-move history
is in that repo's log.

This repo is **public** on GitHub (`github.com/bbirkinbine/agentic-scaffold`).
Treat every change as world-readable: file contents, commit messages,
branch names, PR descriptions, and issue text are all indexed by search
engines. No secrets, no internal hostnames, no work-related context.

---

## Stack / scope

Markdown templates plus bash (`python/bootstrap.sh`, the hook scripts
under `python/.claude/hooks/`). No build, no test suite, no deploy
target — files here are consumed by copy into new repos.

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

## Secrets and public-repo hygiene

**Treat this repo as public from commit #1.** Rewriting history after a
leak is destructive and incomplete — the cheapest fix is to never commit
the thing in the first place. The full rules (what never to commit,
what quietly slips through, the pre-flip checklist) live in
[`new-project-checklist.md`](new-project-checklist.md) and in the
hygiene section of [`CLAUDE.md.template`](CLAUDE.md.template); both
apply to this repo itself, not just to repos bootstrapped from it.

---

## Validation gates before claiming done

```bash
bash -n python/bootstrap.sh
bash -n python/.claude/hooks/*.sh
```

`{{PLACEHOLDER}}` markers throughout the repo (in `*.template` files
and in `python/CLAUDE.md` / `python/pyproject.toml`) are intentional —
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

## Open work / current state (updated 2026-06-12)

Repo split out of the dotfiles repo on 2026-06-09. The Python
scaffolding under `python/` is the active surface; the methodology
behind it is maintained in personal notes outside this repo.

The 2026 workflow refresh merged to `main` on 2026-06-12 (branch
`feat/2026-workflow-refresh`, since deleted): `.claude/rules/` split of
the oversized `python/CLAUDE.md`, `/clarify` + `/analyze` commands,
PreCompact hook, Stop-hook cap documentation, completion-ladder +
parallel-agents + plugin-packaging docs, opt-in Claude CI review
workflow, adversarial-reviewer scope discipline, AGENTS.md symlink
guidance. The same merge brought the spec-numbering doctrine (spec
number = issue number; identity, not execution order; `**Depends on:**`
field) and the `/product-spec` interview that writes
`docs/specs/0000-product.md`, the product-level (PRD) layer.

Open: the refreshed scaffolding has not yet been validated end-to-end
on a real project — exercise `bootstrap.sh` and the issue-first
`/spec` → `/product-spec` flow on the next new repo and feed
corrections back here.
