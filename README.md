# agentic-scaffold

Reusable project-bootstrap templates and agentic-workflow scaffolding
for new repositories. Two flavors depending on whether the new repo is
a Python project (and should use the full agentic-workflow scaffolding)
or something else (infra, FPGA, shell, etc.) that just needs the basic
conventions.

> ## Status
>
> Published as a personal reference, not a managed product. Issues and
> PRs are welcome but won't get fast turnaround.
>
> **This repo is in-flight.** The scaffolding evolves as the workflow
> does. Pin a specific commit if you depend on a snapshot.

This content previously lived under `templates/` in
[`bbirkinbine/dotfiles`](https://github.com/bbirkinbine/dotfiles); its
pre-move development history is in that repo's log.

## Two flavors

### Python projects — use [`python/`](python/)

The full agentic-workflow scaffolding: `CLAUDE.md` + `AGENTS.md` +
`WORKFLOW.md`, default and opt-in subagents, slash commands,
auto-invoked skills, PostToolUse hook, `pyproject.toml` /
`.pre-commit-config.yaml`, and the `docs/specs/` convention.

Run [`python/bootstrap.sh`](python/bootstrap.sh) from a new repo's
root and everything drops into place.

**Start with [`python/WORKFLOW.md`](python/WORKFLOW.md)** — it has the
day-zero checklist and the per-feature loop walkthrough. For the full
file inventory, the agentic-loop table, and opt-in subagent triggers,
see [`python/README.md`](python/README.md).

This file deliberately doesn't enumerate the subagents / commands /
skills — those drift as the scaffolding evolves. The two READMEs below
are the source of truth.

### Non-Python repos — use the top-level templates

- [`CLAUDE.md.template`](CLAUDE.md.template) — generic project context
  for Claude Code (and any other AI coding agent). No Python
  assumptions; fill in the stack section per repo. Includes the
  no-co-author rule and the strengthened public-repo hygiene section
  (treat-as-public-from-commit-#1).
- [`README.md.template`](README.md.template) — human-facing GitHub
  landing page with Status block and AI-tools Acknowledgements.
- [`github-about.md`](github-about.md) — checklist for the GitHub repo's
  "About" sidebar (description, website, topics — specifically the
  `ai-assisted` tag).

### Both flavors use [`new-project-checklist.md`](new-project-checklist.md)

The authoritative step-by-step for any new repo — identity check,
GitHub About sidebar, first-commit hygiene, and the pre-flip
private→public checklist. This mirrors the Obsidian source at
`Research/Programming/New Project Setup.md` in my vault.

## How to use

**For a Python project:**

```bash
cd ~/Downloads/src/new-project
bash ~/Downloads/src/agentic-scaffold/python/bootstrap.sh
# then walk the rest of new-project-checklist.md
```

**For a non-Python repo:**

```bash
cd ~/Downloads/src/new-project
cp ~/Downloads/src/agentic-scaffold/CLAUDE.md.template  ./CLAUDE.md
cp ~/Downloads/src/agentic-scaffold/README.md.template  ./README.md
# Replace every {{...}} placeholder:  rg '{{' .
# then walk the rest of new-project-checklist.md
```

The Obsidian vault has the authoritative checklist with extra context
and *why* notes; this repo is the version that lives next to the
actual template files so it stands alone on machines without the
vault.

## Acknowledgements

This project was developed with the assistance of AI tools.

## License

MIT — see [`LICENSE`](LICENSE).
