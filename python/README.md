# Python agentic-workflow scaffolding

Drop-in scaffolding for new Python projects. Mirrors the destination structure exactly — `bootstrap.sh` just `cp -r`s
the files into place.

This directory **is the source of truth** for the agentic-workflow
scaffolding, version-controlled in this repo
(`github.com/bbirkinbine/agentic-scaffold`; before 2026-06-09 it lived
under `templates/python/` in `github.com/bbirkinbine/dotfiles`). The
conventions and rationale behind each piece are maintained in personal
methodology notes outside this repo.

## What's in here

```text
python/
├── README.md                              # this file (not copied to projects)
├── README.md.template                     # laid down as the project's README.md (incl. the AI-assist Acknowledgements section)
├── bootstrap.sh                           # the one-shot setup script
├── AGENTS.md                              # complete client-neutral project contract
├── CLAUDE.md                              # one-line Claude Code import of AGENTS.md
├── WORKFLOW.md                            # human-facing loop walkthrough (start here)
├── workflow/                              # shared sources for the contract, commands, roles, rules, and skills
├── pyproject.toml                         # uv + ruff + mypy + pytest config
├── .gitignore                             # Python ignores, incl. .env* (.env.*.example kept)
├── .pre-commit-config.yaml                # no-commit-to-main + secret scan + ruff + mypy + commit-msg AI-attribution strip
├── .agentic/
│   └── hooks/                             # shared hook implementations used by both clients
├── .agents/
│   └── skills/                            # Codex workflow + reusable repository skills
├── .claude/
│   ├── settings.json                      # permissions deny (.env/key reads) + status line + SessionStart branch check + PreToolUse deny-list + PostToolUse format-only + PreCompact preserve-context
│   ├── agents/
│   │   ├── analyzer.md                    # Fresh read-only consistency cross-check
│   │   ├── planner.md                     # Spec → markdown plan; read-only
│   │   ├── test-first.md                  # Write failing pytest tests; never implements
│   │   ├── reviewer.md                    # Independent diff reviewer (collaborative framing)
│   │   ├── reviewer-adversarial.md        # Independent diff reviewer (adversarial framing)
│   │   └── optional/
│   │       ├── security-reviewer.md       # App-sec review (opt-in, not auto-copied)
│   │       ├── performance-reviewer.md    # Perf review (opt-in, not auto-copied)
│   │       └── evaluator.md               # Eval suite for an LLM/AI surface (opt-in, not auto-copied)
│   ├── commands/
│   │   ├── product-spec.md                # /product-spec — interview to create/refresh docs/specs/0000-product.md
│   │   ├── spec.md                        # /spec <name> — create docs/specs/NNNN-<slug>.md
│   │   ├── specs-status.md                # /specs-status — refresh the status dashboard in docs/specs/README.md and print it in chat
│   │   ├── scope-check.md                 # /scope-check — five forcing questions before /spec
│   │   ├── clarify.md                     # /clarify — interrogate a draft spec; writes answers back in
│   │   ├── adr.md                         # /adr <title> — create docs/adr/NNNN-<slug>.md (architecture decision record)
│   │   ├── plan.md                        # /plan — invoke planner subagent
│   │   ├── test-first.md                  # /test-first — invoke test-first subagent
│   │   ├── analyze.md                     # /analyze — read-only spec ↔ tests ↔ diff consistency check
│   │   ├── review-check.md                # /review-check — local gate before /review
│   │   ├── review.md                      # /review — invoke reviewer subagent
│   │   ├── review-adversarial.md          # /review-adversarial — invoke reviewer-adversarial
│   │   ├── security.md                    # /security — invoke security-reviewer (if installed)
│   │   ├── performance.md                 # /performance — invoke performance-reviewer (if installed)
│   │   ├── eval.md                        # /eval — author/run an LLM-feature eval suite (if evaluator installed)
│   │   └── delegate.md                    # /delegate — build a handoff packet for a weaker/local executor model
│   └── skills/
│       ├── python-module-split/
│       │   └── SKILL.md                   # Auto-invoked when a .py file ≥ 300 lines
│       ├── python-docstrings/
│       │   └── SKILL.md                   # Auto-invoked on new public symbols
│       └── dependency-hygiene/
│           └── SKILL.md                   # Auto-invoked when pyproject.toml adds a dep
├── .codex/
│   ├── config.toml                        # instruction budget, status line, multi-agent, hooks, secret-denying permission profile
│   ├── hooks.json                         # Codex lifecycle wiring to .agentic/hooks/
│   ├── rules/safety.rules                 # commit/push approval + destructive-command policy
│   └── agents/                            # Codex custom-agent TOML (optional roles stay opt-in)
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                         # CI gate: ruff + mypy + pytest + pip-audit (supply-chain gate) on every PR
│   │   └── claude-review.yml.example      # Opt-in Claude PR review (inert until renamed; bills an API key)
│   ├── dependabot.yml                     # weekly dependency + actions update PRs (uv + github-actions)
│   ├── ISSUE_TEMPLATE/
│   │   ├── feature.yml                    # feature issue form; fields feed the spec
│   │   └── bug.yml                        # bug issue form
│   └── pull_request_template.md           # PR body (carries Closes #N in issue mode)
├── docs/
│   ├── project-types.md                   # Orientation: flavors, profiles, capability matrix, when to use each agent/skill (managed; all profiles)
│   ├── codex-cli.md                       # Codex startup, trust, workflow mapping, switching, and exec usage
│   ├── agent-handoff.md                   # Operational runbook (project-owned; current state, risks, rollback)
│   ├── workflow-diagram.md                # Visual map of the agentic loop (Mermaid; managed)
│   ├── parallel-agents.md                 # Degrees of autonomy, worktree parallelism, agent teams, completion ladder, unattended runs (managed)
│   ├── plugin-packaging.md                # Plugin/marketplace distribution path — documented, not yet adopted (managed)
│   ├── serena-setup.md                    # Optional serena MCP — install / verify / update / teardown (managed)
│   ├── evals.md                           # When to add evals (opt-in, LLM/AI-surface projects) + how to keep them honest (managed)
│   ├── llm-product.md                     # Building an LLM/agent surface: call seam, testing without live calls, prompt versioning, model pinning (managed)
│   ├── local-executor.md                  # Delegating the implement phase to a weaker/local model: the rule, the tiers, what breaks (managed)
│   ├── adr/
│   │   └── README.md                      # Architecture Decision Records: spec-vs-ADR, numbering, status, template (managed)
│   └── specs/
│       └── README.md                      # Spec numbering, status vocabulary, optional sections
├── subdir-AGENTS.md.example               # Per-area Codex instruction template
└── subdir-CLAUDE.md.example               # One-line import of nearby AGENTS.md
                                            # (the pair is copied manually, not by bootstrap)
```

