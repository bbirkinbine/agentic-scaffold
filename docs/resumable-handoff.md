# Resumable local phase handoff — draft spec

**Status:** direction approved; implementation not started
**Last updated:** 2026-10-16

## Goal

Let a productive local Pi handoff run as long as the work requires without
turning one fixed wall-clock duration into a destructive failure. Replace the
current four-hour terminal timeout with:

- a renewable inactivity lease that detects silence or a stuck operation;
- a bounded session segment that ends at a recoverable checkpoint rather than
  discarding the logical run;
- `handoff-status` for deterministic, token-free inspection;
- `handoff-resume` for continuing the same Pi session and worktree;
- an optional absolute total ceiling for an operator or unattended policy that
  wants one, disabled by default.

A pause is not success. The complete handoff still passes the existing scope,
test-file, branch, and full-gate audits before the runner creates its temporary
handoff commit. Frontier review remains mandatory.

## Current behavior and problem

`delegate-run.sh handoff` runs one headless Pi process in JSON mode under a
14,400-second wall-clock watchdog. When that limit expires, the watchdog sends
`TERM` to the process group, waits two seconds, sends `KILL`, records an
`infrastructure` result, and keeps the worktree. The partial filesystem and Pi
session directory survive, but the runner has no supported continuation path
and performs no post-timeout scope audit.

The limit protects against abandoned processes, but it also stops a healthy
slow local model. Raising `DELEGATE_HANDOFF_TIMEOUT` moves the collision rather
than distinguishing inactivity from forward progress. Removing every bound
would allow an unproductive but noisy loop to run indefinitely. The runner
needs recoverable supervision rather than a single terminal timer.

## Terms

- **Logical handoff:** one approved phase from its initial prompt through final
  verification, possibly spanning several Pi processes.
- **Segment:** one supervised Pi process lifetime within a logical handoff.
- **Meaningful activity:** a Pi event or repository milestone that demonstrates
  new work, not merely that a process still exists.
- **Inactivity lease:** the interval after meaningful activity during which the
  segment may continue without diagnosis.
- **Checkpoint request:** a steering instruction asking Pi to leave the
  worktree resumable, update the phase-handoff note, and settle.
- **Paused:** resumable, unverified partial work. It is neither a model-quality
  failure nor an infrastructure failure.
- **Absolute ceiling:** an optional total elapsed limit across every segment of
  a logical handoff. It never renews automatically.

## Decisions

### 1. The normal control is an inactivity lease

The runner tracks the last meaningful activity. A healthy assessment renews
only the lease; it never changes an explicitly configured absolute ceiling.
The check is local shell/RPC processing and invokes no model.

Count as meaningful activity:

- model text or thinking deltas;
- a tool update or tool completion;
- a completed assistant turn;
- a new durable Pi session entry;
- a changed planned path since the previous assessment.

Do not treat these alone as unlimited forward progress:

- process liveness;
- repeated identical retry errors;
- repeated compaction failure;
- heartbeat output from the runner;
- an unchanged long-running tool with no output;
- edits that only oscillate between previously seen manifests.

At lease expiry, write a bounded status snapshot and classify the segment:

| State | Evidence | Action |
| --- | --- | --- |
| `active-model` | Recent model deltas or a new turn | Renew the full lease |
| `active-tool` | Tool updates or a plausible live command | Renew the full lease |
| `recovering` | Bounded retry or compaction recovery | Renew a shorter grace lease |
| `settled` | `agent_settled` and Pi is idle | Continue to independent verification |
| `silent` | Process alive, no meaningful activity | Request a checkpoint; pause if it settles |
| `failed` | Process exited or terminal protocol error | Record infrastructure failure |
| `unknown` | Evidence cannot distinguish slow from stuck | Short grace, then checkpoint; never ask an AI by default |

The initial values are configuration, not claims about model capability. Start
with a 60-minute inactivity lease and a 15-minute recovery/unknown grace, then
tune from real event gaps. A model or project may require a longer lease.

### 2. Four hours becomes a segment boundary, not a default hard kill

At the segment boundary, the runner asks Pi to checkpoint at the next safe
turn boundary. Productive work may cross any number of segments. There is no
default absolute total duration.

The boundary exists to keep one process and one diagnostic log bounded and to
exercise resumability before an overnight session depends on it. It is not an
assertion that the phase should be finished.

A configured absolute ceiling is still available for unattended policy or
resource constraints. Reaching it produces the same checkpoint request first;
a forced abort occurs only after the configured grace period. It is never
extended by status events or an AI opinion. A human may explicitly extend it.

### 3. Use Pi RPC mode for supervised segments

JSON print mode streams evidence but has no input channel. Pi RPC mode adds the
control needed without embedding Pi's SDK or adding a Node dependency to the
stack-neutral Bash runner:

