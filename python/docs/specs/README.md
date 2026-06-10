# Specs

Short design docs for non-trivial features. Read these before implementing
or reviewing.

## Numbering

`NNNN-<kebab-name>.md`, zero-padded to four digits. New specs increment
the highest existing number. Once a number is assigned it doesn't change,
even if the spec is later superseded.

## Status header convention

Top of every spec:

```markdown
# NNNN — <Title>

**Status:** draft | shipping | shipped | paused | abandoned | superseded-by-NNNN
**Last updated:** YYYY-MM-DD
```

The `**Status:**` field is load-bearing — `/specs-status` reads it across
all specs to print the status table. Keep it current; a spec stuck on
`draft` six months after the work shipped is the noise this convention
exists to prevent.

Status vocabulary:

- `draft` — written but not yet acted on. Planner / test-first haven't run.
- `shipping` — currently being implemented. The spec is in flight.
- `shipped` — merged. The feature is in the codebase.
- `paused` — deliberately set down. Will resume; not abandoned. Note in the spec why.
- `abandoned` — decided not to build. Spec stays as a design log of "we considered this and skipped." Note why in the spec.
- `superseded-by-NNNN` — replaced by a newer spec. Link to the successor.

## Minimum spec shape

A spec doesn't need to be long. The minimum is:

```markdown
# NNNN — <Title>

**Status:** draft
**Last updated:** YYYY-MM-DD

## Goal

<One paragraph: what we're building and why.>

## Success criteria

- <Verifiable, behavior-level. Not "code is clean", but "GET /foo returns 200 with {bar} when X.">

## Non-goals

- <Things we're explicitly NOT doing in this spec. Prevents scope creep at plan time.>

## External references

<Where any value or claim in this spec gets its correctness from when
that correctness depends on matching an outside authority. Examples
worth screening (not exhaustive): constant tables and lookups,
algorithm constants (CRC polynomials, hash IVs, S-boxes, curve
parameters), API contracts (endpoint paths, field names, status
codes), file-format markers and struct offsets, grammars and regexes
purporting to implement a documented format, library signatures,
test vectors / known-answer tests, and cited section numbers
("per RFC 7231 §6.4"). The rule is about claimed provenance, not the
data shape — if the spec or implementation will *cite* an outside
source for correctness, it gets declared here.

Required — "None" is a valid answer, but the question must be
answered. Pick the case that applies:

- **Authoritative source.** Name the source and pin a URL + retrieval
  date + the source's license (e.g., "GS1 Manufacturer ID registry,
  https://… , retrieved YYYY-MM-DD, license: public registry / CC-BY
  / MIT / GPL-3.0 / unclear"). Implementation MUST `WebFetch` this URL
  in-session rather than reconstructing values from training data.
  Tests MUST include at least one fixture from an *independent*
  source — a second URL, a permissively-licensed reference
  implementation in `vendor/`, or a hand-decoded byte trace. Fixtures
  derived from the same assumptions the implementation makes
  round-trip noise, not correctness.

  **License compatibility is part of the source decision, not a
  follow-up.** This repo defaults to a permissive license (MIT-style).
  When the candidate source is:

  - Permissive (MIT, BSD, Apache-2.0, CC0, public domain, or an
    official registry page with no per-page license) → copy values
    with attribution.
  - Copyleft (GPL, AGPL, LGPL with strings) → **consult-only**.
    Read it in a browser to verify your independently-derived values;
    do **not** copy the table verbatim and do **not** check the
    project into `vendor/` — vendoring infects the repo even without
    copying. If it's the only source, treat that as a spec-level
    decision: pick a different source, accept the license change, or
    downgrade provenance to "Empirical" / "None — original" with the
    correspondingly smaller claim.
  - Unclear or absent license → treat as all-rights-reserved. "No
    LICENSE file" is not "permissive by default."
- **Empirical.** No published authority, but observable reference
  behavior exists. Capture fixtures from real systems and note their
  provenance ("decoded from N device dumps captured YYYY-MM-DD from
  <system>"). The implementation is documented as empirical, not
  specified.
- **None — original.** No external authority, no reference behavior.
  The spec *is* the source. State this explicitly so the reviewer
  knows not to expect cited values to match an outside registry, and
  so downstream consumers know this is a proposal rather than
  documentation of an existing standard.

Fabricating a source — citing a registry, RFC, or vendor table the
spec and implementation never actually fetched — is the failure this
section exists to prevent. If no source has been found, say so; do
not invent one. The agent should push back at spec time rather than
invent provenance at implementation time.>

## Sketch

<Optional: a few sentences on the approach. The planner subagent
expands this into a file-by-file plan; you don't need to pre-resolve
implementation details here.>
```

For larger features, add: dependencies, schema changes, migration plan,
test strategy, open questions. Keep it reviewable in < 10 minutes.

## Optional sections

These sit alongside the minimum shape above. Skip them on single-session
features.

### `## Phase handoff`

For features that span multiple sessions. At each phase boundary, append
a handoff block before running `/clear`:

```markdown
## Phase handoff

**As of:** YYYY-MM-DD, after `/plan`
**State:** <one paragraph: where we are, what the last phase produced.>
**Next phase:** `/test-first`
**Entry conditions:** <what the fresh session needs to do first. e.g.
"read docs/specs/NNNN-foo.md and src/foo/__init__.py before invoking
the test-first subagent.">
```

Each handoff block stacks below the previous one — keep them in order,
don't overwrite. The fresh session reads the most recent block to know
where to pick up. See `WORKFLOW.md` "Phase handoff" for the why.

### `## Implementation Notes`

Appended **after** merge. Captures decisions that surfaced during
implementation but weren't in the original spec — a library swap, an
edge case the planner didn't anticipate, a refactor that broke a
pattern. Lightweight; one bullet per decision. The spec stays a design
log, not a living document, but this section keeps the design log
honest about what shipped.

```markdown
## Implementation Notes

- Swapped `httpx.AsyncClient` for `httpx.Client` — async wasn't load-bearing
  for this feature and the sync path keeps the call site simpler.
- Pagination cursor format diverged from the spec's `?page=N` to
  `?after=<id>` after discovering the upstream API requires cursor-based
  paging. See PR #42.
```

If a decision was load-bearing enough to redo the original spec, do
that instead — `Status: superseded-by-NNNN` and a new spec. This
section is for the small stuff.

## How specs interact with the agentic loop

From `Research/Programming/Agentic Programming/02 Agentic Methodology Loop.md`:

1. **You write the spec.** ~5 minutes. One paragraph minimum.
2. **`planner` subagent reads the spec** + relevant code, produces a markdown plan with files-to-touch and ordering.
3. **`test-first` subagent reads the spec** + the plan, writes failing pytest tests.
4. Main session implements the minimum code to pass the tests.
5. **`reviewer` subagent reads the spec + the diff**, produces review notes before commit.

The spec is the artifact every other phase refers back to. If it changes
mid-flight, update the file before continuing — don't carry an updated
intent only in the chat session.
