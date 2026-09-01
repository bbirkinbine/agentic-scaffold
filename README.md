# agentic-scaffold

Project-bootstrap templates and agentic-workflow scaffolding for new
repositories. Two dual-client flavors: a full Python agentic workflow, or a
lighter stack-neutral contract and safety layer for anything else (infra,
shell, FPGA, ...).

> ## Status
>
> Published as a personal reference, not a managed product. Issues and
> PRs are welcome but won't get fast turnaround. The scaffolding evolves
> as the workflow does — pin a commit if you depend on a snapshot.
> CI smoke-tests both bootstraps on every push: every Python profile runs
> its quality gate, and the generic flavor exercises fresh install, update,
> legacy migration, hooks, and client configuration.

## Python projects

Run [`python/bootstrap.sh`](python/bootstrap.sh) from a new repo's root,
then open [`python/WORKFLOW.md`](python/WORKFLOW.md) — it walks day-zero
setup and the per-feature loop, step by step. The default is
`--python-core`; use `--minimal` for a thinner starter or `--full` for the
author's complete workflow bundle. The Python scaffold installs Claude Code
and Codex CLI adapters together, so either client can continue from the same
spec, tests, diff, and phase handoff.

```bash
cd your-project                              # the new repo you're starting
bash path/to/agentic-scaffold/python/bootstrap.sh   # wherever you cloned this repo
# then follow python/WORKFLOW.md
```

New to the scaffolding? [`python/docs/project-types.md`](python/docs/project-types.md)
is the orientation map: which flavor and profile to pick, what each one
installs, and when to reach for each agent, skill, and command;
[`python/docs/workflow-diagram.md`](python/docs/workflow-diagram.md) draws
the same loop as Mermaid diagrams. For the
full file inventory and the opt-in pieces, see
[`python/README.md`](python/README.md). This page deliberately doesn't
list the commands, subagents, or skills — they change as the scaffold
evolves, and the two READMEs under `python/` are the source of truth.
For Codex startup, project trust, workflow invocation, and client switching,
see [`python/docs/codex-cli.md`](python/docs/codex-cli.md).

## Non-Python repos

Run the generic bootstrap and fill the `{{...}}` placeholders:

```bash
cd your-project
bash path/to/agentic-scaffold/generic/bootstrap.sh
rg '{{' .
```

This installs a complete canonical `AGENTS.md` plus a `CLAUDE.md` import,
Claude and Codex project configuration, shared safety hooks, Codex command
rules, and a Codex startup guide. It deliberately does not invent
language-specific formatting, tests, or workflow skills; fill the contract's
validation section with the repository's real commands. See
[`generic/README.md`](generic/README.md).

## Both flavors

Walk [`new-project-checklist.md`](new-project-checklist.md) (git
identity, GitHub setup, the private→public hygiene checklist) and
[`github-about.md`](github-about.md) (the repo "About" sidebar).

## Contributing

Each PR carries its own close-tasks: related status, current-state, docs, and
checklist updates belong in the implementation PR rather than a follow-up.
The PR template prompts for that closeout before merge.

## Acknowledgements

Developed with the assistance of AI tools.

Several features here were borrowed from other people's work, and a number of
rules trace to specific research and talks.
[`docs/influences.md`](docs/influences.md) credits them, and records what was
considered and rejected.

## License

MIT — see [`LICENSE`](LICENSE).
