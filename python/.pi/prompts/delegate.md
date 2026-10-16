---
description: Build a self-contained handoff packet so a weaker or local model can implement one file against failing tests. Produces the packet and stops — does not call the other model.
argument-hint: "[path to one file from the approved plan, or blank to pick the next eligible file]"
---

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
  `/review` record its verdict as "Review of delegated files" describes;
- `needs_frontier` (exit 10): implement the file yourself without reading
  the local attempts;
- any other exit: report the reason and stop.

Never call a model any other way, never edit the target while the runner
is working or before `/review`, and do not commit anything.

## Delegation modes

Run `bash .agentic/delegate-run.sh policy`. Exit 1 (`off: <why>`) means no
delegation for this checkout: implement yourself and do not ask about a
mode. Exit 2 means delegation is set up but the runner cannot start (a
missing dependency such as `jq`): tell the human what it printed and
implement yourself; do not install anything. `policy` printing `auto`
means the human approved local delegation for this checkout. Which kind, if
any, is chosen per run, as a standing decision from `/unattended start` or
the human's direct answer:

- `none`: implement yourself. Also the answer when the session itself runs
  on a local model, since delegating to another local model only adds work.
- `files`: "Automatic mode" below, one file per call through `run`.
- `handoff`: "Phase handoff" below, a whole phase to a local session.

With no choice recorded, ask once at the implement step; never assume one
from the policy alone.

## Review of delegated files

If the change set includes files that `.agentic/delegate-run.sh` published
(`green` runs in `.agentic/delegate/ledger.jsonl` with no `review` record
yet), pass the reviewer that list — run ID, target, and packet path for each — and ask it
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

## Automatic mode

With delegation `files` and `policy` printing `auto`, do not ask again per
file. Walk the approved plan's files in its order of operations:

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

## Phase handoff

Instead of one file at a time, the whole implement phase (or test-first plus
implement) can go to a local agent session that reads the repository, edits,
and runs the tests itself, in its own git worktree. The session runs in Pi
whichever client orchestrates, so Pi must be installed. Use it with
delegation `handoff`, the plan approved, the spec `shipping`, and the tree
committed:

1. Explain that a verified handoff is stored as a temporary commit on a
   `handoff/<run>` branch, separate from the feature branch, and ask for
   explicit current-chat authorization for that commit. Choosing delegation
   mode `handoff` by itself is not commit authorization. If the human does
   not authorize it, use `files` or `none` instead. Once authorized, launch
   it:
   `bash .agentic/delegate-run.sh handoff <spec> --allow-commit --phase implement`
   (or `--phase test-first+implement`), with `--model <name>` when the
   human named one. The runner refuses without `--allow-commit`; pass it only
   for the authorization just obtained or recorded by `/unattended start`.
   The launch returns at once (exit 2 if refused) and prints the run id; the
   session runs detached for as long as it keeps working. Do not edit the
   repository while it runs.
2. Wait with `bash .agentic/delegate-run.sh handoff-status <run> --wait 540`.
   It reads local files only and costs no tokens. Repeat it while it exits 12
   (still running); 540 seconds stays under every client's tool time limit.
3. Act on the exit status:
   - 0: verified (full gate green, only plan files changed, no test file in
     an implement-only phase) and committed on `handoff/<run>`. Read the
     spec's `### After handoff` note in the worktree, then run `/review`
     (and `/review-adversarial` on meaningful features) on
     `git diff HEAD...handoff/<run>`. Fix findings yourself or hand off
     again; then `git merge --squash handoff/<run>` into the feature branch
     and continue with closeout.
   - 11 (paused): the session went quiet past its inactivity lease, hit an
     optional total ceiling, or was stopped, and was checkpointed; or its
     runner died (state `orphaned`). Nothing was gated or committed. Read
     the spec's `### Paused handoff` note in the worktree, then resume the
     same session and worktree with
     `bash .agentic/delegate-run.sh handoff-resume <run> --allow-commit`
     (add `--max-total <seconds>` to raise a spent ceiling) and wait again
     as in step 2. Resuming needs the same commit authorization as the
     launch. Or abandon it with `handoff-clean <run>`.
   - 10 (`needs_frontier`): the session ended with the gate red or changed
     nothing. Read its handoff note in the kept worktree, then either
     implement yourself from the branch's starting point or hand off once
     more with a short hint in the spec.
   - 4 (integrity): the session changed files outside the plan, or a test
     in an implement-only phase. Report to the human; do not merge.
   - 3 (infrastructure) or 2 (refused): report and implement yourself.
4. After merging or abandoning a handoff, remove its worktree and branch:
   `bash .agentic/delegate-run.sh handoff-clean <run>`
   (`handoff-clean` alone lists what is left with each run's state; `--all`
   removes every one that is not live). Record the review verdict with
   `record-review <run>` first; a handoff is scored per phase like a file
   run, once per logical run however many times it paused.

To stop a live handoff deliberately, `handoff-stop <run>` asks it to
checkpoint and pause (exit 11 from `handoff-status`).

Under Codex, the default workspace sandbox blocks network access, including
the local model endpoint (and the npm registry when the checkout has not
installed its Pi packages). Ask the human to approve running the handoff
commands outside the sandbox or with a network-enabled permission profile,
or to run them in a terminal. Do not change the project's Codex sandbox
configuration.
