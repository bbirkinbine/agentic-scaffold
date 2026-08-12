---
description: Build a self-contained handoff packet so a weaker or local model can implement one file against failing tests. Produces the packet and stops — does not call the other model.
argument-hint: "[path to the one file to implement, or blank to infer from the approved plan]"
---

Produce a **local-executor handoff packet** for exactly one file.

Read `docs/local-executor.md` first if it is installed; this command
implements the rule it states. Refuse the task rather than bending it —
a packet that violates the preconditions is worse than no packet, because
the failure will look like a model problem.

## Preconditions — check all of them, and stop if any fails

1. An active spec resolves under `AGENTS.md` → **Shared workflow protocols**
   → **Active-spec resolution**, and it has a `## Success criteria` section.
   Ambiguity stops; never guess from the highest spec number.
2. The spec carries an `## Approved implementation plan` and the target is
   **one** file. If the plan touches more than one, say so and stop — split
   the spec instead.
3. Tests for this work exist and **currently fail**. Run the gate and show
   the failing output. If tests pass or do not exist, stop and say
   `/test-first` has not run.
4. The target file is under 300 lines, or the change is confined to a
   region you can quote in full.

State which preconditions passed. If any failed, stop there — do not emit a
partial packet.

## The packet

Write it to `docs/specs/<NNNN>-handoff-<slug>.md` and print the path. It must
be readable by a model with **no access to this conversation, this
repository, or any tool**. Everything it needs is in the file.

Sections, in this order:

1. **Task** — one paragraph. What the file must do when finished. Written as
   a requirement, not as a narrative of the discussion.
2. **The file as it exists now** — full current contents in a fenced block,
   or `NEW FILE` if it does not exist yet.
3. **The failing tests** — full contents of the test functions that must
   pass, in a fenced block. Not a summary of them; the actual code.
4. **The exact failure output** — verbatim from the gate.
5. **Contracts it must honor** — every signature, type, import, and
   constant from elsewhere in the codebase that the implementation touches,
   quoted directly. Assume the executor cannot look anything up. This
   section is where delegation succeeds or fails.
6. **Out of bounds** — files it must not touch, behavior it must not change,
   dependencies it must not add.
7. **Output contract** — verbatim:
   > Return the complete final contents of `<path>`, and nothing else. No
   > diff, no patch, no commentary, no markdown fence around the file, no
   > explanation of your changes.

## Rules for writing it

- **Resolve every reference.** No "see the spec", no "as discussed", no
  `[[links]]`, no relative pointers. If the executor would have to look
  something up, inline it.
- **Prefer a complete file over a diff.** Diff generation is a separate
  skill from coding and weak models are measurably worse at it.
- **Keep the instruction count down.** Instruction-following degrades as
  constraints accumulate, and it degrades faster on smaller models. Six
  sharp constraints beat twenty exhaustive ones. Cut anything the tests
  already enforce — the tests are the specification.
- **Do not include reasoning, alternatives, or rationale.** The executor is
  not deciding anything. Rationale belongs in the spec.

## After the packet

Print, as plain text for the human:

- The packet path.
- The command to run the gate on the result.
- A reminder that the loop is: run the executor, apply its output, run
  `/review-check`, and on a red gate retry at most **3** times before
  escalating this file back to the frontier model.
- A reminder that a green gate is necessary and not sufficient — `/review`
  still runs against the spec afterward, over the complete semantic change
  set.

Then stop. Do not invoke another model, do not implement the file yourself,
and do not commit anything.
