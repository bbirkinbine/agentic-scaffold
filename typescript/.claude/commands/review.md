---
description: Invoke the reviewer subagent on the complete current semantic change set. Independent review — does not see implementation reasoning.
argument-hint: "[spec-path] [<base>..<head> for an explicit historical range]"
---

Invoke the `reviewer` subagent.

Spec selection:

- Resolve the active spec using `AGENTS.md` → **Shared workflow protocols** →
  **Active-spec resolution**: explicit spec path, then branch-number match,
  then the unique `shipping` spec. Ambiguity stops; never guess from the
  highest spec number.

Change-set selection:

- By default, build the complete pre-commit semantic change set from
  `AGENTS.md` → **Shared workflow protocols** → **Semantic change set**. Pass
  the reviewer the resolved spec path, base ref, merge-base, `git status`
  output, tracked working-tree diff, and untracked-path manifest. The reviewer
  must inspect every untracked path as well as the patch.
- If `$ARGUMENTS` explicitly contains `<base>..<head>`, use that committed
  historical range instead and state that current working-tree changes were
  not reviewed.

The reviewer is fresh and read-only — it has not seen the implementation
reasoning. It checks: spec match, test quality (including tautologies), edge
cases, side effects, don't-touch zones, naming + docstrings, file size,
public-repo hygiene, and docs sync. Pass the recorded `/review-check` evidence;
the read-only reviewer inspects tests and results but does not execute project
code.

Surface its findings verbatim. Do NOT argue with or rationalize away its calls
— if it says "needs to be redone," that's a real signal. The orchestrator may
apply `[auto-fix]` findings; `[ask-user]` stops for human adjudication.

After any fixes, docs affected by the fix are synchronized and the complete
gate runs again. Then invoke a fresh reviewer with the prior findings and the
new complete semantic change set. A focused re-review must verify each claimed
resolution and inspect the fix delta for regressions; if the fix materially
changed design, behavior, or scope, run a full review instead. Do not treat a
green mechanical gate as resolution of a semantic finding.

Delegated files: if the change set includes files that
`.agentic/delegate-run.sh` published (`green` runs in
`.agentic/delegate/ledger.jsonl` with no `review` record yet), pass the
reviewer that list — run ID, target, and packet path for each — and ask it
to tag every finding with the file it concerns and, for a delegated file,
whether the cause is the file's own code or something its packet left out
or contradicted. The reviewer still reviews the whole change set against
the spec; the list only makes attribution explicit, so a gap in work that
was never delegated is not read as a model failure.

Once the final disposition is settled, the orchestrator — not the
read-only reviewer — records each delegated file's outcome:
`bash .agentic/delegate-run.sh record-review <run> <verdict>`. Use
`model-defect` when a finding was a defect in the delegated file's own
implementation, even if the orchestrator then fixed it; `packet-defect`
when the cause was something the packet failed to quote or contradicted;
otherwise `pass`, including when findings concerned other files or docs.
Record once review's fixes are applied: the runner compares the file as
published with the file as it is then and logs how many lines review kept,
removed, and added. Tell the human the verdict and the lines the runner
prints.
