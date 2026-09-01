# Influences

Where the ideas in this scaffold came from.

## Why this file exists

The scaffold requires every spec that cites an outside authority to declare
it — source, URL, retrieval date, license — and both reviewer agents treat an
undeclared authority as a finding
([`python/docs/specs/README.md`](../python/docs/specs/README.md) →
"External references";
[`python/workflow/rules/python-code.md`](../python/workflow/rules/python-code.md)
→ "External-reference provenance").

That rule governed the specs written *with* the scaffold, but never the
scaffold's own design. Several features here were taken from other people's
work and credited only in a commit message, or nowhere. This file closes that
gap and holds the scaffold to the standard it sets.

## Provenance of this file

The links below were captured in the author's research notes over
2026-05 to 2026-07 and transcribed here on 2026-07-22. They were **not**
re-fetched when this file was written, so treat them as recorded-at-the-time
rather than verified-today. Entries with no recorded URL say so rather than
carry a reconstructed one. Rows added after that transcription carry their own
retrieval date and were read at the source when added.

Everything here is a **pattern-level borrowing** — a workflow idea, a prompt
shape, a section convention. No source's code, prompt text, or documentation
was copied into this repo, so no upstream license attaches to these files.
Where that ever stops being true, the copying rule in
`python/docs/specs/README.md` applies and the license goes in the header of
the file that carries the copied content.

## Borrowed features

Five features came from a 2026-05 audit of the spec-driven-framework field.
All five shipped. They predate this repo's split from the `dotfiles` repo on
2026-06-09, so they arrive in this log inside the initial import (`15557dd`);
pre-move history is in that repo.

