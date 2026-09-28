# agentic-scaffold

Scaffolding that sets up a new repository so a coding agent (Claude Code or
Codex CLI) works in a disciplined loop: write a spec, plan, write failing
tests first, implement, then pass a quality gate and an independent review
before anything is committed. Python and TypeScript get the full loop;
any other stack gets the contract and safety hooks.

## Quick start

1. **Clone this repo once**, anywhere on your machine.

   ```bash
   git clone https://github.com/bbirkinbine/agentic-scaffold.git ~/src/agentic-scaffold
   ```

2. **Create your project and open the agent in it.**

   ```bash
   mkdir my-project && cd my-project && git init
   claude        # or: codex
   ```

3. **Paste this prompt**, filling in the blank:

   ```text
   The agentic-scaffold checkout is at ~/src/agentic-scaffold. Read its
   workflow/docs/project-types.md, section 1. I want to build: <what it does,
   where it runs, who uses it, what it talks to>. Choose the stack (or the
   generic flavor), tell me the deciding question, run that flavor's
   bootstrap.sh here, then fill the placeholders from what I told you and
   walk me through WORKFLOW.md day zero.
   ```

The agent picks Python, TypeScript, or the generic flavor and says why,
installs the scaffolding, drafts the project contract from your description,
and walks you through the first commit. After that, `WORKFLOW.md` in your
project is the guide; it opens with the short version of the loop.

Two things to do yourself: read every line of the `AGENTS.md` the agent
drafted before you commit it, and restart the agent once after setup so its
hooks load.

## What you get

- **A project contract** (`AGENTS.md`) both agents read: stack, how to run
  things, standing rules, what not to touch.
- **The loop as commands:** `/spec`, `/plan`, `/test-first`,
  `/review-check`, `/review`, with fresh-context subagents for planning and
  review. Codex uses the same names with `$`.
- **Gates that do not depend on the agent remembering:** a hook that blocks
  ending a turn while the source tree is dirty and lint, format, types, or
  tests are red; a hook that blocks destructive shell commands; a commit
  hook that keeps AI attribution out of history; CI that runs the same
  gate plus a dependency audit.
- **One file that names the tools,** `.agentic/toolchain.sh`. Python: uv,
  ruff, mypy, pytest. TypeScript: npm, Biome, tsc, Vitest. Swap a tool
  there and nothing else moves.

## By hand, and reference

```bash
bash ~/src/agentic-scaffold/python/bootstrap.sh       # or typescript/, or generic/
bash ~/src/agentic-scaffold/python/bootstrap.sh --help
```

- [`workflow/docs/project-types.md`](workflow/docs/project-types.md) — which
  flavor and profile, what each installs, when to run each command.
- [`workflow/WORKFLOW.md`](workflow/WORKFLOW.md) — the loop step by step
  (copied into every project).
- [`python/README.md`](python/README.md) and
  [`typescript/README.md`](typescript/README.md) — file inventory per stack;
  [`generic/README.md`](generic/README.md) for everything else.
- [`new-project-checklist.md`](new-project-checklist.md) — the author's
  repo-creation checklist (GitHub settings, the private-to-public hygiene
  pass). Optional for others.
- [`docs/multi-stack-scaffold.md`](docs/multi-stack-scaffold.md) — how a
  stack is added; [`docs/multi-stack-research.md`](docs/multi-stack-research.md)
  — the evidence behind the design.

`python/` and `typescript/` are rendered from `workflow/` and
`stacks/<name>/`; edit the sources and run
`scripts/render-client-surfaces.sh`.

## Status

A personal reference, not a managed product. Issues and PRs are welcome but
won't get fast turnaround; pin a commit if you depend on a snapshot. CI
bootstraps every flavor and profile on every push and runs each fresh
project's quality gate.

## Contributing

Each PR carries its own close-tasks: related status, current-state, docs,
and checklist updates belong in the implementation PR, not a follow-up.

## Acknowledgements

Developed with the assistance of AI tools. Borrowed ideas and the research
behind specific rules are credited in [`docs/influences.md`](docs/influences.md).

## License

MIT — see [`LICENSE`](LICENSE).
