# TypeScript agentic-workflow scaffolding

Drop-in scaffolding for new TypeScript projects. This directory is
**rendered** by `scripts/render-client-surfaces.sh` from the shared
`workflow/` sources and `stacks/typescript/`; edit those, never this tree.

```bash
cd your-project
bash path/to/agentic-scaffold/typescript/bootstrap.sh            # --core profile
bash path/to/agentic-scaffold/typescript/bootstrap.sh --full
bash path/to/agentic-scaffold/typescript/bootstrap.sh --update
```

The workflow (spec, plan, test-first, review trio, Stop gate, close-out
check, hooks, standing rules) is the same one the Python flavor ships; see
`WORKFLOW.md` after bootstrapping. Bootstrap installs the three client
adapters additively: `.claude/`, `.codex/`, and `.pi/`. Pi receives project
prompts, named roles, a local lifecycle extension, and exact-pinned
`pi-subagents`; it inherits whichever hosted or local model the operator
selected. See `docs/pi-agent.md` after bootstrap for trust/reload steps and
limits. What this stack supplies is the gate
behind `.agentic/toolchain.sh`:

| Runner subcommand | Tool |
| --- | --- |
| `install` | `npm ci` (or `npm install` before a lockfile exists) |
| `format` / `format-check` | Biome, `--reporter concise` |
| `lint` | Biome, warnings are errors |
| `typecheck` | `tsc --noEmit`, strict plus `noUncheckedIndexedAccess` |
| `test [target]` | Vitest |
| `gate` | all four checks, every red step reported |

Project-owned files laid down once: `package.json`, `tsconfig.json`,
`biome.json`, `vitest.config.ts`, `.nvmrc` (Node 24), `.gitignore`. The
starter `src/index.ts` and `tests/index.test.ts` make the gate green on day
zero; replace them.

Why these defaults, with sources and dates, is in
`docs/multi-stack-research.md` at the scaffold root (TypeScript 7 has no
programmatic API until 7.1, so typescript-eslint cannot type-lint it; Biome's
type-aware rules use their own inference). To swap a tool, change the line
in `.agentic/toolchain.sh` and the tool's config file; nothing else moves.

Git hooks use pre-commit (a Python tool) so the hygiene hooks are the same
ones every flavor gets: `uv tool install pre-commit` or `pipx install
pre-commit`, then `pre-commit install`.

No stack skills ship yet; they are added on field evidence, not by symmetry
with the Python ones.
