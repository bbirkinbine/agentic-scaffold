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
├── CLAUDE.md                              # project-root context for Claude Code
├── AGENTS.md                              # portable stub for non-Claude agents; points at CLAUDE.md
├── WORKFLOW.md                            # human-facing loop walkthrough (start here)
├── pyproject.toml                         # uv + ruff + mypy + pytest config
├── .gitignore                             # Python ignores, incl. .env* (.env.*.example kept)
├── .pre-commit-config.yaml                # no-commit-to-main + secret scan + ruff + mypy + commit-msg AI-attribution strip
├── .claude/
│   ├── settings.json                      # SessionStart branch check + PreToolUse deny-list + PostToolUse ruff/mypy + PreCompact preserve-context + Stop gate
│   ├── hooks/
│   │   ├── branch-check.sh                # SessionStart: warn when a session opens on main
│   │   ├── block-destructive.sh           # PreToolUse: block unrecoverable cmds (rm -rf /, git clean -fd, mkfs, dd, terraform destroy, etc.)
│   │   ├── gate-on-stop.sh                # Stop: block turn-end while ruff/mypy/pytest are red and src/ has pending changes (8-block cap applies)
│   │   ├── specs-status.sh                # PostToolUse: regenerate the status dashboard in docs/specs/README.md when a spec changes
│   │   └── strip-ai-attribution.sh        # pre-commit commit-msg hook: strip Co-Authored-By: Claude trailers + generated-with footers
│   ├── rules/
│   │   ├── git-workflow.md                # Branch-per-change, naming, PR conventions (always loaded)
│   │   ├── commit-style.md                # Commit style + mistakes-feed-back-into-rules (always loaded)
│   │   ├── public-repo-hygiene.md         # Secrets / public-surface rules (always loaded)
│   │   ├── python-code.md                 # Python conventions + external-reference provenance (path-scoped to src/**, tests/**)
│   │   └── agent-legible-code.md          # Write code agents can verify (path-scoped to src/**)
│   ├── agents/
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
│   │   ├── plan.md                        # /plan — invoke planner subagent
│   │   ├── test-first.md                  # /test-first — invoke test-first subagent
│   │   ├── analyze.md                     # /analyze — read-only spec ↔ tests ↔ diff consistency check
│   │   ├── review-check.md                # /review-check — local gate before /review
│   │   ├── review.md                      # /review — invoke reviewer subagent
│   │   ├── review-adversarial.md          # /review-adversarial — invoke reviewer-adversarial
│   │   ├── security.md                    # /security — invoke security-reviewer (if installed)
│   │   ├── performance.md                 # /performance — invoke performance-reviewer (if installed)
│   │   └── eval.md                        # /eval — author/run an LLM-feature eval suite (if evaluator installed)
│   └── skills/
│       ├── python-module-split/
│       │   └── SKILL.md                   # Auto-invoked when a .py file ≥ 300 lines
│       ├── python-docstrings/
│       │   └── SKILL.md                   # Auto-invoked on new public symbols
│       └── dependency-hygiene/
│           └── SKILL.md                   # Auto-invoked when pyproject.toml adds a dep
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                         # CI gate: ruff + mypy + pytest on every PR
│   │   └── claude-review.yml.example      # Opt-in Claude PR review (inert until renamed; bills an API key)
│   ├── ISSUE_TEMPLATE/
│   │   ├── feature.yml                    # feature issue form; fields feed the spec
│   │   └── bug.yml                        # bug issue form
│   └── pull_request_template.md           # PR body carrying the Closes #N line
├── docs/
│   ├── agent-handoff.md                   # Operational runbook (project-owned; current state, risks, rollback)
│   ├── workflow-diagram.md                # Visual map of the agentic loop (Mermaid; managed)
│   ├── parallel-agents.md                 # Degrees of autonomy, worktree parallelism, agent teams, completion ladder, unattended runs (managed)
│   ├── plugin-packaging.md                # Plugin/marketplace distribution path — documented, not yet adopted (managed)
│   ├── serena-setup.md                    # Optional serena MCP — install / verify / update / teardown (managed)
│   ├── evals.md                           # When to add evals (opt-in, LLM/AI-surface projects) + how to keep them honest (managed)
│   └── specs/
│       └── README.md                      # Spec numbering, status vocabulary, optional sections
└── subdir-CLAUDE.md.example               # Per-area CLAUDE.md template
                                            # (copied manually, not by bootstrap)
