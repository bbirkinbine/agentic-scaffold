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

**Before activation**, `TC_CONFIGURED=0` makes `ready` exit 3. The Stop
hook, edit hook, pre-commit steps, and CI quality job skip only that status.
CI prints a notice saying no quality gate ran.
The loop still works: `/spec`, `/plan`, and `/review` need no toolchain,
which is what a research or feasibility phase uses. `/review-check`
reports that the gate is not defined.

**Fill it in the first spec that adds code to check.** Set
`TC_SOURCE_DIRS` and `TC_TEST_DIRS`, replace each `unfilled <step>`, and
use `no_tool` for a step the stack has no tool for. Then set
`TC_CONFIGURED=1` and run the gate. Keep it active: missing directories,
unfinished steps, or a broken runner must fail validation. From then on
the Stop gate, the hooks, and CI enforce it. A step filled with a command that
cannot fail defeats the gate; the contract's don't-touch list says so.

Project-owned files, laid down once and never overwritten by `--update`:
`.gitignore`, `.agentic/toolchain.sh`, `.github/workflows/ci.yml`, and
`.github/dependabot.yml` (the last three are scaffold-managed in the other
stacks; here the scaffold cannot know the tools, CI setup, or ecosystems). There is no
starter layout and no dependency-audit job; `ci.yml` and `dependabot.yml`
say where to add the project's ecosystem; updates preserve those additions.

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

## Moving from generic

Run the same `custom/bootstrap.sh` command inside the generic project.
The bootstrap archives generic's hashes in `.agentic/generic-scaffold-state`
and writes readable stack state. Unchanged generic client configs receive
the workflow hooks; customized configs stay intact, with merge candidates
under `.agentic/generic-migration/` and a warning that hooks need manual
reconciliation. Existing contract, README, and hand-written workflow files
are preserved, including when the migration is invoked with `--update`.
Merge the contract candidate from `.agentic/generic-migration/AGENTS.md`
into the project's filled contract, then restart the clients and verify
hook loading. Subsequent updates use `custom/bootstrap.sh --update`.

Existing custom consumers must merge this revision's activation switch and
CI status handling manually: those files are project-owned. Activate an
already-filled runner with `TC_CONFIGURED=1`; do not reset it to skip errors.
