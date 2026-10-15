# Local phase handoff — draft spec

**Status:** draft (2026-10-15). Not implemented. Extends
[`docs/local-delegate-runner.md`](local-delegate-runner.md); reuses its
profile, ledger, qualification, and policy.

## Problem

The single-file runner sends a local model one packet with no tools and
verifies the file it returns. Three trials in a TypeScript consumer project
(2026-10-14) showed where that holds and where it does not:

- Files fully pinned by tests survived review: a renderer kept about 99% of
  its published lines.
- Glue and timing code did not: the browser loop kept about 16%, the maze
  about 33%. A single-shot model cannot run its code against the real
  neighbouring modules, and one packet contradicted its plan.
- Delegated code was about 2-3% of the frontier session's output tokens
  (381K output, 2.86M input, 23.9M cache-read for the feature). Most frontier
  cost is orchestration, implementation fix loops, and review; per-file
  delegation cannot reach it.

On 2026-10-15 a local model (GLM-5.3 Flash) ran the scaffold's own loop in
Pi with full tools: clean tool use over a long session, a test-first phase
that pinned the spec's exact values, and correct reasoning about the
movement rules. The behaviour that works is a local *session*, not a local
*file call*.

## Decision

Hand a whole phase, not a file, to a local agent session that runs the same
scaffold loop in an isolated worktree. The frontier orchestrator keeps the
judgment phases and verifies and reviews the result.

```
frontier: spec -> clarify -> plan -> [test-first]
              |
              v  handoff (worktree, headless local session)
local:    [test-first] -> implement -> /review-check green -> stop
              |
              v
frontier: re-run gate -> scope audit -> /review (+ adversarial) -> fix or
          send back -> bring the worktree's changes into the branch
```

Which phases go local is the human's choice per run: `implement`, or
`test-first+implement`. Spec, plan, and the final review never do.

The single-file runner stays for leaf modules the tests fully pin; the
ledger, scored per mode, decides whether it is kept or retired.

## Interface

A subcommand of the existing runner, so profile parsing, model selection,
fingerprints, the ledger, and `policy` are reused:

```
.agentic/delegate-run.sh handoff <spec-path> [--phase implement|test-first+implement]
                                             [--model <name>] [--harness pi]
```

1. **Refuse** unless: the spec's status is `shipping` with an
   `## Approved implementation plan`; the tree is clean; `toolchain.sh
   ready` passes; and, for `--phase implement`, the focused tests exist and
   are red.
2. **Worktree.** `git worktree add` on a new branch `handoff/<run-id>` from
   `HEAD`, outside the checkout (`$TMPDIR/agentic-handoff/<run-id>`).
   Dependencies the gate needs are made available (see open questions);
   ignored secret files (`.env*`, keys) are never copied.
3. **Run the session** with a cleared environment (only `PATH`, `HOME`,
   locale, and the endpoint credential variable the profile names) and a
   wall-clock limit (`handoff_timeout_seconds`, default 4 h):

   ```
   pi -p --approve --model <provider>/<model_id> --thinking <level> \
      --session-dir <result-dir>/session --mode json \
      "<handoff prompt>"
   ```

   The handoff prompt is fixed text plus the spec path and phase: run the
   named phases of the scaffold loop for this spec, follow `AGENTS.md`, use
   no delegation and no model overrides, commit nothing, and stop when
   `/review-check` is green or when blocked, writing a short
   `## Phase handoff` note in the spec.
4. **Verify in the worktree,** independently of the session's claims:
   - the full gate passes (`toolchain.sh` all steps);
   - every changed or added path is in the plan's `## Files to touch` or the
     spec itself; anything else fails the run;
   - for `--phase implement`, no test file changed (hash comparison with
     the starting commit); for `test-first+implement`, test files are
     allowed and reported.
5. **Record and hand back.** Write `results/<run-id>/result.json` and one
   ledger line: mode `handoff`, phase, model, fingerprint (harness name and
   version included), wall time, gate outcome, scope outcome, and the
   session transcript path. Print the worktree path and next step. Exit 0
   when verified, 10 when the session stopped blocked or the gate is red,
   4 on a scope violation, 3 on infrastructure (harness crash, timeout).
6. **The frontier orchestrator** then runs `/review` and, for meaningful
   work, `/review-adversarial` on the worktree's diff, fixes or re-hands,
   brings the changes into the feature branch (`git merge --squash` or a
   patch), removes the worktree, and records the verdict with
   `delegate-run.sh record-review <run-id> pass|model-defect|packet-defect`
   (packet-defect here meaning a spec or plan defect).

The runner never merges, commits to the feature branch, or pushes.

## Orchestrator wiring

- `/delegate` gains a "Phase handoff" section: when `policy` prints `auto`
  and the spec's plan is approved, offer the handoff, run it, and continue
  with review on exit 0; on exit 10 read the session's handoff note and
  either fix with the frontier model or re-hand with a short hint.
- `/unattended start` asks which phases go local and which model, recorded
  as standing decisions.
- Any orchestrator client can call it: Claude Code, Codex, and Pi only run
  a shell command. Only the local session itself needs Pi.

## Scoring

The same probation rules as the single-file runner, keyed by a new bucket
`phase:<phase>` instead of file size. A review verdict scores the handoff
run as a whole. The harness and its version join the fingerprint, so a Pi
upgrade starts a fresh record, as a runtime change does today.

## Acceptance

- A smoke test drives `handoff` with a stub harness script in place of Pi
  (it edits a planned file, or a forbidden file, or a test, or hangs, or
  exits non-zero) and asserts each exit status, the scope audit, the test
  hash check, the timeout, and the cleared environment (no unlisted
  variable reaches the stub).
- One recorded real run in a consumer project, graded by frontier review,
  before `/delegate` offers handoff by default.

## Not in v1

Multi-session parallelism, per-file attribution inside a handoff, a
container sandbox (the worktree, cleared environment, and scope audit are
the v1 containment; Pi's tool allowlist is not OS containment), harnesses
other than Pi, and local review or planning.

## Open questions

- **Dependencies in an isolated copy.** A worktree has no ignored
  `node_modules` (or virtualenv). Options: a `toolchain.sh` `install`
  step run in the worktree, or linking the checkout's dependency
  directory. The same question applies to the single-file runner's scratch
  copy, which also omits ignored files: its trial runs reported typecheck
  and tests "red before the run and still red" on every file, which may
  have been missing dependencies rather than missing plan files. Verify
  before relying on its partial-gate results.
- **Frontier tokens.** The handoff should cut frontier cost well beyond
  per-file delegation; record the frontier session's totals for the first
  real runs to confirm it.