- `prompt` starts or resumes the phase;
- `get_state` identifies the durable session and whether Pi is streaming;
- `get_entries` provides a stable session-entry cursor for progress checks;
- `steer` requests a checkpoint after the current assistant turn and its tools;
- `clear_queue` plus `abort` provides a bounded forced-pause fallback;
- closing stdin requests orderly shutdown after Pi settles.

The runner uses one parent-to-Pi FIFO and writes Pi stdout directly to the raw
segment event log. A reader must continuously consume complete LF-delimited
records, correlate command responses by ID, and preserve every session event.
Pi stderr remains a separate diagnostic log. No shell pipeline may become the
authoritative process status.

Before replacing JSON mode, a plumbing spike must prove RPC startup, prompt,
steer, abort, orderly shutdown, credential isolation, and session reopening on
both macOS's system Bash and CI Linux. If a portable Bash RPC controller cannot
meet those constraints, stop and reconsider a small shipped helper rather than
silently falling back to destructive signals.

### 4. Pause only at a durable point when possible

When the lease or segment boundary asks for a checkpoint:

1. Send a `steer` message instructing Pi to stop starting new implementation
   work, finish only the current safe operation, inspect the worktree, append a
   concise `### Paused handoff` entry to the spec, and settle without committing.
2. Continue consuming events through `agent_settled` for a configured grace
   period.
3. Audit the worktree against the starting commit and approved plan.
4. Close RPC stdin and wait for orderly process exit.
5. Persist the session path/ID and last entry cursor.
6. Record the logical handoff as `paused` and exit with a distinct status.

If Pi does not settle within the grace period, clear queued work and issue RPC
`abort`. Only if RPC does not return idle may the runner use process-group
`TERM`/`KILL`. Forced pause keeps the same artifacts but records that the last
model generation, tool result, or file operation may be incomplete.

A pause never runs the final gate and never commits. It does run the scope,
branch, HEAD, and implement-phase test-file audits. An out-of-plan change is
still an integrity stop, not resumable partial work.

### 5. Resume the same logical handoff

Add:

```text
.agentic/delegate-run.sh handoff-status <run-id>
.agentic/delegate-run.sh handoff-resume <run-id> --allow-commit
                                      [--progress quiet|summary]
```

`handoff-status` reads local state only. It reports the logical state, segment,
worktree and process status, last event and age, active tool, retry/compaction
counts, changed-path count, lease timing, segment timing, and any optional
absolute ceiling. It sends no prompt and uses no model tokens.

`handoff-resume` refuses unless:

- the logical run is `paused` and has no live segment;
- the original worktree and `handoff/<run>` branch still exist;
- HEAD remains the original snapshot and no session/verifier commit exists;
- current changes pass the same plan and test-file audits;
- the spec and approved plan still match their recorded hashes;
- the profile, selected model, endpoint, request settings, Pi version, harness
  version, and generated provider configuration match the recorded fingerprint;
- exactly one saved Pi session is identified;
- the caller again acknowledges temporary-commit authority with
  `--allow-commit`.

The resumed RPC process opens the recorded session and receives one bounded
prompt: continue the approved phase from the current worktree, first inspect
its state and the pause note, do not repeat completed work, and finish the
existing `/review-check` obligation. It does not receive a new task or a model
switch.

Each segment writes under:

```text
.agentic/delegate/results/<run-id>/
├── state.json
├── prompt.md
├── pi-agent/
├── session/
└── segments/
    ├── 0001/
    │   ├── events.jsonl
    │   ├── harness.log
    │   └── status.json
    └── 0002/
        ├── events.jsonl
        ├── harness.log
        └── status.json
```

Raw logs are ignored and may contain source, prompts, reasoning, tool results,
and secrets. Progress rendering remains bounded and redacted.

### 6. Score one logical handoff once

A pause or resume segment is operational evidence, not a model outcome. Store
append-only segment records separately from the terminal run result. Do not
feed `paused`, lease renewal, segment rollover, or forced-pause records into
model selection or demotion.

Only the final logical outcome is scored:

- verified and accepted by frontier review: pass;
- session or resumed session ends with a red gate: `needs_frontier`;
- frontier review attributes a defect to the model: model defect;
- plan/spec defect: packet defect;
- transport, RPC, process, or verifier failure: infrastructure, unscored;
- scope, branch, commit, or test-file violation: integrity stop.

`record-review` continues to name the original logical run ID.

### 7. No automatic AI supervisor in v1

The deterministic status packet is enough to establish many active, settled,
retrying, and failed states. An AI cannot reliably distinguish silent healthy
inference from a wedged inference server, and repeatedly asking the frontier
orchestrator would consume tokens and context.

A later opt-in supervisor may read one bounded, redacted status packet only
when the deterministic classifier returns `unknown`. It must be read-only,
may return only `continue`, `pause`, or `unknown`, and cannot extend an absolute
ceiling or write in the worktree. `unknown` defaults to a short grace followed
by a recoverable pause.

## User-visible state and exit behavior

Proposed terminal outcomes:

