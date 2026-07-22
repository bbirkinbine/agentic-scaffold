# Influences

Where the ideas in this scaffold came from.

## Why this file exists

The scaffold requires every spec that cites an outside authority to declare
it — source, URL, retrieval date, license — and both reviewer agents treat an
undeclared authority as a finding
([`python/docs/specs/README.md`](../python/docs/specs/README.md) →
"External references";
[`python/.claude/rules/python-code.md`](../python/.claude/rules/python-code.md)
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
carry a reconstructed one.

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
| The `AGENTS.md` stub | A vendor-neutral context file other agents look for by convention | [agents.md](https://agents.md/) |

The OpenSpec borrow is deliberately partial: the section convention was taken,
the framework's full living-spec maintenance burden was not.

## Research and reports behind specific rules

| Rule here | Source |
| --- | --- |
| Files ≤ 300 lines; subagents for verbose work; the context-budget guidance in `WORKFLOW.md` → "Session hygiene" | [Context Rot — Chroma](https://research.trychroma.com/context-rot) (U-shaped recall measured across 18 frontier models) |
| `permissions.deny` on `.env` and key material; the status line; `CLAUDE.local.md` overlays; "Session hygiene" | Gui Ferreira, Claude Code talk, NDC AI 2026 — <https://youtu.be/zaDbZt40kRg> (commit `4657fce`) |
| The two senses of "eval", and the opt-in `evaluator` + `/eval` layer | Google/Kaggle, *The New SDLC with Vibe Coding* (2026) — [PDF](https://drive.google.com/file/d/1IR7CddF_2FyQo_PdfBNTaEA50EGiVt2r/view) (commit `b0d490f`) |
| ADR section shape: Context / Decision / Consequences / Alternatives considered | Michael Nygard, *Documenting Architecture Decisions* — no URL recorded |
| The loop's general shape and the test-first discipline | [Anthropic 2026 Agentic Coding Trends Report](https://resources.anthropic.com/hubfs/2026%20Agentic%20Coding%20Trends%20Report.pdf) · [Claude Code best practices](https://code.claude.com/docs/en/best-practices) |

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

## Unverified

- **Gloaguen et al., 2026** — cited in
  [`python/README.md`](../python/README.md) ("Don't") for the finding that
  LLM-generated context files measurably reduce agent performance. Recorded
  second-hand in the author's research notes with no title or URL captured.
  The rule it supports is independently sound, but the citation should be
  replaced with a primary link or dropped to an unattributed statement.
