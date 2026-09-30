# Multi-stack scaffold: one workflow, per-stack toolchains

**Status:** implemented through step 5 (2026-09-26) and merged to `main`
(2026-09-30); the layout below is now the repository's. Open yardstick rows,
left for real projects to close rather than held as merge blockers: live
hook trials of the TypeScript and custom flavors in both clients, validation
in a real TypeScript consumer project, and a real project that fills the
custom runner. The evidence behind the direction, and what could not be
verified, is in [`multi-stack-research.md`](multi-stack-research.md).

A third stack, `stacks/custom/`, was added on 2026-09-30 after the first
real-project trial; see [The custom stack](#the-custom-stack). It
revises two statements below that routed every adapter-less repository to
`generic/`; each is marked where it stands.

Two deviations from the plan as written, both recorded when they were made:
`dependency-hygiene` moved to `stacks/python/skills/` rather than staying
neutral, because every command in it is PyPI- and uv-specific; and the
neutral docs (`WORKFLOW.md`, `docs/`, client config, GitHub templates) moved
under `workflow/` so each flavor directory is generated whole instead of
half-sourced.

## The problem

The scaffold's workflow layer (spec, plan, test-first, review trio, close-out
gate, hooks, standing rules) is language-neutral in substance, but its
mechanical gates are hard-wired to one toolchain: `uv run ruff`, `uv run
mypy src/`, `uv run pytest`. A TypeScript project today gets one of two bad
choices:

- the `generic/` flavor, which installs the safety hooks and a contract but
  no test-first roles, no `/review-check`, no Stop gate, no CI; or
- the `python/` flavor with the Python gate edited out by hand, which breaks
  on the next `--update` and leaves the workflow prose talking about pytest.

The language a project is written in should be chosen for the project
(runtime, ecosystem, what the compiler catches). Choosing it must not cost the
workflow. The agent produces code in any mainstream language at near-zero
marginal cost, and its per-language strength varies by model and task in no
stable order (research note, finding 2), so the verification layer is the
part that must travel unchanged.

## Where the coupling is

Surveyed on `origin/main` at `39b463a`. Most of the workflow already has no
language dependency; the coupling is concentrated.

| Layer | File | Coupling |
| --- | --- | --- |
| Hooks | `python/.agentic/hooks/gate-on-stop.sh` | Runs `uv run ruff check`, `uv run mypy src/`, `uv run pytest` directly |
| Hooks | `python/.agentic/hooks/format-after-edit.sh` | `uv run ruff format`; `--strict` adds ruff check + mypy |
| Commands | `workflow/commands/review-check.md` | The four `uv run` steps are the body of the command |
| Commands | `workflow/commands/test-first.md` | Expected red causes are Python exceptions (`NotImplementedError`, missing attribute); allowed paths name `conftest.py` |
| Commands | `workflow/commands/analyze.md`, `performance.md` | pytest node-id example; `py-spy` / `scalene` / `pytest-benchmark` |
| Roles | `workflow/roles/test-first.md` | "You write pytest tests"; `conftest.py` fixtures; Python failure modes |
| Roles | `workflow/roles/reviewer.md` | Points at `python-module-split` for the 300-line check |
| Rules | `workflow/rules/python-code.md` | Python conventions, plus the external-reference provenance rule, which is language-neutral and misplaced here |
| Rules | `workflow/rules/agent-legible-code.md` | `paths: src/**/*.py`; "verifiable in one pytest" |
| Skills | `python-module-split`, `python-docstrings`, `dependency-hygiene` | The first two are Python by name; the third triggers on `pyproject.toml` but asks stack-neutral questions |
| Project files | `pyproject.toml`, `.pre-commit-config.yaml`, `.gitignore`, `.github/workflows/ci.yml`, `.github/dependabot.yml` | Entirely Python |
| Contract | `python/AGENTS.md` Stack and How-to-run sections; don't-touch `[tool.uv]` | Python |
| Docs | `WORKFLOW.md`, `docs/project-types.md` | `uv sync`, "review-check runs ruff + mypy + pytest"; routing sends every non-Python repo to `generic/` |
| Bootstrap | `python/bootstrap.sh` | Profile name `--python-core`; `--strict-hooks` means "ruff check + mypy"; creates the `src/{{PACKAGE_NAME}}/__init__.py` + `tests/test_smoke.py` starter inline |
| Scaffold CI | `scripts/smoke-test.sh`, `.github/workflows/ci.yml`, `scripts/render-client-surfaces.sh` | `uv sync` + the gate; `PYTHON_DIR` hard-coded in the renderer |

