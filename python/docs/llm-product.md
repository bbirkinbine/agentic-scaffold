# Building an LLM/agent product — construction-side conventions

> **Purpose.** [`evals.md`](evals.md) covers *judging* a product's
> LLM/AI surface (Sense B evals). This doc is its construction-side
> counterpart: how to *write* the code that calls a model so the rest of
> the scaffold — `/test-first`, `/review-check`, CI, the security
> opt-in — keeps working on it. Same gate as evals.md Section 3: if
> nothing in the product calls an LLM, none of this applies; skip it.

---

## 1. The one design rule: isolate the model call behind a seam

Everything else in this doc follows from one decision, made when the
LLM feature is first specced: **all model calls go through one thin
module** — client construction, model id, sampling params, retry
policy, and nothing else. One project, one seam (e.g.
`src/<package>/llm.py`, growing into a package per
`python-module-split` if it must).

```text
deterministic code  →  [ the seam ]  →  provider SDK / HTTP
   (tests own this)     (tests fake this)    (evals judge what comes back)
```

Why this is load-bearing:

- **Tests stay tests.** Code on the deterministic side of the seam —
  prompt assembly, request shaping, output parsing, error handling — is
  ordinary Python. `/test-first` writes failing tests for it and CI runs
  them with no API key and no network.
- **Evals stay scoped.** Only the quality of what comes *back through*
  the seam needs an eval ([`evals.md`](evals.md) Section 3). A fat seam
  drags deterministic logic into eval territory where regressions are
  expensive to detect.
- **Changes are visible.** Model swaps, param tweaks, and retry changes
  land as a diff to one file — reviewable, and an unambiguous trigger
  for re-running `/eval`.

A call site scattering `client.messages.create(...)` through business
logic is the LLM equivalent of SQL strings concatenated inline: it
works, and it makes every downstream discipline impossible.

## 2. Testing code that calls an LLM

Three layers, strictest to loosest. The split to keep straight: **tests
assert the plumbing; evals judge the output.** A test proves the request
was built right and the response was handled right; whether the model's
answer was any *good* is `/eval`'s job, never a unit test's.

| Layer | What it does | Network / key | Runs in CI |
| --- | --- | --- | --- |
| **Unit (default)** | Fake the seam — inject a stub client or callable returning canned responses; assert prompt assembly, parsing, validation, error paths | Never | Yes — this is the layer `/test-first` writes |
| **Recorded (optional)** | Replay captured HTTP responses (e.g. `respx` for httpx-based SDKs, or `vcrpy` cassettes) for integration shape — streaming, tool-call frames, error bodies | Record once, replay offline | Yes, replay only |
| **Live smoke (manual)** | A handful of real calls to catch SDK/provider drift | Real key from the environment | No — marked and deselected |

Conventions that keep the layers honest:

- **No API key in the CI test job, ever.** If the suite fails without a
  key, a live call has leaked below the top layer — treat it as a bug.
  (`.github/workflows/ci.yml` sets no provider secrets; keep it that
  way.)
- **Mark live tests and deselect them by default:**

  ```toml
  # pyproject.toml
  [tool.pytest.ini_options]
  markers = ["live: hits a real LLM API; needs a key; excluded by default"]
  addopts = "-m 'not live'"
  ```

  Run them deliberately with `uv run pytest -m live`.
- **Scrub recorded fixtures before they land.** Cassettes capture
  request headers — an `Authorization` header in a committed fixture is
  a live credential in a public repo. Configure the recorder to filter
  auth headers, and treat fixtures as in scope for the
  `public-repo-hygiene` rules and the gitleaks pre-commit scan.
- **Don't over-assert canned responses.** A unit test asserting the full
  text of a fake completion pins nothing real. Assert the plumbing
  around it: the right prompt version was sent, the parser accepted or
  rejected correctly, the retry fired.

## 3. Prompts are code

Prompts live in named, versioned files in one place (e.g.
`src/<package>/prompts/`), not as string literals scattered through
call sites. They are code in every way that matters — behavior lives in
them, diffs to them are reviewed like logic changes — except one:
**no test can catch a prompt regression.** A prompt edit compiles, types,
and passes the whole suite while silently degrading output quality.

That asymmetry sets the rule: **a change to a prompt re-runs `/eval` on
the features that use it, before it merges** — the same trigger evals.md
Section 4 names. The seam should log which prompt (name + version) each
call used, so an eval score is attributable to a specific prompt
revision.

