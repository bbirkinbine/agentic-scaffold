# agentic-scaffold

Project-bootstrap templates and agentic-workflow scaffolding for new
repositories. Two flavors: a full Python agentic workflow, or a minimal
set of conventions for anything else (infra, shell, FPGA, ...).

> ## Status
>
> Published as a personal reference, not a managed product. Issues and
> PRs are welcome but won't get fast turnaround. The scaffolding evolves
> as the workflow does — pin a commit if you depend on a snapshot.

## Python projects

Run [`python/bootstrap.sh`](python/bootstrap.sh) from a new repo's root,
then open [`python/WORKFLOW.md`](python/WORKFLOW.md) — it walks day-zero
setup and the per-feature loop, step by step.

```bash
cd your-project                              # the new repo you're starting
bash path/to/agentic-scaffold/python/bootstrap.sh   # wherever you cloned this repo
# then follow python/WORKFLOW.md
```

For the full file inventory and the opt-in pieces, see
[`python/README.md`](python/README.md). This page deliberately doesn't
list the commands, subagents, or skills — they change as the scaffold
evolves, and the two READMEs under `python/` are the source of truth.

## Non-Python repos

Copy the two top-level templates and fill the `{{...}}` placeholders:

```bash
cd your-project                              # the new repo you're starting
cp path/to/agentic-scaffold/CLAUDE.md.template  ./CLAUDE.md
cp path/to/agentic-scaffold/README.md.template  ./README.md
rg '{{' .   # find every placeholder, then replace it
```

## Both flavors

Walk [`new-project-checklist.md`](new-project-checklist.md) (git
identity, GitHub setup, the private→public hygiene checklist) and
[`github-about.md`](github-about.md) (the repo "About" sidebar).

## Acknowledgements

Developed with the assistance of AI tools.

## License

MIT — see [`LICENSE`](LICENSE).