Not coupled, despite the word "python" appearing in them: `block-destructive.sh`
and `statusline.sh` only say they avoid a python3 dependency;
`closeout-check.sh`, `specs-status.sh`, `branch-check.sh`,
`context-reminder.sh`, `strip-ai-attribution.sh`, and every other command,
role, and rule are already neutral.

## Target shape: three layers

```
shared/              safety layer: hooks, Codex config, execpolicy   (exists)
workflow/            the loop: commands, roles, neutral rules, neutral skills
stacks/<name>/       the toolchain: gate runner, manifest, conventions rule,
                     starter layout, CI, pre-commit, gitignore, stack skills
```

A flavor is a composition:

| Flavor | Layers | Consumer command |
| --- | --- | --- |
| `generic/` | shared | `generic/bootstrap.sh` (unchanged) |
| `python/` | shared + workflow + `stacks/python` | `python/bootstrap.sh` (unchanged) |
| `typescript/` | shared + workflow + `stacks/typescript` | `typescript/bootstrap.sh` (new) |
| `custom/` | shared + workflow + `stacks/custom` | `custom/bootstrap.sh` (added 2026-09-30) |

`python/` and `typescript/` remain rendered surfaces, as `python/.claude/`,
`python/.agents/`, and `python/.codex/` are today. The renderer iterates over
`stacks/*` instead of assuming one. Consumer usage does not change for
existing Python projects.

`generic/` stays as the floor for repositories that do not want the
prescribed loop. The routing in `docs/project-types.md` changes from
"Python or not" to "is there a stack adapter for this repository's
language"; since 2026-09-30 a repository with no adapter that wants the loop
takes `custom/`, not `generic/`.

## The seam: one gate runner per stack

Every consumer of the quality gate calls one script instead of naming tools:

```
.agentic/toolchain.sh install            # uv sync | npm ci
.agentic/toolchain.sh format             # ruff format . | biome format --write .
.agentic/toolchain.sh lint               # ruff check . | biome lint .
.agentic/toolchain.sh typecheck          # mypy src/ | tsc --noEmit
.agentic/toolchain.sh test               # pytest -x --tb=short | vitest run
.agentic/toolchain.sh test <target>      # one test, for the red-first check
.agentic/toolchain.sh gate [--quiet]     # lint + format-check + typecheck + test
.agentic/toolchain.sh ready              # 0 ready, 3 uninitialized; other statuses are errors
```

Consumers of the seam:

- `gate-on-stop.sh` calls `gate --quiet` and blocks on non-zero. The
  `src/`-dirty guard and the loop guard do not change.
- `format-after-edit.sh` calls `format`; `--strict` adds `lint` and
  `typecheck`.
- `/review-check` runs `lint`, `format`, `typecheck`, `test` as its four
  numbered steps and reports each. The command's text stops naming tools.
- The consumer `ci.yml` quality job runs the same four subcommands as four
  named steps, so a red CI still says which tool failed.
- `AGENTS.md` "How to run things" lists the subcommands once; the stack
  section says which tools stand behind them.
- `scripts/smoke-test.sh` runs `gate` on the freshly bootstrapped project.

The runner is MANAGED, copied from `stacks/<name>/toolchain.sh`. Per-project
tuning belongs in the tool configs the runner invokes (`pyproject.toml`,
`biome.json`, `tsconfig.json`), which are project-owned, not in the runner.
A project that must change a command edits the runner knowingly and accepts
that `--update` will flag it, the same contract as the client configs today.

