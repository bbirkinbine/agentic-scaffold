---
name: delegate
description: Build a self-contained handoff packet so a weaker or local model can implement one file against failing tests. Produces the packet and stops — does not call the other model.
---

In these shared instructions, `$ARGUMENTS` means the arguments supplied with this skill invocation. Any `/<name>` cross-reference names another workflow: invoke `$<name>` in Codex or the matching `/<name>` prompt (or `/skill:<name>`) in Pi.


Produce a **local-executor handoff packet** for exactly one file. A plan
that touches several files is delegated as a sequence of one-file packets in
dependency order, one invocation per file.

Read `docs/local-executor.md` first if it is installed; this command
implements the rule it states. Refuse the task rather than bending it —
a packet that violates the preconditions is worse than no packet, because
the failure will look like a model problem.

## Preconditions — check all of them, and stop if any fails

1. An active spec resolves under `AGENTS.md` → **Shared workflow protocols**
   → **Active-spec resolution**, and it has a `## Success criteria` section.
   Ambiguity stops; never guess from the highest spec number.
2. The spec carries an `## Approved implementation plan` and the target is
   **one** file from its files-to-touch list. With no argument, pick the
   first file in the plan's order of operations that is not yet implemented
   and whose dependencies are.
3. Every file the target depends on that the plan creates or changes is
   already implemented, so its signatures can be quoted from the tree rather
   than from the plan. If one is not, name it and stop — it goes first.
4. The target can reach green on its own. If its tests cannot pass without
   a simultaneous edit to another file (a signature change rippling to
   callers, two modules that only make sense together), stop: the frontier
   model implements that change.
5. Tests for the target exist and **currently fail**. Run the gate and show
   the failing output. Name the tests that exercise the target; failures
   belonging to other not-yet-implemented plan files are expected and stay
   out of the packet. If the target's tests pass or do not exist, stop and
   say `/test-first` has not run.
6. The target file is under 300 lines, or the change is confined to a
   region you can quote in full.
7. **Every requirement on the target is traced.** Collect, verbatim, each
   line of the spec and the approved plan that applies to this file: its
   files-to-touch entry, its order-of-operations step, test-strategy and
   risk lines that name it or its behavior, and the success criteria it
   implements. Each must be covered by a failing test quoted in the packet,
   a quoted contract, or the Task paragraph; mark any that only `/review`
   can check as unverified. If the packet would forbid or omit behavior a
   requirement demands (for example, "must not validate" where the plan
   requires validation), stop and fix the packet, or ask the human to amend
   the plan. A packet that contradicts the plan is the most common cause of
   a gate-green file that review rejects.
8. **No open choices are left to the executor.** Where the spec and plan
   leave a choice open that a person will see or feel (size, layout, count,
   palette, wording, defaults), decide it from the spec's goal, the product
   spec, and the project's intent, and write the decision into the packet
   concretely: "a symmetric maze about 19×21 with blue walls `#1d4ed8` on
   black", not "an original maze". A local executor fills an open choice
   with the smallest thing the tests accept. List these decisions in the
   report after the packet; in an unattended run, log them under
   `## Unattended decisions`. If a choice is product direction rather than
   detail, ask the human instead.

State which preconditions passed. If any failed, stop there — do not emit a
partial packet.

## The packet

Write it to `.agentic/delegate/packets/<NNNN>-<target-slug>.md`, where
`<NNNN>` is the active spec's number and `<target-slug>` is derived from the
target path, and print the path. The directory is gitignored: a packet is
per-run execution state, not a spec, and a file under `docs/specs/` would
reuse the spec's number and enter the status dashboard. It must be readable
by a model with **no access to this conversation, this
repository, or any tool**. Everything it needs is in the file.

Start the file with this front matter, filled from the plan and the
preconditions above. `.agentic/delegate-run.sh` reads it to check the run
and never sends it to the model:

```yaml
---
format: 2
targets: [<path of the one target file>]
target_lines: <current line count, 0 for a new file>
expected_lines: <for a new file: the plan's estimate of its finished size>
contract_items: <signatures, types, and constants quoted in Contracts>
visible_tests: <test functions in the target's test files>
test_targets: [<test file(s) that exercise the target>]
new_dependencies: false
bucket: <small: <=150 lines and <=8 contract items; medium: <=300 and <=15>
---
```

`bucket` takes the larger size that either count gives, with lines being
the larger of `target_lines` and `expected_lines`. The runner applies the
same rule, refuses a packet labelled smaller than its counts, and keeps a
label larger than they give, so route models by this field.

Write only the sections that need judgment, in this order. Do **not** copy
the target file, the test files, or the gate output into the packet: with
`format: 2` the runner appends the target as it exists, the full test files
named in `test_targets`, the live failure output from its own red baseline,
and the output contract, so those cost no frontier output tokens and never
go stale.

