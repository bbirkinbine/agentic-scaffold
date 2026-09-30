# Custom-stack agentic-workflow scaffolding

Drop-in scaffolding for a project whose stack has no adapter under
`stacks/` (Go, Rust, HDL/FPGA, infrastructure code, shell, anything else)
and that wants the full workflow anyway. This directory is **rendered** by
`scripts/render-client-surfaces.sh` from the shared `workflow/` sources and
`stacks/custom/`; edit those, never this tree.

```bash
cd your-project
bash path/to/agentic-scaffold/custom/bootstrap.sh            # --core profile
bash path/to/agentic-scaffold/custom/bootstrap.sh --full
bash path/to/agentic-scaffold/custom/bootstrap.sh --update
```

The workflow (spec, plan, test-first, review trio, Stop gate, close-out
check, hooks, standing rules) is the same one the Python and TypeScript
flavors ship; see `WORKFLOW.md` after bootstrapping. The difference is the
gate behind `.agentic/toolchain.sh`: the other stacks name their tools,
this one ships a template the project fills.

| Runner subcommand | In the template | You write |
| --- | --- | --- |
| `install` | `unfilled` | the dependency/toolchain install, or `no_tool` |
| `format` / `format-check` | `unfilled` | the formatter in write and check mode, or `no_tool` |
| `lint` | `unfilled` | the linter, warnings as errors |
| `typecheck` | `unfilled` | a type check, compile, or elaboration that fails on a broken tree |
| `test [target]` | `unfilled` | the suite, and one focused target when an argument is given |
| `gate` | works as shipped | nothing; it runs the four checks and names every red step |

**Before the runner is filled**, `ready` fails. The Stop hook, the edit
hook, the pre-commit gate steps, and CI's quality job all check `ready`
first, so they stay quiet; CI prints a notice saying no quality gate ran.
The loop still works: `/spec`, `/plan`, and `/review` need no toolchain,
which is what a research or feasibility phase uses. `/review-check`
reports that the gate is not defined.

**Fill it in the first spec that adds code to check.** Set
`TC_SOURCE_DIRS` and `TC_TEST_DIRS`, replace each `unfilled <step>`, and
use `no_tool` for a step the stack has no tool for. From then on the Stop
gate, the hooks, and CI enforce it. A step filled with a command that
cannot fail defeats the gate; the contract's don't-touch list says so.

Project-owned files, laid down once and never overwritten by `--update`:
`.gitignore`, `.agentic/toolchain.sh`, and `.github/workflows/ci.yml` (the
last two are scaffold-managed in the other stacks; here the scaffold
cannot know the tools or how to install them on a CI runner). There is no
starter layout and no dependency-audit job; `ci.yml` and `dependabot.yml`
say where to add the project's ecosystem.

The contract's Stack, How-to-run, and Test-first sections are placeholders
the founding session fills. "Not chosen yet; spec NNNN chooses it" is a
valid fill on day zero, and better than a guessed toolchain.

Git hooks use pre-commit (a Python tool) so the hygiene hooks are the same
ones every flavor gets: `uv tool install pre-commit` or `pipx install
pre-commit`, then `pre-commit install`.

When a second project wants the same tools, that is the signal to promote
the filled runner into a real `stacks/<name>/` adapter
(`docs/multi-stack-scaffold.md` at the scaffold root lists what one
supplies).