Nothing about a hook, a role prompt, or the Stop gate's decision logic is
per-stack. That is the property this design is buying.

## What a stack supplies

```
stacks/<name>/
  toolchain.sh              the gate runner above
  manifest/                 pyproject.toml | package.json + tsconfig.json + biome.json
  gitignore                 rendered to the project's .gitignore
  pre-commit-config.yaml    hygiene hooks (shared) + the stack's format/lint hooks
  ci.yml                    consumer CI: install, the four gate steps, hygiene, closeout, audit
  dependabot.yml            ecosystem: pip | npm
  starter/                  src/ and tests/ that are green on day zero
  rules/<name>-code.md      conventions; the standing rule appended to AGENTS.md
  contract-stack.md         the Stack + How-to-run block for AGENTS.md
  skills/                   stack skills, only where field evidence supports one
```

Two stack-specific facts the workflow prose has to fetch from the stack
rather than assume:

1. **Expected red causes for `/test-first`.** In Python a test that imports a
   missing function fails with `AttributeError` or `ImportError` on the
   symbol, and `NotImplementedError` from a stub. In TypeScript under Vitest
   the test file is transpiled without type checking, so a missing export
   normally arrives as `undefined` and the failure is `TypeError: x is not a
   function`; `tsc --noEmit` fails separately on the same missing export.
   Both are the "expected" red. The role and command say "fails for the
   missing behavior, not for a typo or a broken fixture" and defer the
   concrete list to the stack rule.
2. **Test fixture conventions.** `conftest.py` is Python; Vitest uses
   `setupFiles` in `vitest.config.ts` and `tests/helpers/`. The
   `/test-first` scope audit's allow-list comes from the stack rule.

## Maturity yardstick: what the Python flavor has

A stack reaches parity when every row below has an answer and the stack's
smoke test exercises it. This is the checklist for step 4 and for any later
stack.

| # | Python flavor has | Exercised by |
| --- | --- | --- |
| 1 | Gate runner: format, lint, typecheck, test, focused test | smoke test, Stop hook |
| 2 | Stop gate that blocks a red turn end while `src/` is dirty | smoke test (`--no-stop-gate` negative case) |
| 3 | Edit hook: format on every edit; `--strict` adds lint + typecheck | smoke test (`--strict-hooks`) |
| 4 | `/review-check` with per-step verbatim failure output | live client trial |
| 5 | Consumer CI: quality, hygiene, closeout, audit jobs; least-privilege token | consumer CI on the smoke project |
| 6 | Dependency audit and Dependabot for the stack's ecosystem | consumer CI |
| 7 | pre-commit: shared hygiene hooks + the stack's format/lint hooks + attribution strip | smoke test (commit-msg case) |
| 8 | Manifest with the strict configuration the rules assume | smoke test gate |
| 9 | Starter `src/` + `tests/` green on day zero | smoke test gate |
| 10 | Conventions standing rule rendered into `AGENTS.md` | render + adapter validation |
| 11 | Contract Stack and How-to-run blocks; `WORKFLOW.md` commands | smoke test placeholder walk |
| 12 | Test-first red causes and fixture conventions stated for the stack | `/test-first` live trial |
| 13 | Stack skills | only on field evidence; the Python ones predate that rule |
| 14 | Both clients' hooks fire on the stack (live acceptance) | `scripts/acceptance-*-live.sh` pattern |
| 15 | Validation in a real consumer project | the first project bootstrapped on the stack |

## Recommended TypeScript stack

Defaults chosen to mirror the Python stack's shape: one fast formatter-linter,
a strict type checker as a free reviewer, one test runner, an advisory audit.
Versions are as of 2026-09-26; see the research note for sources and decay.