1. **Task** — one paragraph. What the file must do when finished. Written as
   a requirement, not as a narrative of the discussion.
2. **Requirements** — the lines collected for precondition 7, quoted
   verbatim, each tagged `[test: <name>]`, `[contract]`, `[task]`, or
   `[unverified: review checks]`, followed by the decisions from
   precondition 8, each tagged `[decided: frontier]` and stated concretely.
   This is the executor's only view of the spec; do not paraphrase it.
3. **Contracts it must honor** — every signature, type, import, and
   constant from elsewhere in the codebase that the implementation touches,
   quoted directly — including from files implemented earlier in this
   plan. Assume the executor cannot look anything up. This section is where
   delegation succeeds or fails.
4. **Out of bounds** — files it must not touch (every other file in the
   plan included), behavior it must not change, dependencies it must not
   add.

The exact message the model received is saved with each run as
`.agentic/delegate/results/<run>/prompt.md`.

## Rules for writing it

- **Resolve every reference.** No "see the spec", no "as discussed", no
  `[[links]]`, no relative pointers. If the executor would have to look
  something up, inline it.
- **Prefer a complete file over a diff.** Diff generation is a separate
  skill from coding and weak models are measurably worse at it.
- **Keep the instruction count down.** Instruction-following degrades as
  constraints accumulate, and it degrades faster on smaller models. Six
  sharp constraints beat twenty exhaustive ones. Cut anything the tests
  already enforce from the Task and Out-of-bounds prose — but never cut a
  requirement from section 2, and never add a prohibition the plan does
  not make.
- **Do not include reasoning, alternatives, or rationale.** The executor is
  not deciding anything. Rationale belongs in the spec.

## After the packet

Print, as plain text for the human:

- The packet path.
- Every `[decided: frontier]` choice in the packet, so the human can see
  what was decided on their behalf.
- How to run it: `bash .agentic/delegate-run.sh run <packet>`, with
  `--model <name>` to name a `[[model]]` entry in the machine profile
  (`~/.config/agentic/local-models.toml`; `--help` shows the format). The
  runner completes the packet, verifies in a scratch copy, retries at most
  **3** times, and publishes only a passing file. A format-2 packet is not
  meant to be pasted by hand: it lacks the sections the runner adds.
- The plan files still unimplemented after this one, and which of them is
  next eligible for a packet. Gate failures from those files are expected
  until they land; failures in the target's own tests are not.
- A reminder that a green gate is necessary and not sufficient — `/review`
  still runs against the spec afterward, over the complete semantic change
  set once every plan file has landed.

Then stop, unless the human asked you to run the packet. The model must
have passed `bash .agentic/delegate-run.sh qualify <name>` for its current
setup; the runner refuses it otherwise, and `status` shows every model's
state and record. Run it with the model they named (`--model <name>`), or
without `--model` to let it select from the checkout's `[[project]]`
candidates, and report its result as it printed it, including which model
ran and why:

- exit 0: the file is published; `/review-check` comes next, and after
  `/review` record its verdict with `record-review` as `/review` describes;
- `needs_frontier` (exit 10): implement the file yourself without reading
  the local attempts;
- any other exit: report the reason and stop.

Never call a model any other way, never edit the target while the runner
is working or before `/review`, and do not commit anything.

## Automatic mode

At the implement step, when `.agentic/delegate-run.sh` is installed and
`bash .agentic/delegate-run.sh policy` prints `auto`, the human has already
approved local delegation for this checkout; do not ask again per file.
Walk the approved plan's files in its order of operations:

1. Check the preconditions above for the next file. If one fails, implement
   that file yourself and move on; say which precondition failed.
2. Otherwise write its packet and run
   `bash .agentic/delegate-run.sh run <packet>` without `--model`; the
   runner chooses the model from its record and says why.
3. Act on the exit status:
   - 0: the file is published; move to the next file without editing it.
   - 10 (`needs_frontier`): implement the file yourself without reading
     the local attempts, then move on.
   - 2 (refused): implement the file yourself and report the reason.
   - 3 (infrastructure): stop delegating for the rest of this plan,
     implement the remaining files yourself, and report the failure.
   - 4 (integrity stop): stop and report to the human; the workspace or the
     candidate's verification did something unexpected. In an unattended run
     with standing consent, run the packet once more from a fresh snapshot;
     if it stops again, implement the file yourself and log both stops
     under `## Unattended decisions`.

When every plan file has landed, continue with docs, `/review-check`, and
`/review` as usual. After the final review disposition, record a verdict
with `record-review` for every run that published a file. Report which
files were delegated, which model ran each, and how each ended.