## Prerequisites

- [`ripgrep`](https://github.com/BurntSushi/ripgrep) (`rg`) — used by the
  placeholder walk, the `.env` leak check, and the agent's own searches:
  `brew install ripgrep`. Claude Code ships a bundled `rg` inside its
  shell, so it always works there; a plain terminal needs the real
  binary. `bootstrap.sh` warns if `rg` is missing, but the copy itself
  continues; install it before the placeholder and public-hygiene checks.
- `uv`, `git`, and (for PRs/issues) the `gh` CLI.

## How to use

```bash
cd your-project
bash path/to/agentic-scaffold/python/bootstrap.sh              # default: --python-core
bash path/to/agentic-scaffold/python/bootstrap.sh --minimal    # thinner starter
bash path/to/agentic-scaffold/python/bootstrap.sh --full       # full doctrine/docs surface
```

The script copies the file set selected by the profile table below;
within that selected set it excludes this index README, itself, and the
two `subdir-*.md.example` files. `README.md.template` is laid down as the
project's `README.md` (suffix dropped). On a first run, existing files
are skipped, not overwritten. Re-run with `--update` and the desired
profile/options to refresh the matching managed scaffolding. Project-owned
files are preserved; the one narrow exception is the marked generated
standing-rules block in canonical `AGENTS.md`, which refreshes without
touching customized content outside its markers. `CLAUDE.md` imports it
with `@AGENTS.md`, so there is no second policy copy to maintain.

### Install profiles

For the decision trees, the full capability matrix, and "when do I run each
agent / skill / command", see [`docs/project-types.md`](docs/project-types.md)
(copied into every project). Quick summary:

| Profile | What it is for | Copies by default |
| --- | --- | --- |
| `--minimal` | Small repos that want the core loop without the full doctrine surface | `AGENTS.md` + `CLAUDE.md`, `WORKFLOW.md`, pyproject, pre-commit, CI, shared format/safety hooks, Codex config/rules, specs convention, core Claude commands + Codex skills, and both clients' agents |
| `--python-core` (default) | Normal attended Python agentic workflow | Minimal + skills, status dashboard, ADRs, product/scope/clarify/analyze/review-adversarial commands, workflow diagram, Dependabot |
| `--full` | The author's full workflow bundle | Python-core + advanced docs (`parallel-agents`, plugin packaging, serena, evals, llm-product, local-executor), opt-in reviewer command stubs, `/delegate`, and the inert Claude PR-review workflow example |

Options compose with profiles:

- The Stop hook (`gate-on-stop.sh`), which blocks turn-end while the
  local gate is red, is wired **by default** in every profile;
  `--no-stop-gate` removes it.
- `--strict-hooks` rewrites Claude and Codex hook wiring so edits run
  `ruff format`, `ruff check`, and `mypy`. Without it,
  Edit/Write formats only; `/review-check` and CI remain the hard gates.
- `--advanced-docs` copies the advanced docs without using the full
  profile.

After bootstrap:

0. **Read [`WORKFLOW.md`](WORKFLOW.md)** — the human-facing
   walkthrough: day-zero setup and the per-feature loop as numbered
   steps. Copied into every new project; this is the entry point for
   understanding the methodology.
1. Replace placeholders: `rg '\{\{' .` — including the new `README.md`.
   Keep its **Acknowledgements** section (the single AI-attribution
   surface); don't move that attribution into commits or per-file
   notices.
2. Walk the rest of [`../new-project-checklist.md`](../new-project-checklist.md)
   — GitHub About sidebar, identity check, the private→public scrub.
3. `uv sync && uv run pre-commit install` — installs both the
   `pre-commit` and `commit-msg` hook types (the latter runs
   `strip-ai-attribution.sh`, which drops AI co-author trailers and
   generated-by-client footers that slip into a commit message).
4. **Codex:** start `codex`, accept the normal project trust review, then
   run `/hooks` to review and trust the checked-in hook definitions.
   Run `/skills` to inspect workflows. See
   [`docs/codex-cli.md`](docs/codex-cli.md).
5. Issue mode only (opt-in — see `docs/specs/README.md`): create the
   labels the issue forms reference (`feature`, `bug`, `spec-needed`,
   `triage`) so `.github/ISSUE_TEMPLATE/` resolves them — e.g.
   `gh label create spec-needed`. The default local mode needs no
   GitHub setup.
6. Write your first spec: `docs/specs/0001-<feature>.md`
7. For per-subdirectory rules, copy the canonical file and its import shim:
   ```bash
   cp subdir-AGENTS.md.example src/<area>/AGENTS.md
   cp subdir-CLAUDE.md.example src/<area>/CLAUDE.md
   ```
   Edit heavily; nested instructions should contain only rules specific to
   that area. Claude discovers them when it reads that area. Codex builds
   its instruction chain only at launch, so use `codex --cd src/<area>`
   when the nested rules are needed. Keep critical repository-wide rules in
   the root contract.
8. **If this project has a network surface, auth, or processes untrusted
   input** — add the opt-in security-reviewer:
   ```
   cp path/to/agentic-scaffold/python/.claude/agents/optional/security-reviewer.md \
      .claude/agents/security-reviewer.md
   cp path/to/agentic-scaffold/python/.codex/agents/optional/security-reviewer.toml \
      .codex/agents/security-reviewer.toml
   ```
   See the [opt-in subagents](#opt-in-subagents) section below for what
   triggers a "yes" on this question.
9. **If this project has a hot path, async code, or runs under load** —
   add the opt-in performance-reviewer:
   ```
   cp path/to/agentic-scaffold/python/.claude/agents/optional/performance-reviewer.md \
      .claude/agents/performance-reviewer.md
   cp path/to/agentic-scaffold/python/.codex/agents/optional/performance-reviewer.toml \
      .codex/agents/performance-reviewer.toml
   ```
   See the [opt-in subagents](#opt-in-subagents) section below for the
   trigger list.
10. **If the product itself contains an LLM/AI surface** (summarizer, RAG
   answer, chatbot, agent trajectory, NL classifier) — add the opt-in
   evaluator:
   ```
   cp path/to/agentic-scaffold/python/.claude/agents/optional/evaluator.md \
      .claude/agents/evaluator.md
   cp path/to/agentic-scaffold/python/.codex/agents/optional/evaluator.toml \
      .codex/agents/evaluator.toml
   ```
   Most projects ship no LLM surface and skip this. `docs/evals.md` is the
   decision rule and the discipline that keeps evals from grading
   themselves.

## The agentic loop this scaffolding enables

[`docs/workflow-diagram.md`](docs/workflow-diagram.md) draws this whole
section as Mermaid diagrams (day zero, the per-feature loop, the automation
layer); [`docs/project-types.md`](docs/project-types.md) maps each profile
to the pieces below. `Spec → Plan → Test-first → Implement → Verify`, where:

The table uses Claude's `/<name>` notation. In Codex, use the same workflow
as `$<name>`; for example, `/plan` maps to `$plan`.

| Phase | Driven by | Workflow entry |
| --- | --- | --- |
| Product spec (optional, project-level, once) | Agent interviews you (seven questions) and writes `docs/specs/0000-product.md` — the PRD-level layer feature specs link up to | `/product-spec [name]` |
| Scope check (optional pre-spec) | You answer five forcing questions; output feeds the spec | `/scope-check <desc>` |
| Spec | You write `docs/specs/NNNN-<feature>.md`, or `/spec` drafts it from the current discussion; you then review and edit | `/spec <name>` |
| Clarify (optional post-draft) | Agent interrogates the draft spec's underspecified areas (max 5 questions), writes answers back into the spec | `/clarify [spec-path]` |
| Architecture decision (Large / cross-cutting work) | You write `docs/adr/NNNN-<slug>.md` (independent numbering), or `/adr` drafts it from the current discussion; you then review and edit the rationale | `/adr <title>` |
| Branch | Main session creates `spec-NNNN-<slug>` (or `<type>/<slug>`; `<issue#>-<slug>` in issue mode) automatically — see the `AGENTS.md` Git workflow rule | — |
| Plan | `planner` subagent (Claude Markdown / Codex TOML adapters) | `/plan [spec-path]` |
| Test-first | `test-first` subagent (Claude Markdown / Codex TOML adapters) | `/test-first [spec-path]` |
| Analyze (optional consistency check) | Fresh read-only `analyzer` cross-check: every success criterion covered by a test, no undeclared scope, standing rules honored | `/analyze [spec-path]` |
| Implement | Main client session (`AGENTS.md`; Claude imports it through `CLAUDE.md`) | — |
| Per-edit quality | Client PostToolUse wiring calls `.agentic/hooks/format-after-edit.sh`; `--strict-hooks` also runs ruff check + mypy | — |
| Local quality gate (pre-review) | ruff lint + format + mypy + pytest, refuses pass on failure | `/review-check` |
| Turn-end gate (default; `--no-stop-gate` removes it) | Shared Stop hook (`.agentic/hooks/gate-on-stop.sh`) blocks finishing a turn while ruff/mypy/pytest are red and `src/` has pending changes | — |
| Verify (collaborative) | `reviewer` subagent; default includes committed, staged, unstaged, and untracked work | `/review [spec-path] [<base>..<head> for historical review]` |
| Verify (adversarial — pair with `/review` on meaningful PRs) | `reviewer-adversarial` on the same complete change set | `/review-adversarial [spec-path] [<base>..<head>]` |
| Verify (security) | `security-reviewer` (opt-in subagent) | `/security [spec-path] [<base>..<head>]` |
| Verify (performance) | `performance-reviewer` (opt-in subagent) | `/performance [spec-path] [<base>..<head>]` |
| Verify (evals — LLM/AI-surface projects only) | `evaluator` (opt-in subagent) judges non-deterministic output quality against a rubric; most projects skip it | `/eval [spec-path]` |
| CI gate (every PR) | GitHub Actions runs ruff + mypy + pytest — the non-skippable backstop | `.github/workflows/ci.yml` |
| Public-repo hygiene (every PR) | CI runs the non-quality pre-commit hooks over the full tree: secret/key, YAML/TOML, merge-marker, large-file, and client-contract checks | `.github/workflows/ci.yml` |
| Supply-chain gate (every PR) | A second CI job runs `pip-audit` on the locked dep tree; Dependabot opens the weekly fix PRs | `.github/workflows/ci.yml` · `.github/dependabot.yml` |
| Status overview (any time) | Live dashboard in `docs/specs/README.md` (struck-through = shipped/abandoned/superseded), auto-refreshed by the `specs-status.sh` hook on every spec change; `/specs-status` forces a refresh and prints the table in chat | `/specs-status [filter]` |

On multi-day features, append a `## Phase handoff` section to the spec
at phase boundaries and run `/clear` between phases — see
[`WORKFLOW.md`](WORKFLOW.md) "Phase handoff" and
[`docs/specs/README.md`](docs/specs/README.md) "Optional sections."

Auto-invoked side-skills (load on demand based on what's happening in
the diff):

- `python-module-split` — fires when a `.py` file approaches 300 lines.
- `python-docstrings` — fires when a new public function, class, or
  module is added or touched without a compliant Google-style docstring.
- `dependency-hygiene` — fires when `pyproject.toml` adds a new dep;
  surfaces a check (maintenance, license, advisories, stdlib alternative)
  before the dep lands.

The complete `AGENTS.md` contract is the glue. `CLAUDE.md` imports it, so
both clients receive the same orchestration rules without duplicate policy.
Shared sources under `workflow/` render Claude commands/agents/skills and
Codex skills/custom agents; `scripts/validate-codex-adapters.sh` rejects
drift and stale adapters.
See [`docs/codex-cli.md`](docs/codex-cli.md) for startup, trust, switching,
and `codex exec`.

## Issue mode (opt-in)

The default workflow is local: specs are numbered from the highest
existing `docs/specs/NNNN-*.md` + 1, branches are `spec-NNNN-<slug>` or
`<type>/<slug>`, and PR closing keywords are omitted — no GitHub
issue/forms/labels setup needed. For a team repo, or when you want the
backlog tracked as GitHub issues, opt into issue mode: the issue number,
spec number, branch, and PR then all share one identifier
(`<issue#>-<slug>` branches, `Closes #N` in the PR body). Document the
choice in `AGENTS.md` so the spec workflow looks up the issue instead of taking
the next local number.

## Opt-in subagents

Both `.claude/agents/optional/` and `.codex/agents/optional/` hold adapters
that are **not** copied by the default bootstrap. Enable both client files
when the role applies.

### `security-reviewer.md`

Application-security review of a diff. Distinct from the general
`reviewer` — focuses only on security-relevant findings (injection,
deserialization, auth/authz, crypto, path/file, SSRF, logging, secrets
in code, and — when the product calls a model — the LLM surface: prompt
injection, model output as untrusted input, tool-call authorization).
Output is structured like a pentest finding list (severity,
category, location, evidence, why-it-matters, suggested fix). Manual
review only — no `pip-audit` / `bandit` / `semgrep` shell-outs.

**Copy it in when the project has any of:**

- A network surface (HTTP server, MCP server with off-loopback bind,
  websocket, raw socket).
- Authentication or authorization logic.
- Processes untrusted input (user-supplied files, HTTP bodies,
  third-party API responses that pass through to internal use).
- Handles secrets — fetches, stores, rotates, or routes them.
- Deserializes external data (pickle, yaml, xml, jwt, custom binary).
- Calls an LLM — prompts assembled from untrusted content, or model
  output feeding tools, shell, SQL, or file paths (see
  `docs/llm-product.md`).

To enable for a project:

```bash
cp path/to/agentic-scaffold/python/.claude/agents/optional/security-reviewer.md \
   .claude/agents/security-reviewer.md
cp path/to/agentic-scaffold/python/.codex/agents/optional/security-reviewer.toml \
   .codex/agents/security-reviewer.toml
```

Then add a one-line mention in `AGENTS.md`; Claude receives it through the
existing import.

### `performance-reviewer.md`

Performance review of a diff. Distinct from the general `reviewer` and
the `security-reviewer` — focuses only on perf-relevant findings (N+1
queries, accidental O(n²), sync I/O in async, missing pagination,
allocation churn, migration-locking patterns). Output is the same
Ghostwriter-style finding list. Recommends profiling commands (`py-spy`,
`scalene`, `pytest-benchmark`, `EXPLAIN ANALYZE`) per finding — the
human runs them.

**Copy it in when the project has any of:**

- A hot path (request handler, background worker that processes large
  batches, a CLI that runs over user-sized inputs).
- DB queries on tables that grow without bound, or any query in a loop.
- Async code (where sync I/O inside `async def` is a real footgun).
- Migrations against tables larger than a few thousand rows.
- Anything that runs under load or has a latency SLO.

To enable for a project:

```bash
cp path/to/agentic-scaffold/python/.claude/agents/optional/performance-reviewer.md \
   .claude/agents/performance-reviewer.md
cp path/to/agentic-scaffold/python/.codex/agents/optional/performance-reviewer.toml \
   .codex/agents/performance-reviewer.toml
```

Then add a one-line mention in `AGENTS.md`; Claude receives it through the
existing import.

### `evaluator.md`

The quality counterpart to `test-first`, for the subset of projects whose
*product* contains an LLM/AI surface. Tests assert deterministic behavior;
the `evaluator` authors and runs **evals** that judge non-deterministic
output quality against a rubric (task success, tool-use quality, trajectory
compliance, hallucination rate, response quality). It authors cases from
the spec (never the implementation), keeps the rubric, inputs, and ground
truth external, and runs the LM-judge pass independent of the generator —
so an eval measures correctness, not the model's agreement with itself.
Driven by `/eval`; full doctrine and the decision rule live in
`docs/evals.md`.

**Copy it in only when the product itself contains an LLM/AI surface:**

- A text-generating feature whose output varies run to run (summarizer,
  rewriter, chatbot).
- A RAG / retrieval-grounded answerer where faithfulness to the source
  matters.
- An agent whose tool-use trajectory or task completion is the thing under
  test.
- An LLM classifier / extractor over natural-language input.

A deterministic CLI, library, or IaC/homelab tool needs none of this —
tests suffice. This is the most-skipped opt-in of the three.

The evaluator judges the LLM surface; `docs/llm-product.md` (installed
with `--full` / `--advanced-docs`) covers building it — the single call
seam, testing without live API calls, prompt versioning, model pinning,
and when the surface also trips the `security-reviewer` opt-in.

To enable for a project:

```bash
cp path/to/agentic-scaffold/python/.claude/agents/optional/evaluator.md \
   .claude/agents/evaluator.md
cp path/to/agentic-scaffold/python/.codex/agents/optional/evaluator.toml \
   .codex/agents/evaluator.toml
```

Then add a one-line mention in `AGENTS.md`; Claude receives it through the
existing import.

## Don't

- Don't keep `{{PLACEHOLDER}}` strings in a committed file. A project contract
  that still says `Project: {{PROJECT_NAME}}` is worse than no CLAUDE.md.
- Don't blanket-copy the `subdir-*.md.example` pair into every directory —
  use it where per-area conventions differ from the root. Keep policy in
  the nested `AGENTS.md`; leave the paired `CLAUDE.md` as its import shim.
- Don't paste these templates into a chat, ask an agent to "regenerate them
  for my project," and commit what comes back unread. How you draft is your
  call — by hand, with an agent, or both. What matters is that you own every
  line that lands, and that you keep it short.

  The one controlled evaluation of repository context files measured
  agent-generated files at 0.5–2% *below* no context file at all and
  developer-written ones at 2.4% above — neither difference statistically
  significant, so read the direction as weak evidence, not a result. What
  did reach significance: developer-written files beat agent-generated
  ones, and context files raise inference cost either way (20–23% for
  agent-generated, up to 19% for developer-written) because the agent
  reads them, tests more, and explores more.

  Note what those two conditions were: a file the agent generated on its
  own, versus one a developer had committed. Nobody measured the middle —
  an agent drafting and a human cutting it down. That is untested ground,
  not endorsed ground, so the rule is about ownership, not authorship.

  The finding worth designing around is that repository *overviews* did
  not help. The paper concludes context files are useful for specifying
  non-standard practices — so a context file earns its cost by stating
  what this repo does *differently*, not by describing it. File length
  itself showed no significant effect on success; keep it short because
  every line is billed on every turn, not because short scores better.

  The floor is set by enforcement, not by taste: the contract is the only
  channel Codex has for the standing rules, so it cannot shrink below them.
  Everything above that floor should have to fight for its place.

  Source: Gloaguen, Mündler, Müller, Raychev, Vechev, "Evaluating
  AGENTS.md: Are Repository-Level Context Files Helpful for Coding
  Agents?", arXiv:2602.11988v2 (2026-06-23),
  <https://arxiv.org/abs/2602.11988> — retrieved 2026-07-22.
