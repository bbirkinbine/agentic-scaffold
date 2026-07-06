# Evals — what the term means, what you already do, and the one opt-in piece

> **Purpose.** "Eval" is used two ways in the agentic-engineering
> literature, and conflating them causes confusion. This doc separates
> them, shows that your scaffold already does most of one of them under
> other names, and scopes the single net-new, opt-in piece: evals for a
> *product that contains an LLM/AI surface*. If you ship no such surface,
> Section 2 is all that applies to you — the rest is for the subset of
> projects whose product is (or embeds) an agent. This doc covers
> *judging* that surface; how to *build* it — the call seam, prompt
> versioning, model pinning, testing without live calls — is
> [`llm-product.md`](llm-product.md).

---

## 1. The two senses of "eval"

An eval is one technique: judge **non-deterministic** behavior with
**output evaluation** (was the final artifact right?) plus **trajectory
evaluation** (was the path that produced it right — the sequence of tool
calls and intermediate reasoning?), scored not by a single equality
assertion but by **labelled datasets, scoring rubrics, and LM judges**.
The scored dimensions are the same in both senses: task success, tool-use
quality, trajectory compliance, hallucination rate, response quality.

What differs is *whose* non-deterministic behavior you point it at:

- **Sense A — the agent that *builds* your project.** Did the coding agent
  take the right trajectory of decisions against the spec and plan, choose
  the right tools, and not skip its verification steps? This applies to
  **any** AI-built project, even a fully deterministic one — the source is
  the coding agent, not your product. (Source: *"Testing AI-generated code
  requires evaluating not just what the agent produced, but how it got
  there. Output evaluation checks the final artifact… Trajectory
  evaluation checks the full sequence of tool calls and intermediate
  reasoning."*)
- **Sense B — the agent that *is* your product.** When your software ships
  an LLM/agent surface, its runtime trajectory and response quality are
  non-deterministic and must be gated before it ships into a workflow.
  (Source: *"Require eval coverage with explicit rubrics as a precondition
  for any agent shipping into a shared workflow."*)

The common confusion: hearing "eval" and assuming it always means Sense B
(your product must *be* an agent). It does not. Sense A is about the coding
agent's decisions while building ordinary software. Keep them separate;
your scaffold treats them differently.

## 2. Sense A — you already do this (under other names)

You do not need a new tool for Sense A. The scaffold's existing review
machinery *is* output-and-trajectory evaluation of the coding agent; it
just isn't labelled "eval":

| Paper's term | What it checks | Where the scaffold does it |
| --- | --- | --- |
| **Output evaluation** | compiles? tests pass? matches the spec? | `/review-check` (ruff · mypy · pytest) + `/review` + `/analyze` (every success criterion has a test) |
| **Trajectory evaluation** | "how it got there" — did it follow the spec/plan, skip no verification, choose sound approaches? | fresh-context `/review` + `/review-adversarial` (a context that did *not* see the implementation reasoning judges the result) + completion-ladder rung 4 ("gate green but feature wrong") |
| **"evals are the contract, written before the code"** | tell the agent what "correct" means up front | the spec's `## Success criteria` (behavior-level, ideally a runnable check) + `/test-first` writing failing tests before implementation |

So the paper's "without tests *and* evals you're vibe coding" is, for a
deterministic project, already satisfied: tests pin the deterministic
behavior, and `/review` + `/review-adversarial` + `/analyze` +
the completion ladder evaluate the coding agent's output and trajectory.
Nothing to add. If anything, read this row as a vocabulary map for when the
paper's language shows up in discussion.

## 3. Sense B — do I need product evals?

Everything below is the opt-in piece, and it applies only when the answer
to one question is yes:

> **Does my code call an LLM, or otherwise produce output I judge for
> *quality* rather than *equality*?**

If the output is deterministic — same input, same output, checkable with an
exact assertion — it is a **test**, not an eval. If the output is
probabilistic and "correct" is a quality judgment, it needs a **product
eval**.

| Example | Tests | Product evals |
| --- | --- | --- |
| `add(2, 2)` → `4` | assert equality | — |
| `parse_config(x)` → exact dict | assert equality | — |
| `summarize(doc)` → a summary that differs every run | can't assert equality | judge quality vs. a rubric |
| RAG answer over a vault | test the plumbing (200, N chunks returned) | judge the answer (grounded? hallucinated?) |

**Most projects scaffolded from this template never enable Sense B.** A
CLI, a library, an IaC/homelab tool — all deterministic; tests plus the
Section 2 review machinery suffice. Product evals are for the subset whose
product contains an LLM/AI surface: a summarizer, a chatbot, a RAG
answerer, an MCP server that generates text, an agent whose tool-use
trajectory matters. That is why the `evaluator` subagent is **opt-in**, the
same way `security-reviewer` is opt-in for a network surface — see
`new-project-checklist.md`.

## 4. When in the loop do I run `/eval`?

Product evals run at the same three rhythms as tests:

1. **Up front**, when you build the LLM feature. The eval set is the
   quality contract — write it before or alongside the feature, the way
   `/test-first` writes failing tests first. The spec's success criterion
   becomes a threshold: "done when ≥90% of cases score ≥4/5 on
   faithfulness."
2. **During Verify**, beside `/review-check`, before the feature ships.
3. **Every time you touch the probabilistic part afterward** — a prompt
   tweak, a model swap (`opus` → `haiku`), a retrieval change. None of
   those break a test, and all of them move output quality silently. The
   eval is the only gate that catches a prompt change that quietly made
   answers worse. Run it in CI on that feature.

Mental model: **`/test-first` is for the deterministic code; `/eval` is for
the AI-in-the-product code.** A project uses one, both, or — usually — just
tests plus the Section 2 review.

## 5. What a product eval is, and why it must not grade its own homework

A case is `(input, rubric, ground truth)`: run the feature on the input,
then judge the output — by a deterministic assertion where one is
checkable, otherwise by an **LM judge** scoring against the rubric.

The danger unique to evals: if the same model invents the cases, produces
the output, and grades itself, the eval measures *self-consistency*, not
*correctness* — and it fails silently, passing everything. The defense is
that **none of an eval's authority comes from the model's own invention.**
Each part traces to something external:

| Part of a case | Where its authority comes from — never the model |
| --- | --- |
| **Rubric** (what "good" means) | the spec's `## Success criteria` — the human owns the bar |
| **Inputs** | a **labelled dataset** of real, representative data — actual docs/questions, not synthesized |
| **Gold / ground truth** | external — the source document or spec, not the model's opinion (e.g. faithfulness is judged *against the source*, which the model can't fake) |

Two anti-patterns this rules out:

- **Self-referential cases** — the model writes the cases, writes the
  answers, and grades itself. Measures agreement with itself, not truth.
- **Evals derived from the implementation** — read the code, write cases
  matching what it already does, and the eval just ratifies current
  behavior (the eval equivalent of a test that asserts whatever the
  function happens to return today).

Both are killed by the same discipline the `reviewer` subagent already
follows ("has not seen the implementation reasoning"): **author evals from
the spec, never the code; keep rubric, inputs, and ground truth external;
run the judging pass independent of the generator.**

**Who creates the criteria.** You do not hand the `evaluator` a finished
eval suite, and it does not originate the bar from nothing. It is
**draft-and-stop**: it drafts the rubric from your spec's `## Success
criteria` (or `## Goal` when the criteria are thin) and, if the spec names
no pass threshold, proposes a candidate for you to confirm — then stops at
a checkpoint where you approve or edit before any case counts. What it will
*not* do is invent a rubric by reading the implementation (a dead eval) or
fabricate inputs and ground truth. Real inputs and ground truth it must be
given; if they do not exist yet, it asks and waits. So the split is: the
evaluator drafts the bar *from the spec* for your sign-off, and you own the
bar and supply the data. If the spec has no quality intent at all — not
even in the Goal — it pushes back to the spec (or `/clarify`) rather than
guessing what "good" means.

## 6. Rubric dimensions

Score each case on the dimensions that apply (the paper's eval rubric):

- **Task success** — did it accomplish the requested task?
- **Tool-use quality** — right tools, right arguments, no thrash?
- **Trajectory compliance** — did it follow the intended path / stay in
  bounds?
- **Hallucination rate** — did it assert anything unsupported by the
  source / ground truth?
- **Response quality** — clarity, format, completeness of the final
  output.

A criterion that is deterministically checkable does not belong in the
rubric — push it down into a **test** instead. Evals stay lean by only
covering what a test can't assert.

## 7. Convention and fit

- **Where eval cases live.** Under `evals/`, parallel to `tests/`,
  runnable. Not auto-seeded by `bootstrap.sh` — the `evaluator` subagent
  creates `evals/` on first run, once the project has opted in.
- **The pass threshold lives in the spec.** Phrase the LLM feature's
  `## Success criteria` as an eval threshold so `/eval`'s pass/fail is
  mechanical ("≥90% of cases score ≥4/5 on faithfulness"). This is the
  "set the bar at the eval, not the demo" rule: a demo proves it worked
  once; an eval with an explicit rubric proves it works reliably. If the
  spec omits a threshold, the `evaluator` proposes one at the Job A
  checkpoint for you to confirm — it won't dead-end, but it won't bake in a
  bar of its own either.
- **Where it sits in the loop.** Product evals are part of **Verify**,
  alongside `/review-check` — see `../WORKFLOW.md` → "Every feature" and
  "The completion ladder". Gate shipping on eval coverage the way the repo
  already gates on tests and CI.
- **The judge.** Use a capable (frontier) model for the LM-judge — judging
  quality is harder than producing it — and run it independent of the call
  that generated the output.

## 8. Enabling product evals on a project

Doctrine (this file) and the `/eval` command ship managed by `bootstrap.sh`.
The `evaluator` subagent is opt-in — copy it in when the product gains an
LLM/agent surface:

```bash
cp path/to/agentic-scaffold/python/.claude/agents/optional/evaluator.md \
   .claude/agents/evaluator.md
```

Then add a one-line mention under "Subagents" in `CLAUDE.md` so the agent
knows when to invoke it, and record the decision in the day-zero opt-in
step of `new-project-checklist.md`.