`/review` treats a prompt diff like a code diff: unexplained rewrites of
working prompts are scope creep, and a prompt that embeds facts (dates,
URLs, product claims) follows the same external-reference provenance
rule as code (`.claude/rules/python-code.md`).

## 4. Pin the model

Model ids and sampling params live at the seam (or in config the seam
reads), pinned to a specific version — a dated or versioned id, not a
provider's floating alias, which re-points silently and moves output
quality with no diff in your repo.

Treat a model swap exactly like a dependency major-version bump,
because it is one:

- It lands as a reviewable one-line diff at the seam.
- It re-runs `/eval` before merging — a cheaper model that clears the
  spec's eval threshold is a free win; one that doesn't is a regression
  the tests will never see.
- The rationale goes in the commit body (or an ADR if the choice is
  cross-cutting — e.g. standardizing the judge model across features).

The `dependency-hygiene` skill fires when `pyproject.toml` gains the
provider SDK; the model id itself is the second, quieter dependency this
section exists to make visible.

## 5. Model output is untrusted input

Validate at the seam, on the way in:

- **Parse, don't trust.** Coerce structured output into a schema
  (Pydantic at the boundary) and handle the failure path — refusals,
  truncation, malformed JSON are normal operating conditions, not
  exceptional ones. Cap retries; a model that failed to produce valid
  output twice will usually fail a third time.
- **Never execute it raw.** Model output that reaches an interpreter —
  `eval`, shell, SQL, a tool dispatcher — is a trust boundary by
  definition.

That second bullet is why **an LLM surface usually trips the
`security-reviewer` opt-in** (see the README's trigger list): prompt
injection when external content (user text, retrieved documents, web
pages) enters the prompt; excessive agency when output selects or
parameterizes tools; SSRF/path traversal when output becomes a URL or
filename. If the feature is a tool-using agent or an MCP server, copy
`security-reviewer` in at day zero rather than debating it.

MCP servers add two conventions of their own: tool docstrings and
schemas *are* the public API — the model reads them, so
`python-docstrings` applies with double force — and an off-loopback bind
is a network surface (a `security-reviewer` trigger on its own).

## 6. Observability and cost

The seam is also where calls get recorded. Log per call: model id,
prompt name + version, input/output tokens, latency, and the outcome
(ok / refused / parse-failed / retried). Without this, an eval
regression can't be attributed and a cost spike can't be explained;
with it, both are a log query.

When the spec has a latency or cost constraint, phrase it as a success
criterion the way evals.md phrases quality thresholds ("p95 under 3 s
on the eval set", "under $0.01 per document") — then the budget is part
of Verify, not a surprise in the first invoice.

## 7. How it fits the loop

The loop does not change; the LLM feature adds one column to each phase:

| Phase | Deterministic feature | + when the feature calls an LLM |
| --- | --- | --- |
| Spec | goal, success criteria, non-goals | quality bar as an eval threshold; latency/cost budget if one exists ([`evals.md`](evals.md) Section 7) |
| Plan | file-by-file plan | seam module named; prompt files named; model pinned |
| Test-first | failing pytest tests | tests fake the seam (Section 2); eval cases drafted from the spec (`/eval`, if `evaluator` is installed) |
| Implement | code to green | prompts under `prompts/`, calls through the seam only |
| Verify | `/review-check` + `/review` | `/eval` clears the spec's threshold; `/security` if the surface trips its triggers |
| Afterward | tests catch regressions | every prompt edit / model swap / retrieval change re-runs `/eval` |

## 8. Day zero for an LLM feature

When a scaffolded project gains its first LLM surface:

1. Copy in the `evaluator` subagent and confirm `/eval` is installed
   (`--full` ships the command; [`evals.md`](evals.md) Section 8).
2. Decide `security-reviewer` — Section 5 makes it the default answer
   for tool-using agents, MCP servers, and anything feeding external
   content into a prompt.
3. Create the seam module and the `prompts/` directory before the first
   call site exists.
4. Pin the model id and params at the seam.
5. Add the `live` pytest marker and the no-key-in-CI convention
   (Section 2).
6. Note the seam path, prompt directory, and pinned model in
   `CLAUDE.md` (stack section + don't-touch list as appropriate) so
   future sessions extend the seam instead of bypassing it.