| Feature here | Idea | Source |
| --- | --- | --- |
| `reviewer-adversarial` + `/review-adversarial` | Adversarial review as a second, hostile pass over the same diff | [garrytan/gstack](https://github.com/garrytan/gstack) |
| `/scope-check` — forcing questions before `/spec` | An interrogation pass that refuses to let a fuzzy goal through | [garrytan/gstack](https://github.com/garrytan/gstack) |
| `## Phase handoff` + the `/clear` discipline | Per-phase context reset, with state handed off in a file | [gsd-build/get-shit-done](https://github.com/gsd-build/get-shit-done) |
| `## Implementation Notes` in specs | Living-spec sync — keeping the design log honest about what shipped | [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) |
| Complete `AGENTS.md` contracts across both scaffold flavors | A vendor-neutral context file other agents look for by convention | [agents.md](https://agents.md/) |

The OpenSpec borrow is deliberately partial: the section convention was taken,
the framework's full living-spec maintenance burden was not.

## Research and reports behind specific rules

| Rule here | Source |
| --- | --- |
| Files ≤ 300 lines; subagents for verbose work; the context-budget guidance in `WORKFLOW.md` → "Session hygiene" | [Context Rot — Chroma](https://research.trychroma.com/context-rot) (U-shaped recall measured across 18 frontier models) |
| `permissions.deny` on `.env` and key material; the status line; `CLAUDE.local.md` overlays; "Session hygiene" | Gui Ferreira, Claude Code talk, NDC AI 2026 — <https://youtu.be/zaDbZt40kRg> (commit `4657fce`) |
| The two senses of "eval", and the opt-in `evaluator` + `/eval` layer | Google/Kaggle, *The New SDLC with Vibe Coding* (2026) — [PDF](https://drive.google.com/file/d/1IR7CddF_2FyQo_PdfBNTaEA50EGiVt2r/view) (commit `b0d490f`) |
| ADR section shape: Context / Decision / Consequences / Alternatives considered | Michael Nygard, *Documenting Architecture Decisions* — no URL recorded |
| "Delegate only where a machine can tell whether it succeeded", the three-tier verdict table, and the serialization-not-reasoning failure analysis in `python/docs/local-executor.md` | Terminal-Bench 2.0 agentic-coding leaderboard (open-weight vs. frontier scores), plus published harness tool-call serialization defects across Cline, Roo Code, OpenCode, the Qwen CLI, llama.cpp, and Ollama — **URLs and retrieval date not yet recorded; the leaderboard figures are live values and need a pinned source** |
| The loop's general shape and the test-first discipline | [Anthropic 2026 Agentic Coding Trends Report](https://resources.anthropic.com/hubfs/2026%20Agentic%20Coding%20Trends%20Report.pdf) · [Claude Code best practices](https://code.claude.com/docs/en/best-practices) |
| Own every line of the shared `AGENTS.md` contract rather than committing a generated one unread, and keep it short (`python/README.md` → "Don't") | Gloaguen, Mündler, Müller, Raychev, Vechev, "Evaluating AGENTS.md: Are Repository-Level Context Files Helpful for Coding Agents?", [arXiv:2602.11988v2](https://arxiv.org/abs/2602.11988) (2026-06-23), retrieved 2026-07-22 |
| Dual-client contract/adapters: complete `AGENTS.md`, repository skills, project custom agents, trusted hooks, permission profiles, command rules, and Codex TUI status line | Official Codex documentation for [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md), [skills](https://learn.chatgpt.com/docs/build-skills), [subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents), [hooks](https://learn.chatgpt.com/docs/hooks), [rules](https://learn.chatgpt.com/docs/agent-configuration/rules), and [configuration](https://learn.chatgpt.com/docs/config-reference), verified 2026-07-30 against Codex CLI 0.146.0 |
| One canonical `AGENTS.md`, imported by Claude instead of duplicated; read-only Claude reviewer/planner subagents | Official Claude Code documentation for [project memory and `AGENTS.md` imports](https://code.claude.com/docs/en/memory) and [subagent `permissionMode: plan`](https://code.claude.com/docs/en/sub-agents), verified 2026-07-30 against Claude Code 2.1.220 |
| Review findings as a trigger for `AGENTS.md` rules (`workflow/rules/commit-style.md` → "Mistakes feed back into the rules"); reviewers excluding mechanical findings the local gate and CI already enforce | Anthropic, *The AI-Native SDLC Playbook* — <https://claude.com/blog/the-ai-native-sdlc-playbook>, published 2026-08-21, retrieved 2026-09-01 |

### A tension, and how it was resolved

The AGENTS.md paper found that repository *overviews* did not improve task
success, and that context files add inference cost regardless of who wrote
them: 20–23% for agent-generated files and up to 19% for developer-written
ones. The scaffold's canonical `AGENTS.md` template opens with exactly such
an overview (project description, stack, how to run things), and the template
is not short.

Sharper still: developer-written context files improved results for every
agent the paper tested *except* Claude Code, which scored best on their
benchmark with no context file at all. This scaffold's premise is shipping a
durable agent contract to both Claude Code and Codex.

The counter-argument is that the paper measured single-issue SWE-bench-style
tasks with no human in the loop, while this scaffold targets multi-session
work where the same file also carries the workflow contract, the don't-touch
list, and hygiene rules — none of which that benchmark exercises. That is a
reasonable defence, not a measured one. Treat the template's length as an
open question rather than a settled decision, and prefer cutting — on cost
grounds, since the paper found file length itself had no significant effect
on success.

A second, independent source points the same way. Anthropic's *AI-Native
SDLC Playbook* (2026-08-21; retrieved 2026-09-01) states the context file
should be **one page maximum**, on the reasoning that stale or redundant
instruction wastes the context the session runs on.

Two sources arguing for a shorter contract did not settle what to cut, so on
2026-09-01 the contract was judged section by section against whether a
current model still needs to be told. The rendered `python/AGENTS.md` went
from 27,859 to 16,476 bytes, a 41% reduction. What left was the material a
session does not need in context in order to act: the rationale behind each
rule, worked examples, and enforcement backstory that `WORKFLOW.md`,
`python/README.md`, and `docs/specs/README.md` already carry and that the
contract points at. Every decision rule stayed, and the headings that the
commands and skills reference — `## Shared workflow protocols` and
`### Semantic change set` — were held stable. `generic/project-contract.md`
was already short and was left alone.

The remaining distance between 16 KB and "one page" is deliberate. This file
is not only a repository overview; it also carries the workflow contract, the
don't-touch list, and the hygiene rules, none of which the playbook's
one-page target accounts for. Both sources stay on record as the reason to
keep pressure on the length, not as a target already met.

## Considered and not adopted

Recording the rejections matters as much as the adoptions — it stops each one
being re-proposed.

- **spec-kit's explicit `/tasks` phase.** The planner's file-by-file output
  already covers it; a separate task-list artifact is one more thing to keep
  in sync. [github/spec-kit](https://github.com/github/spec-kit)
- **spec-kit's `checklist-template.md` primitive.** Overlaps the spec's
  success criteria without adding a check either reviewer would make.
- **Periodic re-evaluation of the framework category.** The 2026-05 audit
  concluded the category has converged and that further comparison shopping
  is low-value. Revisit only if something changes the loop itself, not the
  CLI around it.
- **A batch of anti-slop lint hardening** (complexity caps, blanket `T20`,
  a slop linter inside `/review-check`), reviewed 2026-07-16 and declined:
  checks an agent can satisfy without improving anything invite compliance
  theater and manufacture false confidence.
- **Most of the *AI-Native SDLC Playbook*** (2026-08-21; retrieved
  2026-09-01), reviewed against the scaffold and declined. Two of its practices
  landed (see the row above); the rest did not, for four distinct reasons:
  - *Roles this scaffold does not have.* `intent.md` as a pre-spec artifact
    exists to carry intent between an originator, a product owner, and an
    engineer. Here those are one person, and "discuss the feature, then
    `/spec`" already is that capture step. Likewise a root `REVIEW.md`
    review-policy file: review policy already lives in the reviewer role
    prompts, which render to both clients — a second home for it would be a
    second source of truth.
  - *Stages that presuppose a deployment target.* Stage 6 in full (control
    bands, `bands.yaml` response tiers, autonomous production monitoring,
    scheduled hosted scans, Claude on call via Slack) and Stage 5's
    per-environment autonomy tiers assume a running service and an
    organization around it. This scaffold bootstraps repositories and has no
    deploy target at all.
  - *Sound, but priced wrong for a solo project.* Eval suites that
    regression-test the agent configuration itself — 20–50 recorded tasks
    re-run whenever the contract, skills, or hooks change. This repo's smoke
    tests provide deterministic configuration and bootstrap coverage, while
    `scripts/acceptance-workflow-live.sh` provides a smaller opt-in live
    workflow check. It does not maintain the source's proposed agent-behavior
    eval suite. Shipping that into consumer projects would cost tokens on every
    configuration change to defend against a failure mode a solo author notices
    in the next session. Revisit if a consumer project ever runs unattended
    long enough that nobody would.
  - *Not evidentiable in this workflow.* A reviewer check for test assertions
    loosened, narrowed, deleted, or skipped after they first went red — the
    playbook's Stage 4 guard against implementation moving the goalposts
    instead of meeting them. It was drafted for both reviewer roles and
    withdrawn on review: the objection is evidentiary, not one of principle.
    The scaffold's `/test-first` phase produces no committed or otherwise
    durable red-state snapshot — the failing tests and the implementation
    arrive together in the single commit taken at the final checkpoint — so a
    read-only reviewer running `git log -p` over the test paths has nothing to
    compare against. It can still judge whether the tests cover the spec; it
    cannot establish *when* they changed. The playbook's version holds because
    it commits the failing test first and then freezes test edits behind a
    hook. Revisit only alongside one of those preconditions: an explicit
    red-state artifact or hash, a separately approved red-test commit, or a
    hook that freezes the relevant test paths during implementation.

## Corrections

- **Gloaguen et al., 2026** (resolved 2026-07-22). This citation sat in
  `python/README.md` for months as a bare "(Gloaguen et al., 2026)" with no
  title or URL, supporting the claim that LLM-generated context files
  "measurably reduce agent performance." The primary source was located and
  read: the claim was directionally right but overstated, and it omitted the
  study's more useful finding. Measured effects are small and, for both
  conditions, not statistically significant (agent-generated files 0.5–2%
  below no context file; developer-written 2.4% above), and the headline
  result is that context files add 20%+ inference cost while repository
  overviews do not help at all. All three call sites (`python/README.md`,
  `python/WORKFLOW.md`, `new-project-checklist.md`) now state the numbers
  and carry the full citation.

  Re-audited 2026-07-30 against the cited v2, which caught three errors in
  the correction itself: the "4% above" figure was v1's (v2 revises it to
  2.4%), "both adding 20%+ cost" was wrong for developer-written files
  (at most 19%), and the significance caveat was missing throughout. A
  fourth claim — that padding a context file "measured worse than keeping
  it minimal" — was not in the paper at all; it explicitly found file
  length had no significant effect on success. The shortness rule now
  rests on cost, which the paper does measure.

  The same pass relaxed the hand-edit rule. It had read "hand-edit —
  don't have the agent regenerate it," which overstated the evidence in
  the other direction: the study compared files an agent generated on its
  own against files a developer had committed, and never tested an agent
  drafting with a human cutting it down. Since that middle path is now
  the common way to work, the rule became one about ownership rather than
  authorship — draft it however you like, but read every line and own
  what lands. The measured failure mode was unreviewed generation, and
  that is what the rule still warns against.

  The lesson generalises twice over: a citation with no URL is a citation
  nobody checks, including its author — and adding the URL is only half
  the fix, because the numbers behind it still have to be read off the
  version you cite. That is the failure the
  `## External references` rule exists to prevent, and it had taken root
  here.
