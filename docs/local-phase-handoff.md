# Local phase handoff — draft spec

**Status:** v1 implemented (2026-10-15) as `delegate-run.sh handoff` and
`handoff-clean`, including bounded live progress from Pi JSON events;
smoke-tested with a stub harness, with no real-model run yet.
Differences from the draft below: dependencies come from the stack's own
`toolchain.sh install` in the worktree; a verified run is committed on its
`handoff/<run>` branch so the orchestrator can review and `git merge
--squash` it; the runner requires `--allow-commit` after explicit human
approval for that temporary commit; `handoff-clean` removes worktrees and
branches; the scope audit also allows the spec itself and the regenerated
`docs/specs/README.md`;
the implement phase's test-file rule is a path heuristic (`tests/`,
`__tests__/`, `spec/`, `*.test.*`, `*.spec.*`, `test_*`). Extends
[`docs/local-delegate-runner.md`](local-delegate-runner.md); reuses its
profile, ledger, qualification, and policy.

Review fixes (2026-10-15): scope checks cover the complete tree against the
starting commit, run both before and after the gate, and reject a session or
verifier that commits or changes branches. Pi receives a per-run
`PI_CODING_AGENT_DIR` with a generated `models.json` binding the profile's
endpoint, model ID, context, request settings, and credential variable name
(never its value). No global Pi provider setup is required. An old `pi_model`
alias is accepted only when it matches `<endpoint>/<model_id>`; a different
alias is refused. Phase selection and recording share the harness/configuration
fingerprint, and `status` and `reset` include both phase buckets. These fixes
have regression coverage; an authenticated real-model phase trial remains open.

Pi package fixes (2026-10-15), found by the
resumable-handoff RPC spike (branch `spike/resumable-handoff-rpc`): a real Pi start in a
stack project installs `pi-subagents` into `.pi/npm/` and leaves a
self-unignoring `.pi/npm/.gitignore`, which the scope audit would have stopped
on. Stack `.gitignore` files now ignore `.pi/npm/` (`--update` migrates it), the
runner copies the checkout's installed `.pi/npm/` into the worktree, and Pi's
npm cache lives in the run directory (Codex's sandbox denies `~/.npm`). The
hard limit's `KILL` also reaches process groups the session's tools created;
before, a tool command that outlived Pi's `TERM` handling was orphaned. Where
`ps` is denied (Codex's macOS sandbox), only the session's own group is
signalled.

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
.agentic/delegate-run.sh handoff <spec-path> --allow-commit
                                             [--phase implement|test-first+implement]
                                             [--model <name>]
                                             [--progress quiet|summary]
```

1. **Refuse** unless: the human explicitly approved the temporary commit
   on `handoff/<run>` and the caller acknowledged it with `--allow-commit`;
   the spec's status is `shipping` with an `## Approved implementation plan`;
   the tree is clean; `toolchain.sh ready` passes; and, for `--phase
   implement`, the focused tests exist and are red. Choosing `handoff` mode
   alone is not commit authorization.
2. **Worktree.** `git worktree add` on a new branch `handoff/<run-id>` from
   `HEAD`, outside the checkout (`$TMPDIR/agentic-handoff/<run-id>`).
   Dependencies the gate needs are made available (see open questions);
   ignored secret files (`.env*`, keys) are never copied.
3. **Run the session** with a cleared environment (only `PATH`, `HOME`,
   locale, and the endpoint credential variable the profile names) and a
   wall-clock limit (`handoff_timeout_seconds`, default 4 h):

   ```
   PI_CODING_AGENT_DIR=<result-dir>/pi-agent \
   pi -p --approve --provider <endpoint> --model <model_id> --thinking <level> \
      --session-dir <result-dir>/session --mode json \
      "<handoff prompt>"
   ```

   Pi stdout is retained verbatim as `results/<run>/harness.events.jsonl`;
   Pi stderr remains `results/<run>/harness.log`. In an interactive terminal,
   the runner consumes the JSONL concurrently and prints bounded lifecycle,
   tool start/end, retry, compaction, and elapsed-time summaries. Redirected
   runs default to quiet; `--progress quiet|summary` overrides the default.
   Assistant text, reasoning, tool results, and unbounded arguments are never
   rendered in the summary.

   The handoff prompt is fixed text plus the spec path and phase: run the
   named phases of the scaffold loop for this spec, follow `AGENTS.md`, use
   no delegation and no model overrides, commit nothing, and stop when
   `/review-check` is green or when blocked, writing a short
   `## Phase handoff` note in the spec.
4. **Verify in the worktree,** independently of the session's claims:
   - the full gate passes (`toolchain.sh` all steps);
   - the session and verifier kept HEAD and the worktree branch unchanged;
   - every changed, deleted, or added path, staged or unstaged, is in the
     plan's `## Files to touch`, the spec itself, or its generated dashboard;
     anything else fails the run;
   - for `--phase implement`, no test path changed against the starting
     commit; for `test-first+implement`, test files are allowed and reported;
   - scope and test checks run before and after the gate, so verifier writes
     cannot enter the final commit without being audited.
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
- `/unattended start` asks which phases go local and which model, and asks
  separately for authority to create temporary `handoff/<run>` commits. It
  records both as standing decisions; without the commit authority it uses
  `files` or `none`.
- Any orchestrator client can call it: Claude Code, Codex, and Pi only run
  a shell command. Only the local session itself needs Pi.

## Scoring

The same probation rules as the single-file runner, keyed by a new bucket
`phase:<phase>` instead of file size. A review verdict scores the handoff
run as a whole. The harness and its version join the fingerprint, so a Pi
upgrade starts a fresh record, as a runtime change does today.
`status` shows phase scores for the installed harness (or
`DELEGATE_HANDOFF_HARNESS` override); `reset <model> phase:implement` and
`reset <model> phase:test-first+implement` clear the respective demotion.

## Acceptance

- A smoke test drives `handoff` with a stub harness script in place of Pi
  (it edits a planned file, or a forbidden file, or a test, or hangs, or
  exits non-zero) and asserts each exit status, the scope audit, the test
  hash check, the timeout, and the cleared environment (no unlisted
  variable reaches the stub). It also streams representative Pi JSONL,
  including malformed and unknown records, and checks bounded/redacted
  summaries, raw-event retention, quiet mode, and unchanged ledger outcomes.
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