| Role | Python (today) | TypeScript (proposed) | Why |
| --- | --- | --- | --- |
| Runtime + package manager | Python 3.12 via `uv` | Node 24 LTS pinned in `.nvmrc` and `engines` (26 from its October 2026 LTS promotion); `npm` with a committed lockfile | Zero extra install on any machine with Node |
| Format + lint | ruff | Biome 2.5, run with `--reporter concise` from hooks | One tool, one config, one binary; its type-aware rules do not need the TypeScript compiler, at the cost of partial coverage (Biome puts its floating-promise detection at about 75% of typescript-eslint's), which `tsc --noEmit` in the same gate backstops; the concise reporter exists to save agent tokens |
| Types | mypy `strict = true` | TypeScript 7.0 `tsc --noEmit`; `strict` is the 7.0 default, add `noUncheckedIndexedAccess: true` | The compiler is the reviewer that never tires; 7.0's native compiler makes the Stop-gate typecheck cheap |
| Tests | pytest | Vitest 5 | Fast, TypeScript-native, `vitest run <file>` for the focused red check |
| Dependency audit | `pip-audit` | `npm audit --audit-level=high` | Same CI job shape; Dependabot ecosystem `npm` |
| Git hooks | pre-commit | pre-commit | Reuses the proven gitleaks / private-key / large-file / no-commit-to-main hooks unchanged; costs a Python on the machine |
| Conventions rule | `python-code.md` | `typescript-code.md`: ESM only, named exports, explicit return types on exported functions, no `any` or `!` without a justifying comment, files at most 300 lines, errors carry the input and the expectation | Same intent as the Python rule, stated as actions |

Alternatives, recorded so they are not re-derived:

- **ESLint + Prettier** instead of Biome when a framework needs ESLint-only
  plugin rules. Not viable as the default today: typescript-eslint supports
  TypeScript `<6.1.0`, so its type-aware rules need the
  `@typescript/typescript6` compatibility package beside TypeScript 7 until
  7.1 exposes the programmatic API. Revisit when 7.1 ships. The runner hides
  the choice; a project swaps the two lines in `toolchain.sh` and the config
  files, nothing else moves.
- **pnpm** instead of npm for monorepos. Same swap.
- **lefthook** instead of pre-commit if requiring Python on a TypeScript box
  becomes a real friction. Not worth the second hook manager until it does.

No TypeScript skills at first. The llm-mask audit showed which scaffold rules
earned their keep in practice and which never fired; stack skills get added
on that kind of evidence, not by symmetry with the Python ones.

## Go and Rust, when their turn comes

Both have first-party answers for every runner subcommand, so each is step 4
repeated. Recorded now so the seam is designed against three stacks, not
one.

| Subcommand | Go | Rust |
| --- | --- | --- |
| install | `go mod download` | `cargo fetch` |
| format | `gofmt -l .` (check) / `gofmt -w .`; `goimports` if imports drift | `cargo fmt --check` / `cargo fmt` |
| lint | `go vet ./...` + golangci-lint v2 with at least `errcheck` and `staticcheck` | `cargo clippy --all-targets -- -D warnings` |
| typecheck | `go build ./...` | `cargo check --all-targets` |
| test | `go test ./...` | `cargo test` |
| audit | `govulncheck ./...` | `cargo audit`; `cargo deny check` where license policy matters |
| Dependabot | `gomod` | `cargo` |

Go's layout convention is `cmd/` and `internal/`, not `src/`, so the Stop
gate's dirty-tree guard has to read `TC_SOURCE_DIRS` from the runner rather
than assume `src/`. That is a step 1 design point, not a Go-only one.

## Implementation order

Each step leaves every existing smoke test green and ships as its own PR.
Steps 1 and 2 change no consumer behavior; they make the seam exist.

1. **Introduce the runner in the Python flavor.** Add
   `python/.agentic/toolchain.sh` with the subcommands above, wrapping the
   current `uv run` commands. Point `gate-on-stop.sh`, `format-after-edit.sh`,
   `review-check.md`, the consumer `ci.yml`, `AGENTS.md` How-to-run,
   `WORKFLOW.md`, and `scripts/smoke-test.sh` at it. The runner exports
   `TC_SOURCE_DIRS` and `TC_TEST_DIRS`; the Stop gate's dirty guard reads
   them instead of assuming `src/`. Validation: all three profile smoke
   tests plus `--strict-hooks` and `--no-stop-gate`; the consumer CI diff
   is four renamed steps.
2. **Neutralize the workflow prose.** `test-first` role and command,
   `reviewer`, `analyze`, `performance`, `agent-legible-code` paths. Move the
   external-reference provenance section out of `python-code.md` into its own
   neutral rule so it renders for every stack. Validation: render, adapter
   validation, smoke.
3. **Split the sources.** Move `python/workflow/` to top-level `workflow/`;
   move the Python-only pieces (manifest, gitignore, pre-commit, CI,
   dependabot, starter, `python-code.md`, the two Python skills, the
   contract's stack block) to `stacks/python/`. Teach the renderer to iterate
   `stacks/*` and emit `<stack>/`. Move the bootstrap body to
   `scripts/bootstrap-stack.sh` with a `--stack` argument; `python/bootstrap.sh`
   becomes a thin wrapper so the documented consumer command survives. Keep
   `--python-core` as a silent alias of `--core` so persisted
   `.agentic/scaffold-state` still resolves (decision recorded below). Validation: the rendered
   `python/` tree is byte-identical before and after, except for moved
   source paths; smoke.
4. **Add `stacks/typescript/`.** The runner, manifest set, starter, CI,
   conventions rule, and `typescript/bootstrap.sh`. Add
   `scripts/smoke-test-typescript.sh` and a CI row for it. Validation: a
   fresh TypeScript project is green on day zero through `toolchain.sh gate`;
   both clients' hooks fire on it, following the live trial pattern from
   `docs/codex-portability.md`; every row of the maturity yardstick has an
   answer.
5. **Docs and close-tasks.** Top-level `README.md`, `python/README.md`, a
   `typescript/README.md`, `docs/project-types.md` routing, the new-project
   checklist, the `AGENTS.md` current-state block. Record any outside source
   consulted for the TypeScript defaults in `docs/influences.md` in the same
   PR.

Later stacks (Go, Rust) are step 4 repeated. As written on 2026-09-26: a
stack that cannot supply a `format`, `lint`, `typecheck`, and `test`
subcommand is not a stack for this scaffold; it uses `generic/`. Revised
2026-09-30: it uses `custom/`, which lets the project supply those
subcommands itself and mark a missing one `no_tool`.

## The custom stack

Added 2026-09-30. It is the loop for a repository with no adapter: every
command, role, hook, and rule from `workflow/`, with the gate runner
shipped as a template instead of a filled file.

**Evidence.** The branch's first real-project trial (2026-09-29) was an
FPGA feasibility project. The rubric sent it to `generic/`, as designed.
The owner wanted the scaffold's discipline anyway, so the founding agent
hand-wrote a `WORKFLOW.md` and a spec convention, and in two days the
project shipped two specs through them and drafted a third. The first was
research with no code; the second installed a toolchain and reached the
decisive result (the core did not fit the device). The loop earned its keep
with no Stop gate and no workflow commands installed, and for the first
spec with no toolchain at all, which is the case "generic is the floor" did
not cover: a
project that wants the loop before it has, or without ever having, an
adapter. The same trial showed the founding prompt pointing at
`WORKFLOW.md` and `docs/specs/`, neither of which generic installs.

**Shape.**

- `stacks/custom/toolchain.sh` has the same subcommands as the other
  runners. Its six step functions call `unfilled <step>`, and
  `TC_SOURCE_DIRS` is empty. `TC_CONFIGURED=0` makes `ready` exit 3,
  the only status consumers may skip. Set it to 1 after filling the runner:
  missing directories, missing functions, and unfinished steps then return
  an error. Shared hooks, custom pre-commit entries, and custom CI check
  syntax and distinguish the unconfigured status from a broken runner.
- The project fills each step with its real command, or `no_tool` for a
  step its stack has no tool for. `no_tool` is the only relaxation of the
  four-subcommand rule, and it is explicit and visible in review.
- The runner, `.github/workflows/ci.yml`, and `.github/dependabot.yml` are
  project-owned here: the project supplies its tools and ecosystems. A stack
  claims a normally managed path by
  listing it in `STACK_PROJECT_FILES`; `sync` in the bootstrap body skips a
  claimed path, as does profile pruning, so `--update` cannot overwrite or
  delete it. The consumer CI's quality job prints a notice only for an
  explicitly unconfigured runner; a broken active configuration fails.
- No starter layout, no stack skills, no `rules/` file. Conventions and the
  test-first notes live in `contract-stack.md`, which renders into the
  project-owned part of `AGENTS.md`; the standing-rules block is refreshed
  by `--update` and would overwrite a filled placeholder.
- The contract's don't-touch list names the filled runner, since an agent
  that can edit the gate definition can also weaken it.
- Work with no code to test (research, measurement, documentation) skips
  `/test-first`; the spec names the evidence and `/review` checks it. That
  line is in `WORKFLOW.md` for every stack.

**Against the yardstick.** `scripts/smoke-test-custom.sh` fills the runner
with a small shell toolchain and exercises rows 1, 2, and 11, without the
`--no-stop-gate` negative case. Row 3 (edit hook) is exercised in the
unconfigured, active, and broken-configuration states. Row 7's custom format/lint
entries are executed in those states; installation through pre-commit
itself remains untested.
Row 10 is met differently: the conventions are a filled placeholder in the
contract, checked by the render and adapter validation, not a rule file.
Rows 5 and 6 are partial by design: the quality job is one guarded `gate`
step and there is no audit job, because both depend on the project's
ecosystem. Rows 8, 9, 12, and 13 are the project's to supply. Rows 14 and
15 are open: no live hook trial in either client, and no real project has
filled the runner yet.

**Migration and regression coverage.** Generic-to-custom installation
archives the old hash directory, upgrades unchanged client configs, and
preserves customized configs with merge candidates. Project contracts and
hand-written workflow files are preserved; the contract candidate must be
reconciled before using the loop. The custom smoke test covers stock and
customized migration, readable state on subsequent updates, Dependabot
ownership across profile changes, and failures from missing directories,
missing functions, unfinished active steps, syntax/runtime errors, and a
missing runner. It executes the shipped CI step and pre-commit entries as
well as the hooks. These checks do not establish live client integration.

**Relation to real adapters.** `custom/` does not replace Go or Rust
adapters. When a second project wants the same tools, its filled runner is
the draft of `stacks/<name>/toolchain.sh`, and the adapter adds what a
template cannot: a manifest, a starter that is green on day zero, an audit
job.

## Deliberately not in scope

- A universal linter or a meta-config that generates per-tool configs. The
  seam is the runner's subcommand names, nothing deeper.
- Per-stack review roles. The reviewer and adversarial reviewer read diffs;
  their checklists are about behavior, hygiene, and spec fit, not syntax.
- Rewriting the `generic/` flavor. It remains the no-loop floor. (Still
  true after 2026-09-30: `custom/` sits beside it; generic gained only a
  day-zero list in its README and a pointer to `custom/`.)
- Retroactive `--update` of consumer projects. They are snapshots; the change
  reaches them at their next bootstrap.

## Decisions, all settled 2026-09-26

- Biome vs ESLint + Prettier: Biome. The research note makes it the only
  workable default until TypeScript 7.1 ships its programmatic API; revisit
  then on the coverage argument.
- npm vs pnpm: settled on npm (2026-09-26). It ships with Node, so a
  bootstrapped project needs no second install, and `npm ci` pins CI to the
  lockfile. pnpm's advantages (faster, shared store, refuses undeclared
  imports, workspaces) matter for monorepos; that is the documented swap.
- `--python-core` vs `--core`: settled on `--core` (2026-09-26). Profiles
  (minimal, core, full) say how much workflow a project wants; the stack is
  a separate axis chosen for the project, so a profile must not carry a
  language name. `--python-core` stays as a silent alias in the flag parser
  and the state reader, so persisted `PROFILE=python-core` and old commands
  keep working. Rename lands in step 3 with the source split; the name
  appears in 15 files, 57 places, none of them in workflow sources.
