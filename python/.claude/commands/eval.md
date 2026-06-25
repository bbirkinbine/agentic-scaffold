---
description: Invoke the evaluator subagent to author or run an eval suite for an LLM/agent feature. Requires the opt-in subagent to be installed in this project.
argument-hint: [spec path, or blank to run the existing suite]
---

Invoke the `evaluator` subagent.

This command is for **Sense B** evals — judging the quality of a product
that contains an LLM/AI surface. Evaluating the *coding* agent's own
trajectory (did it follow the spec/plan) is Sense A, and that is `/review`,
`/review-adversarial`, and `/analyze`, not this command. `docs/evals.md`
explains both senses.

Preflight: confirm `.claude/agents/evaluator.md` exists in this project. If
not, this project hasn't opted into product evals. Most projects shouldn't —
they are only for a product that contains an LLM/AI surface (see
`docs/evals.md` → "Sense B — do I need product evals?"). If the project does
ship one, enable it:

```
Evaluator is not installed in this project. Evals are opt-in — only enable
them if the product itself contains an LLM/AI surface (summarizer, RAG
answer, chatbot, agent trajectory). To enable:

  cp path/to/agentic-scaffold/python/.claude/agents/optional/evaluator.md \
     .claude/agents/evaluator.md

Then add a one-line mention under "Subagents" in CLAUDE.md so the agent
knows when to invoke it. See docs/evals.md for the decision rule.
```

And stop.

If installed, proceed.

Job selection:

- If `$ARGUMENTS` is a spec path (or the feature has no `evals/` yet), the
  evaluator runs **Job A** — author the eval set from the spec, then stop
  at a human checkpoint for you to confirm the cases before they count.
- Otherwise, the evaluator runs **Job B** — execute the existing suite and
  judge output against the spec's threshold.

The evaluator authors from the spec (never the implementation), keeps the
rubric, inputs, and ground truth external, and runs the LM-judge pass
independent of the generator — the independence rules in `docs/evals.md`
that keep an eval from grading its own homework. Surface its case list (Job
A) or scored results and top-line verdict (Job B) verbatim. A below-bar
result is a Verify-phase blocker for an LLM feature, the same way a red
`/review-check` is.