```

## Prerequisites

- [`ripgrep`](https://github.com/BurntSushi/ripgrep) (`rg`) — used by the
  placeholder walk, the `.env` leak check, and the agent's own searches:
  `brew install ripgrep`. Claude Code ships a bundled `rg` inside its
  shell, so it always works there; a plain terminal needs the real
  binary. `bootstrap.sh` hard-fails early if `rg` is missing.
- `uv`, `git`, and (for PRs/issues) the `gh` CLI.

## How to use

```bash
cd your-project
bash path/to/agentic-scaffold/python/bootstrap.sh
```

The script copies everything except this index README, itself, and
`subdir-CLAUDE.md.example`. `README.md.template` is laid down as the
project's `README.md` (suffix dropped). On a first run, existing files
are skipped, not overwritten. Re-run with `--update` to refresh the
managed scaffolding (everything except the project-owned `CLAUDE.md`,
`README.md`, `pyproject.toml`, and `.gitignore`) to the current
template.

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
   `strip-ai-attribution.sh`, which drops any `Co-Authored-By: Claude`
   trailer or "Generated with Claude Code" footer that slips into a
   commit message).
4. Create the GitHub issue labels the issue forms reference (`feature`,
   `bug`, `spec-needed`, `triage`) so `.github/ISSUE_TEMPLATE/` resolves
   them — e.g. `gh label create spec-needed`.
5. Write your first spec: `docs/specs/0001-<feature>.md`
6. For per-subdirectory rules: `cp subdir-CLAUDE.md.example src/<area>/CLAUDE.md`
   and edit heavily.
7. **If this project has a network surface, auth, or processes untrusted
   input** — add the opt-in security-reviewer:
   ```
   cp path/to/agentic-scaffold/python/.claude/agents/optional/security-reviewer.md \
      .claude/agents/security-reviewer.md
   ```
   See the [opt-in subagents](#opt-in-subagents) section below for what
   triggers a "yes" on this question.
8. **If this project has a hot path, async code, or runs under load** —
   add the opt-in performance-reviewer:
   ```
   cp path/to/agentic-scaffold/python/.claude/agents/optional/performance-reviewer.md \
      .claude/agents/performance-reviewer.md
   ```
   See the [opt-in subagents](#opt-in-subagents) section below for the
   trigger list.
9. **If the product itself contains an LLM/AI surface** (summarizer, RAG
   answer, chatbot, agent trajectory, NL classifier) — add the opt-in
   evaluator:
   ```
   cp path/to/agentic-scaffold/python/.claude/agents/optional/evaluator.md \
      .claude/agents/evaluator.md
   ```
   Most projects ship no LLM surface and skip this. `docs/evals.md` is the
   decision rule and the discipline that keeps evals from grading
   themselves.

## The agentic loop this scaffolding enables

`Spec → Plan → Test-first → Implement → Verify`, where:

| Phase | Driven by | Slash command |
| --- | --- | --- |
| Product spec (optional, project-level, once) | Agent interviews you (seven questions) and writes `docs/specs/0000-product.md` — the PRD-level layer feature specs link up to | `/product-spec [name]` |
| Scope check (optional pre-spec) | You answer five forcing questions; output feeds the spec | `/scope-check <desc>` |
| Spec | You write `docs/specs/NNNN-<feature>.md` (seeded with status header) | `/spec <name>` |
| Clarify (optional post-draft) | Agent interrogates the draft spec's underspecified areas (max 5 questions), writes answers back into the spec | `/clarify [spec-path]` |
| Branch | Main session creates `<issue#>-<slug>` (or `<type>/<slug>`) automatically — see `.claude/rules/git-workflow.md` | — |
| Plan | `planner` subagent (`.claude/agents/planner.md`) | `/plan [spec-path]` |
| Test-first | `test-first` subagent (`.claude/agents/test-first.md`) | `/test-first [spec-path]` |
| Analyze (optional consistency check) | Read-only cross-check: every success criterion covered by a test, no undeclared scope, standing rules honored | `/analyze [spec-path]` |
| Implement | Main Claude session (CLAUDE.md + `.claude/rules/` tell it the rules) | — |
| Per-edit quality | PostToolUse hook (`.claude/settings.json`) runs ruff format + ruff check + mypy on every Edit/Write | — |
| Local quality gate (pre-review) | ruff lint + format + mypy + pytest, refuses pass on failure | `/review-check` |
| Turn-end gate (automatic) | Stop hook (`.claude/hooks/gate-on-stop.sh`) blocks finishing a turn while ruff/mypy/pytest are red and `src/` has pending changes — `/review-check` made mechanical | — |
| Verify (collaborative) | `reviewer` subagent (`.claude/agents/reviewer.md`) | `/review [<base>..<head>]` |
| Verify (adversarial — pair with `/review` on meaningful PRs) | `reviewer-adversarial` subagent (`.claude/agents/reviewer-adversarial.md`) | `/review-adversarial [<base>..<head>]` |
| Verify (security) | `security-reviewer` (opt-in subagent) | `/security [<base>..<head>]` |
| Verify (performance) | `performance-reviewer` (opt-in subagent) | `/performance [<base>..<head>]` |
| Verify (evals — LLM/AI-surface projects only) | `evaluator` (opt-in subagent) judges non-deterministic output quality against a rubric; most projects skip it | `/eval [spec-path]` |
| CI gate (every PR) | GitHub Actions runs ruff + mypy + pytest — the non-skippable backstop | `.github/workflows/ci.yml` |
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

