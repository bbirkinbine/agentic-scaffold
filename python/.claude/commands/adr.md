---
description: Create an Architecture Decision Record at docs/adr/NNNN-<slug>.md capturing a cross-cutting technical decision and its rationale.
argument-hint: <decision title>
---

Create a new ADR under `docs/adr/`.

An ADR records a **cross-cutting technical decision** — one that several
features inherit and that is costly to reverse (a storage engine, an
async/sync boundary, a public API shape, an auth model, a serialization
format). It is not a feature spec. If the decision affects only one unit
of work, it belongs in that feature's spec under `## Sketch`, not here.
See `docs/adr/README.md` for the full convention.

Procedure:

1. Determine `NNNN` — ADRs are numbered **independently of issues**
   (unlike specs, where the number *is* the issue number): take the
   highest existing 4-digit prefix in `docs/adr/` and add 1, zero-padded
   to four digits. The first ADR is `0001`. Never reuse a number, even
   for a superseded ADR.
2. Derive a slug from `$ARGUMENTS` (lowercase, hyphen-separated, no
   punctuation).
3. Title-case `$ARGUMENTS` for the H1.
4. Determine today's date in `YYYY-MM-DD`, consistent with prior ADRs.
5. Write the file at `docs/adr/NNNN-<slug>.md` using this skeleton
   (substitute `NNNN`, the title-cased name, and today's date):

```markdown
# NNNN — <Title-cased decision name>

**Status:** proposed
**Last updated:** YYYY-MM-DD

## Context

<The forces at play — technical constraints, product needs, what makes a
decision necessary now. State the problem, including the parts that argue
against the decision you reach. Not the answer yet.>

## Decision

<The choice, in active voice: "We will …". One decision per ADR.>

## Consequences

<What this makes easier and what it makes harder — the trade-offs
accepted, and any follow-on work the decision creates. List downsides,
not only upsides.>

## Alternatives considered

- <option> — <why it was not chosen>
```

The `**Status:**` and `**Last updated:**` fields are load-bearing — keep
them. If this ADR replaces an earlier one, set the older ADR's status to
`superseded-by-NNNN` and link the two together (see `docs/adr/README.md`).

Stop after writing the file. Do NOT proceed to implementation — the human
reviews and edits the rationale before the decision is acted on. Surface
the path of the file you wrote.