| Exit | Meaning |
| --- | --- |
| `0` | Full gate and scope audit passed; temporary handoff commit created |
| `11` | Paused and resumable; no final gate or commit |
| `10` | Session settled but final gate stayed red; frontier takes over |
| `4` | Integrity violation; worktree retained |
| `3` | RPC, process, endpoint, or verifier infrastructure failure |
| `2` | Usage or precondition refusal |

On exit 11, print the worktree, status path, reason for the pause, last durable
session event, whether the stop was graceful or forced, and the exact
`handoff-resume` and `handoff-clean` commands.

## Migration

- Introduce `DELEGATE_HANDOFF_LEASE_SECONDS`,
  `DELEGATE_HANDOFF_SEGMENT_SECONDS`, and optional
  `DELEGATE_HANDOFF_MAX_TOTAL_SECONDS` as temporary environment controls.
- Move stable values into the private machine profile only after field evidence
  establishes which belong per model versus per checkout.
- Treat an explicitly set legacy `DELEGATE_HANDOFF_TIMEOUT` as an absolute
  ceiling during one compatibility release and print a deprecation warning.
- Remove the implicit 14,400-second terminal timeout only when pause/resume
  acceptance passes. Until then, the existing hard limit remains in force.
- Never reinterpret an explicitly configured hard timeout as a renewable lease
  without warning.

## Safety invariants

- One writer and one live segment per logical handoff.
- No resume against a changed spec, plan, snapshot, fingerprint, or branch.
- No automatic model or provider substitution.
- No session/verifier commits before final verification.
- No publication from paused work.
- Scope and test-file audits before pause, before resume, and before commit.
- A forced pause is never described as a clean checkpoint.
- Raw session artifacts stay ignored and are never copied into prompts for an
  AI status judge by default.
- Cleanup never removes the primary checkout or a non-handoff branch.

## Acceptance plan

Extend the loopback handoff harness to emulate Pi RPC and prove:

1. prompt acceptance, streamed events, correlated command responses, and
   orderly shutdown;
2. frequent meaningful activity renews a short lease without invoking a model
   or pausing the segment;
3. repeated retries do not renew the full lease indefinitely;
4. a segment boundary queues one checkpoint steer and pauses at
   `agent_settled` without a signal;
5. an unresponsive segment receives clear/abort, then process-group termination
   only after grace expires;
6. pause performs plan, branch, HEAD, and test-file audits but does not run the
   final gate or create a commit;
7. resume reopens the same session and worktree, preserves partial changes,
   appends a new segment log, and can finish green;
8. split JSON records, unknown records, renderer exit, and stderr output do not
   break RPC correlation or replace Pi's exit status;
9. profile, model, Pi, harness, spec, plan, session, branch, and snapshot
   mismatches refuse resume;
10. a paused/resumed logical handoff creates one final ledger outcome and one
    review record;
11. `handoff-status` is token-free and reports active, silent, paused, terminal,
    and orphaned states;
12. an optional absolute ceiling spans segments and cannot renew automatically;
13. legacy `DELEGATE_HANDOFF_TIMEOUT` keeps its hard-limit meaning during the
    compatibility period;
14. every generated stack receives a byte-identical runner.

After deterministic smoke coverage, run one real local-model trial that crosses
a deliberately short segment boundary, resumes the same session, passes the
full gate, and receives frontier review. Do not replace the current handoff
path by default before that evidence exists.

## Non-goals

- Resuming a one-file non-streaming HTTP generation.
- Running several Pi writers against one worktree.
- Switching models during resume.
- Treating a pause as successful delegation.
- Automatically feeding raw session logs to a hosted model.
- Removing operator stop or cleanup controls.
- Guaranteeing recovery from a command that modified resources outside the
  audited worktree.

## External references

- Pi 1.3.0 [Sessions and Context](https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/sessions.md), retrieved 2026-10-16, MIT: persisted sessions, `--session`, `--session-dir`, and continuation semantics.
- Pi 1.3.0 [RPC Mode](https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/rpc.md) and [RPC Commands](https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/rpc-commands.md), retrieved 2026-10-16, MIT: strict JSONL framing, asynchronous command correlation, `prompt`, `steer`, `clear_queue`, `abort`, `get_state`, `get_entries`, `agent_settled`, session switching, and orderly shutdown.

These references establish Pi's interfaces, not that the proposed Bash
controller or recovery semantics work. The plumbing spike and acceptance tests
must establish that locally.

## Open questions before implementation planning

1. Can the existing Bash runner control Pi RPC portably with FIFOs and ordinary
   file descriptors on macOS Bash 3.2 and CI Linux, including cancellation and
   process-group cleanup?
2. Should the segment boundary default remain four hours, or be disabled until
   real completion-time evidence exists?
3. Which event gaps are normal for the current local endpoint during long
   inference and long tools?
4. Should a graceful paused segment exit immediately with 11, or may unattended
   mode resume it automatically under standing consent?
5. How should a human extend an optional absolute ceiling while a segment is
   live without introducing a separate daemon?