`CLAUDE.md` is the glue — its "Workflow expectations" section tells
Claude to route to each subagent based on task size (> 3 files: planner;
tests first: test-first; before commit: reviewer; > 5 files: stop and
ask). The slash commands above are the one-keystroke way to invoke each
phase explicitly when the agent doesn't auto-route.

`AGENTS.md` is a portable stub sibling of `CLAUDE.md` — non-Claude
agents (Codex, Cursor, Gemini) that look for that filename by
convention find a pointer back to `CLAUDE.md`. `CLAUDE.md` stays the
source of truth. For a repo that non-Claude agents work regularly, the
stub can be inverted into a symlink (`ln -sf AGENTS.md CLAUDE.md` after
moving the content) — one file, both filenames; see the note inside
`AGENTS.md`.

Standing rules beyond `CLAUDE.md` live in `.claude/rules/` — rules
without `paths` frontmatter (git workflow, commit style, hygiene) load
every session; path-scoped rules (Python conventions, agent-legible
code) load when matching files are touched. This keeps `CLAUDE.md`
itself short enough to be read rather than skimmed; the sizing research
this follows says a bloated root context file gets ignored.

## Opt-in subagents

`.claude/agents/optional/` holds subagents that are **not** copied by the
default bootstrap. Each is intended for projects where the cost of having
that subagent invoked routinely is worth it.

### `security-reviewer.md`

Application-security review of a diff. Distinct from the general
`reviewer` — focuses only on security-relevant findings (injection,
deserialization, auth/authz, crypto, path/file, SSRF, logging, secrets
in code). Output is structured like a pentest finding list (severity,
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

To enable for a project:

```bash
cp path/to/agentic-scaffold/python/.claude/agents/optional/security-reviewer.md \
   .claude/agents/security-reviewer.md
```

Then add a one-line mention in your `CLAUDE.md` "Subagents" section so
Claude knows to invoke it before commits that touch a sensitive area.

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
```

Then add a one-line mention in your `CLAUDE.md` "Subagents" section.

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

To enable for a project:

```bash
cp path/to/agentic-scaffold/python/.claude/agents/optional/evaluator.md \
   .claude/agents/evaluator.md
```

Then add a one-line mention in your `CLAUDE.md` "Subagents" section.

## Don't

- Don't keep `{{PLACEHOLDER}}` strings in a committed file. A `CLAUDE.md`
  that still says `Project: {{PROJECT_NAME}}` is worse than no CLAUDE.md.
- Don't blanket-copy `subdir-CLAUDE.md.example` into every directory —
  use it where per-area conventions differ from the root.
- Don't paste these templates into a chat and ask Claude to "regenerate
  them for my project." Hand-edit. LLM-generated context files have been
  measured to *reduce* agent performance (Gloaguen et al., 2026).
