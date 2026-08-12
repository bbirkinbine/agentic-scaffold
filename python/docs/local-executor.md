# Delegating implementation to a local model

Advanced doc, installed with `--full` / `--advanced-docs`. Companion to
[`parallel-agents.md`](parallel-agents.md): that doc covers running *more*
agents of the same class, this one covers running a *weaker* agent on a
subset of the loop and being honest about which subset.

Everything here is optional. Nothing in the loop depends on it.

## The rule

**Delegate to a local model only where a machine — not a human — can tell
whether it succeeded.**

That is not a general principle about model quality. It follows from three
facts, in order:

1. On the independently-run Terminal-Bench 2.0 leaderboard, open-weight
   models that fit in 72 GB of VRAM score roughly **25%** on autonomous
   agentic coding tasks, against roughly **85%** for current frontier
   models. Most local attempts at an agentic task fail.
2. A high failure rate is only affordable when detection is automatic and
   free.
3. This scaffolding already owns automatic detection. `/test-first` writes
   the oracle *before* implementation exists, and `/review-check` runs it.

Point 3 is the whole reason this is worth attempting here. Most public
reports of local-model delegation converge on "bounded chores" precisely
because the people writing them have no mechanical oracle and are
eyeballing the diff.

## Three tiers, three verdicts

"Can a local model code" is three questions.

| Tier | The job | Model class | Verdict |
| --- | --- | --- | --- |
| **1 — inline autocomplete (FIM)** | Complete the line you are typing | 1.5B–7B **base** model | Works. Unrelated to this loop; wire it up and forget it |
| **2 — one bounded edit** | Rewrite one already-specified file so failing tests pass | 27B–120B instruct | Viable *only* behind a green gate |
| **3 — autonomous agentic loop** | Multi-turn tool use, commands, many files | any open weight today | Does not work. Do not design around it |

Tier 1 notes worth carrying: use a **base** model, not an Instruct
variant — chat tuning suppresses fill-in-the-middle, and model vendors say
so directly. Serve it on its own endpoint; the autocomplete model and the
implementation model should never be the same process.

## Phase-by-phase

| Phase | Local? | Why |
| --- | --- | --- |
| `/spec`, `/product-spec`, `/adr` | No | No machine oracle, and specification defects are the largest single category of multi-agent failure |
| `/plan` | No | A weaker planner measurably degrades a stronger executor; the reverse hazard is real |
| `/test-first` | No | The tests *are* the oracle. Never delegate the grader |
| Implement | **Yes, conditionally** | The only phase with mechanical pass/fail |
| `/review-check` | n/a | Deterministic already — ruff, mypy, pytest |
| `/review`, `/review-adversarial` | No | This is the rung that catches "gate green, feature wrong." A 25%-agentic model is the wrong judge |

## Conditions on the implement phase

All six, or don't delegate:

1. **One file.** Multi-file refactors are the named failure in every
   negative field report.
2. **Single shot, not an agentic loop.** Ask for a complete file back. The
   loop is where the 25% lives; the single bounded edit is where the ~40%
   lives.
3. **Tests exist and fail before the call.** No oracle, no delegation.
4. **Capped retries, then escalate to the frontier model.** The cap matters
   more than its value; three is a reasonable start.
5. **Prefer whole-file output over diffs.** The same model on the same
   problems has scored 2x differently on format alone. Diff generation is a
   separate skill from coding and weak models are bad at it.
6. **Pin the quadruple** — model, quant, runtime version, harness version.
   Local tool-calling breaks on serialization mismatches between model,
   runtime and harness far more often than on reasoning, and every one of
   those layers ships breaking changes.

## What breaks, and it is not what you expect

The dominant local-executor failure is **serialization, not reasoning**:
the model emits a tool call in a shape the harness does not parse, and the
harness either silently no-ops or loops forever re-emitting it. Documented
instances span Cline, Roo Code, OpenCode, Qwen's own first-party CLI,
llama.cpp's tool parser, Ollama's Anthropic-compatibility layer, and Claude
Code's schema validation. These are fixed and re-broken continuously.

Practical consequences:

- Budget context for the harness itself. An agentic harness system prompt
  plus tool schemas can consume 6–10K tokens before your task starts;
  32K context is a floor and 64K is comfortable.
- Test the plumbing on an *already-solved* spec first. You want the first
  failure to be a parser bug you can see, not a subtle wrong implementation.
- When a model works, write down the exact versions. When you upgrade, re-run
  the plumbing test before trusting a real task to it.

## Honest expectations

The bounded, tested, single-file edit is the cheapest thing a frontier model
does, so moving it local saves the least. Expect the win to show up as
latency and privacy rather than capability or cost, and expect a meaningful
fraction of delegated tasks to escalate back.

The good reason to build this is to learn where the envelope actually is.
That is a real reason. It is not an efficiency argument, and presenting it
as one sets up a disappointment.

## What would change this doc

- A controlled comparison — same tasks, frontier-only versus frontier-plan
  plus local-execute, with quality and token numbers. No such measurement is
  published as of 2026-08. Running one on your own repo would be novel.
- An open-weight model fitting 72 GB scoring above ~35% on an independent
  agentic leaderboard. That would move Tier 3 from "no" to "measure it."
- Harness-side convergence on one tool-call serialization, which would
  retire most of the failure list above.
