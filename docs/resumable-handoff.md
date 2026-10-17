# Resumable local phase handoff — draft spec

**Status:** implemented (2026-10-15) as Pi RPC segments under an inactivity
lease, a detached launch, `handoff-status [--wait]`, `handoff-resume`, and
`handoff-stop`; the four-hour hard limit is removed. Deterministic smoke
coverage drives an RPC stub harness and real Pi 1.3.0 against a loopback
stub (green, graceful pause at a ceiling, resume to one ledger outcome).
The real local-model trial that pauses and resumes (acceptance plan, final
paragraph) is still open. Spike evidence:
[Plumbing spike](#plumbing-spike-2026-10-15). The consumer-facing guide
(controls, exit codes, log locations) is
[`workflow/docs/local-executor.md`](../workflow/docs/local-executor.md#supervising-a-handoff),
installed as `docs/local-executor.md`; the runner's help points there.
**Last updated:** 2026-10-16

## Goal

Let a productive local Pi handoff run as long as the work requires without
turning one fixed wall-clock duration into a destructive failure. Replace the
current four-hour terminal timeout with:

- a renewable inactivity lease that detects silence or a stuck operation;
- a recoverable checkpoint (pause) rather than discarding the logical run
  when the lease expires without activity;
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

### 2. No time-based segment boundary (decided 2026-10-15)

A run continues for as long as the lease keeps renewing; the four-hour limit
is removed rather than turned into a periodic checkpoint. A new segment starts
only when a run pauses (lease expiry, operator stop, or the optional ceiling)
and is resumed. There is no default absolute total duration.

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
- closing stdin shuts Pi down promptly. It does **not** wait for the run to
  settle: EOF during a run abandons it with no `agent_settled`. The runner
  closes stdin only after `agent_settled` or a completed `abort`.

The runner holds the only write end of a FIFO. An inline Perl supervisor (the
same dependency `bounded` already uses) reads that FIFO and relays it into a
real `pipe()` that is Pi's stdin, closing the pipe when the FIFO reaches EOF.
Pi never reads the FIFO itself: on macOS, Node never sees EOF on a FIFO stdin.
Bash process substitution would also give Pi a pipe, but Codex's macOS sandbox
denies opening `/dev/fd/N`, which Bash 3.2 needs for it. Pi stdout goes
directly to the raw segment event log, a regular file, so Pi can never block
on a slow reader. The runner tails that file, consumes complete LF-delimited
records, correlates command responses by ID, and preserves every session event.
Pi stderr remains a separate diagnostic log. The supervisor also puts Pi in
its own process group, records its pid, and writes its exit status atomically;
that file, not a shell pipeline or `kill -0`, is the authoritative process
status.

The plumbing spike below established these constraints on macOS's system
Bash 3.2, on Linux, and inside Codex's macOS sandbox. No separate shipped
helper file is needed.

The runner is launched **detached** from the orchestrator's tool call. A
handoff runs for hours; Claude Code caps a foreground shell call at 10 minutes,
and Codex commands are time-limited too. Because Pi exits as soon as the runner
dies (stdin EOF), a tool timeout that killed an attached runner would also
abandon the session mid-run. `handoff` therefore double-forks into a new
session (`POSIX::setsid` in Perl; macOS has no `setsid` command), prints the
run ID and status path, and returns at once. The orchestrator then calls
`handoff-status <run> --wait <seconds>`. Each call blocks for at most the
given time (below the client's tool limit), returns early when the run
reaches a terminal or paused state, and exits with that outcome's status. All
three clients use the same flow.

### 4. Pause only at a durable point when possible

When lease expiry or the absolute ceiling asks for a checkpoint:

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
`abort`. Only if RPC does not return idle may the runner use signals. Pi's
bash tool runs each command in its own process group, so a signal to Pi's
group alone does not reach a running tool: Pi's `TERM` handler kills those
groups, but `KILL` orphans them. The fallback therefore sends `TERM` to Pi's
group, waits, then enumerates Pi's live descendants (`ps -axo pid,ppid,pgid`)
and kills their process groups before sending `KILL` to Pi. Codex's macOS
sandbox denies `/bin/ps`. There the sweep is skipped and logged, the `TERM`
grace is the only cleanup, and the result records that tool processes may
have been orphaned. Forced pause keeps
the same artifacts but records that the last model generation, tool result, or
file operation may be incomplete.

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
counts, changed-path count, lease timing, elapsed time, and any optional
absolute ceiling. It sends no prompt and uses no model tokens. It never talks
to the live Pi process: only the supervising runner holds the RPC pipe, so a
second writer is impossible by construction. Status reads `state.json`, the
segment's `status.json` and event log, and the append-only session file,
which Pi writes entry by entry.

Field trials showed a 540-second wait that printed nothing until it
returned, then a snapshot whose last progress lines were mostly
heartbeats. `--interval <s>` adds one bounded line per interval while the
call waits: runner and Pi alive, seconds since the last activity and the
last event, the running tool and its age, lease left, and tool calls (by
sanitized tool name), retries, compactions, and changed paths since the
previous line. The lines are mechanical: event types and counts only, no
message, argument, or result content. Each snapshot ends with
`cursor: <segment>:<byte offset>` into that segment's `events.jsonl`;
`--since <cursor>` replaces the raw tool lines with counts of the events
after it, across later segments. The cursor belongs to the caller, not to
`state.json`, so two observers never move each other's position. Without
`--interval` the wait stays silent, as before. Whether Claude Code or Codex
display a command's output before it returns is client behavior, not
verified here.

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
feed `paused`, lease renewal, or forced-pause records into
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
| `12` | `handoff-status --wait` only: still running when the wait expired |
| `10` | Session settled but final gate stayed red; frontier takes over |
| `4` | Integrity violation; worktree retained |
| `3` | RPC, process, endpoint, or verifier infrastructure failure |
| `2` | Usage or precondition refusal |

On exit 11, print the worktree, status path, reason for the pause, last durable
session event, whether the stop was graceful or forced, and the exact
`handoff-resume` and `handoff-clean` commands.

## Migration

- Introduce `DELEGATE_HANDOFF_LEASE_SECONDS` and optional
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
- In flight, the same scope rules are checked after tool calls (at most once
  every `DELEGATE_HANDOFF_SCOPE_CHECK_SECONDS`, default 5, read-only with
  `GIT_OPTIONAL_LOCKS=0`). A violation aborts the session at once, without a
  checkpoint steer, records `early_scope_stop` in `state.json`, and the
  unchanged post-segment audit ends the run as an integrity stop (exit 4,
  worktree kept, no gate, no commit). Added 2026-10-16 after a field trial in
  which a local model edited an implement-phase test after a compaction and
  the audit refused it only when the session settled, 39 minutes later.
- After each `compaction_end`, the runner sends one fixed steer restating
  the scope rules (the plan's files, or their count when the list is long;
  test immutability in the implement phase; no commit or branch change; stop
  and record a conflict in `## Phase handoff` instead of editing a test).
  Pi cannot append them to its default compaction summary. A steer that is
  not accepted is reported as progress, not treated as a failure.
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
4. lease expiry or the absolute ceiling queues one checkpoint steer and pauses
   at `agent_settled` without a signal;
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

After deterministic smoke coverage, run one real local-model trial that hits a
deliberately short absolute ceiling, pauses, resumes the same session, passes the
full gate, and receives frontier review. Do not replace the current handoff
path by default before that evidence exists.

## Non-goals

- Resuming a one-file non-streaming HTTP generation (that mode was
  removed on 2026-10-17).
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
- Pi 1.3.0 [RPC Extension UI](https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/rpc-extension-ui.md) and [JSON Event Stream](https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/json.md), read from the installed npm package on 2026-10-15, MIT: dialog methods block until an `extension_ui_response`; `ctx.hasUI` is true in RPC mode; event and retry record shapes.

These references establish Pi's interfaces, not that the proposed Bash
controller or recovery semantics work. The plumbing spike and acceptance tests
must establish that locally.

## Plumbing spike (2026-10-15)

**Question:** can the stack-neutral Bash runner drive Pi 1.3.0 RPC portably,
with no new runtime dependency? **Answer: yes**, with three changes to the
draft design: Pi's stdin is a supervisor-relayed pipe rather than the FIFO
itself, stdin EOF is not a graceful stop, and signal fallback must reach tool
process groups. A follow-up the same day added the orchestrator side: the
runner must launch detached, and under Codex it needs network access.

**Setup.** A Bash controller library and sixteen scenarios, kept out of the
repository as spike code, driving real `pi` 1.3.0 against
`scripts/delegate-stub-server.py` on 127.0.0.1. Pi ran exactly as `handoff`
runs it: `env -i` with only `PATH`, `HOME`, `LANG`, `TERM=dumb`,
`PI_CODING_AGENT_DIR=<per-run dir with generated models.json>` and the
credential variable, then
`pi --mode rpc --approve --provider stub --model stub-model --session-dir <dir>`.
Platforms: macOS 26 `/bin/bash` 3.2.57 (Node 26.8), and Docker
`node:24-bookworm-slim` with Bash 5.2.15, Node 24.22 and
`@earendil-works/pi-coding-agent@1.3.0` (CI uses ubuntu-latest, Node 24, Pi
1.3.0). Both platforms produced the same result in every scenario. This shows
plumbing only. A stub endpoint says nothing about real-model behaviour.

| # | Requirement | Observed |
| --- | --- | --- |
| 1 | Start with isolated provider and cleared environment | `get_state` reports provider `stub`, model `stub-model`; stub received `Authorization: Bearer <value of the named variable>`; no global `~/.pi` extension records appeared |
| 2 | Correlate commands | `prompt`→`{"id":"c1","type":"response","command":"prompt","success":true,"data":{"disposition":"started"}}`; `steer`→`disposition:"queued"`; a second `prompt` during a run without `streamingBehavior`→`success:false`; malformed input→`{"type":"response","command":"parse","success":false,…}` with no ID; `get_entries` with an unknown `since`→`success:false` |
| 3 | Retain stdout/stderr, keep exit status | stdout as a regular file never blocks Pi; records up to 1,815,032 bytes (`tool_execution_end` for 200 KB of output) parsed; U+2028 inside strings did not split records; stderr separate; exit status from the supervisor file matched `waitpid` |
| 4 | Checkpoint and `agent_settled` | During a `sleep 3` tool: `queue_update` (steer queued) → `tool_execution_end` → `turn_end` → `queue_update` (drained) → next model request carried the steer text and the tool result → `agent_settled {"aborted":false}` |
| 5 | Shutdown by closing stdin | Idle: exit 0 in 120–160 ms. **During a run: exit 0 in ~130 ms with no `agent_settled`**; the session keeps the user prompt and no reply |
| 6 | Reopen persisted session | `--session <file>` with the same `--session-dir`: same `sessionFile`, `messageCount` 3, `get_entries since=<last leafId>` empty, next request carried prior history. After a forced abort, reopen sent `["system","user","user"]` (original task, then resume prompt). `--session-id <uuid>` creates or reopens a runner-chosen ID |
| 7 | Timeout and cancellation | `abort` against a 60 s silent request: `agent_settled {"aborted":true}` then the abort response, 180–270 ms, `isStreaming:false` afterwards. `abort` during `sleep 300` in a tool killed it in 90–420 ms. Fake Pi ignoring `TERM` with a grandchild: group `KILL` cleaned both (exit 137). Controller `SIGKILL`: Pi exited in ~110 ms (stdin EOF) |
| 8 | macOS Bash 3.2 and Linux | Same results; constraints below |
| 9 | No model calls for status, one writer | 15 `get_state`/`get_entries`/`get_session_stats` calls after a run: 1 model request total. Only the runner holds the pipe |

**Failures found and their fixes:**

- **FIFO stdin never reaches EOF on macOS.** With a FIFO, no writer remained
  (`lsof`) but Pi kept running; plain Node reproduced it (`data` but no `end`).
  Linux delivers EOF. Process substitution (`exec 8> >(…)`) fixed it outside
  Codex but failed inside Codex's sandbox (`/dev/fd/62: Operation not
  permitted`). The final design keeps the FIFO for the runner and has the Perl
  supervisor relay it into a `pipe()`. Perl's blocking `sysread` sees FIFO EOF
  on macOS. All scenarios passed again on macOS, inside the sandbox, and on
  Linux.
- **EOF is not graceful** (row 5). Pi 1.3's "orderly shutdown" disposes the
  runtime; it does not finish the run. Close stdin only after settling.
- **Tool commands run in their own process groups.** With `sleep 300` in a
  tool, Pi's pgid was 28593 and the tool's 28662. Group `TERM`: Pi cleaned up
  the tool (exit 143). Group `KILL`: the tool survived as an orphan (exit
  137). This also applies to today's 4-hour timeout (`TERM`, 2 s, `KILL`).
- **Extension dialogs block in RPC mode.** `ctx.hasUI` is true in RPC (false
  in print mode). A project extension calling `ctx.ui.confirm` hung the run
  until answered. Auto-answering `{"type":"extension_ui_response","id":…,"cancelled":true}`
  let it settle (the tool was blocked as the extension chose). The scaffold's
  own `agentic-hooks.ts` and `pi-subagents` only emit fire-and-forget
  `notify`/`setWidget` records.
- **An unknown model ID does not fail startup.** `--model no-such-model`
  printed a stderr warning and used it as a custom ID (exit 0). The runner
  must compare `get_state` provider/model with the profile before prompting.

**Orchestrator-side follow-up (same day).** Checked with
`codex sandbox` from codex-cli 0.162.1 (the repository's live acceptance pins
0.146.0). It applies Codex's seatbelt policy to a command with no model call.

- *Network.* Built-in profiles `:workspace` and `:read-only` blocked even
  loopback (`curl` to the stub: exit 7), so the runner's endpoint check and
  Pi's model calls fail. The legacy
  `-c sandbox_workspace_write.network_access=true` had no effect on a
  permission profile. A profile extending `:workspace` with network enabled
  worked: `-c 'permissions.handoff.extends=":workspace"'
  -c 'permissions.handoff.network.enabled=true' -P handoff` → HTTP 200. Under
  it, the steer, reopen, abort, EOF, parent-kill, status and unresponsive
  scenarios matched the unsandboxed results.
- *Pi packages.* In a `custom --full` project, Pi's startup `npm install` of
  `pi-subagents` failed: DNS (`ENOTFOUND`) under `:workspace`, and `EPERM`
  on `~/.npm/_cacache` with network enabled. Pi then exited. Adding
  `npm_config_cache=<result dir>/npm-cache` to Pi's cleared environment fixed
  it. A fresh worktree never has the ignored `.pi/npm/`, so every handoff
  installs the package again unless the runner seeds it from the primary
  checkout.
- *Process listing.* `/bin/ps` is denied, so the descendant sweep cannot run
  there (see decision 4).
- *Detached launch.* A caller in its own process group launched the spike
  runner through a Perl double fork with `setsid`, then was `SIGKILL`ed as a
  group after 2 s. The runner finished its steer and abort scenarios on macOS,
  on Linux, and inside the sandbox. Launched from a sandboxed command that
  exited at once, the runner also finished, and it kept the sandbox's network
  permission.

**Bash constraints the controller must respect** (each one broke the spike):

- Never call controller functions inside `$(…)`. The subshell shares the fd 9
  read offset, so it consumes records, but drops the state it parsed
  (`agent_settled` was lost). Its `exec 8>&-` also leaves the parent's writer
  open. Return results in globals.
- `kill -0` is true for an unreaped zombie, and Bash 3.2 has no
  `wait -n`, no `$!`/`wait` for process substitution, no `coproc`, no `{fd}`
  allocation, no `$'\u…'`, and no fractional `read -t`. Use fixed fds (8, 9),
  `sleep 0.1` polling, and the supervisor's exit file.
- Every long-lived child started while fd 8 is open must get `8>&-`. A
  `sleep 600` that inherited it kept Pi alive after the controller died.
- The supervisor reaps Pi on its next 0.5 s poll. After a forced `KILL`, wait
  for the status file to appear before reading it. Linux exposed this race
  (an empty exit status); three Linux repeats then reported 137.
- `${line%pattern}` on a 1.8 MB record ran for more than 20 s in Bash 3.2 and
  5.3, in both UTF-8 and C locales. Prefix `case` matching, `${line:0:40}`,
  and one `jq` call each took under 0.1 s. Route `message_update` records by
  prefix and never use suffix removal on records.

**Found outside RPC (affects v1 handoff today).** Running real Pi with
`--approve` in a fresh `custom --full` project installed `pi-subagents` into
`.pi/npm/` (network required) and left `?? .pi/npm/.gitignore` untracked: Pi
writes `*` / `!.gitignore` there, so the file un-ignores itself. JSON print
mode reproduced this. The handoff scope audit lists untracked files, so a real
`handoff` in a `--full` project would integrity-stop on its first run, and a
primary checkout where Pi has run fails the clean-tree precondition. The
stub-harness smoke test cannot see it.

**Event volume.** Each tool update repeats cumulative output: 200 KB of
output produced a 4.9 MB event log. JSON mode has the same behaviour today. The
pump routes tool updates without `jq`, and the status packet stays bounded.

## Implementation plan (approved 2026-10-15)

Ordered so that each step leaves the gates green.

0. **Prerequisite fix** (shipped with this spec, before the rest, since it
   affects v1 today):
   ignore `.pi/npm/` in `stacks/{python,typescript,custom}/project/.gitignore`
   (and any other flavor that installs `.pi/settings.json`), with a
   `scripts/bootstrap-stack.sh` `--update` migration like the existing
   `.agentic/delegate/` entry, and a smoke assertion that a real
   `pi --approve` start in a `--full` project leaves `git status` clean. Also
   give today's `bounded` hard-timeout path the descendant-group sweep before
   `KILL`, and set `npm_config_cache` inside the run directory in Pi's
   environment (seeding the worktree's `.pi/npm/` from the primary checkout
   when present).
1. **`workflow/bin/delegate-run.sh`** (single source; the renderer copies it
   to every flavor):
   - RPC controller functions (`rpc_start`, `rpc_send`, `rpc_pump`,
     `rpc_await`, `rpc_await_settled`, `rpc_shutdown`, `rpc_kill_tree`) as
     spiked (FIFO plus Perl relay supervisor), plus dialog auto-cancel logged
     to the segment log and a model/provider check from `get_state`.
   - Detached launch: `handoff` validates preconditions in the foreground
     (refusals still exit 2 synchronously), then double-forks with `setsid`,
     prints the run ID, status path and the next command, and exits 0.
     `--foreground` keeps today's attached behaviour for terminals and tests.
     `handoff-resume` launches the same way.
   - Lease/segment supervisor loop: activity classifier per the decision-1
     table, `steer` checkpoint, grace, `clear_queue`+`abort`, signal fallback;
     writes `segments/NNNN/{events.jsonl,harness.log,status.json}`.
   - `state.json` for the logical run (snapshot SHA, spec and plan hashes,
     fingerprint, session file and ID, last entry cursor, segment list,
     absolute-ceiling deadline), written atomically.
   - `cmd_handoff` switches to RPC segments; pause path runs `audit_handoff`
     without the gate; exit 11.
   - `cmd_handoff_status [--wait <s>]` (read-only; waits at most `<s>`, returns
     early on a terminal or paused state, and exits with that outcome's code,
     or 12 "still running" when the wait expires) and `cmd_handoff_resume` (refusal list
     from decision 5, reopen with `--session`, one fixed resume prompt).
   - `render_pi_event` reused for RPC events; `watch_pi_events` replaced by
     the pump in the controller process, so no second reader exists.
   - Env controls `DELEGATE_HANDOFF_LEASE_SECONDS`,
     `DELEGATE_HANDOFF_MAX_TOTAL_SECONDS`,
     `DELEGATE_HANDOFF_GRACE_SECONDS`; legacy `DELEGATE_HANDOFF_TIMEOUT` keeps
     its hard meaning with a deprecation warning. Usage text and exit table.
   - Ledger: segment records go to `segments/`, not the ledger; one terminal
     ledger line per logical run.
2. **`scripts/delegate-stub-server.py`**: optional streamed `tool_calls`
   responses (the spike's queue format already works), and a `.hang` marker
   that holds a request until the client disconnects.
3. **`scripts/smoke-test-delegate.sh`**: a stub RPC harness (Bash script that
   speaks the JSONL protocol, scripted per mode) covering acceptance items
   1–13, plus a real-Pi-against-loopback block (skipped when `pi` is absent)
   for steer→settle, abort, EOF, reopen, dialog cancel, and the tool-group
   sweep. CI already installs Pi 1.3.0, so CI exercises the real-Pi block.
4. **`workflow/commands/delegate.md`** ("Phase handoff") and
   **`workflow/commands/unattended.md`**: one flow for Claude Code, Codex and
   Pi orchestrators: launch (returns at once), then repeat
   `handoff-status <run> --wait 540 --interval 60 --since <cursor>` until it is no longer 12 (540 s stays
   under Claude Code's 10-minute tool limit), then act on the exit code
   (0/10/11/4/3). Exit 11 handling and `handoff-resume`; unattended behaviour
   per decision 3 below. A **Codex note**: the handoff needs network access
   to the local endpoint (and to the npm registry when Pi packages are not
   seeded); in Codex's default workspace sandbox, ask the human to approve
   running it outside the sandbox or with a network-enabled permission
   profile, or to run it in a terminal. Do not edit the project's Codex
   sandbox configuration from the command.
5. **Docs**: this spec (status), `docs/local-phase-handoff.md` (RPC,
   exit 11, pause/resume), `workflow/docs/` user-facing section if
   `/delegate` docs live there, `AGENTS.md` current state, README if commands
   are listed there; `docs/influences.md` only if an outside source prompted
   a change (none so far beyond Pi's docs, already cited here).
6. `bash scripts/render-client-surfaces.sh`, then every gate in `AGENTS.md`.

Correction on implementation (2026-10-15): the default 14,400 s hard limit is
removed rather than kept until the real-model trial. With the decision for no
time-based boundary, a stopped run now pauses resumably instead of being
destroyed, and the lease handles silence; an operator can still set
`DELEGATE_HANDOFF_MAX_TOTAL_SECONDS`. The real-model pause/resume trial
remains the open acceptance item.

## Decisions (settled 2026-10-15)

1. Step 0 ships first, in the PR that carries this spec.
2. No time-based segment boundary; the lease alone governs a live run.
3. `/unattended` may resume a paused run itself, with no count limit, under
   its standing consent. Each pause and resume is logged under
   `## Unattended decisions`; the optional absolute ceiling, when configured,
   still stops it.
4. Extension dialogs are auto-cancelled and logged.
5. An absolute ceiling is raised by pausing and resuming with
   `handoff-resume --max-total <s>`; no live channel.
6. `handoff` launches detached by default; `--foreground` stays.
7. Codex network access is documented (approve or run outside the sandbox);
   the scaffold ships no Codex permission profile.
8. Each pause writes a `### Paused handoff` note in the spec.

## Cleanup when a background run exits early

Checked on macOS and Linux with a tool command (`sleep 300`) running:

| What dies | Observed | Left behind |
| --- | --- | --- |
| Runner (`SIGKILL`) | Supervisor sees FIFO EOF, closes Pi's stdin; Pi exits and kills its tool; supervisor writes exit status 0 | Lock, `state.json` saying running, worktree |
| Runner and supervisor (`SIGKILL`) | Pi's stdin pipe closes; Pi exits and kills its tool | Same, and no exit-status file |
| Pi itself (`SIGKILL` or hard crash) | Tool process group survives (spike `group-KILL`) | Orphaned tool, plus the above |
| Graceful pause, verified finish, or forced abort | Runner cleans up normally | Worktree only (by design) |

The runner cannot run a cleanup trap after `SIGKILL`, so the remaining
cleanup happens on the next touch, without a daemon:

- The lock records the runner's PID and, where `ps` is allowed, its start
  time. A command that finds the lock held by a process that no longer exists
  (or a reused PID with a different start time) reports it and takes the lock
  over. Inside Codex's macOS sandbox, `ps` is denied, so a reused PID can make
  a stale lock look live; the message names the lock to remove by hand.
- `state.json` records runner, supervisor and Pi PIDs and the tool process
  groups last seen in `tool_execution_start`. `handoff-status` reports such a
  run as `orphaned` when none of them is alive and no terminal state was
  written. If a recorded tool process group is still alive, it reports that
  too.
- `handoff-resume` accepts an `orphaned` run like a forced pause: it first
  kills any surviving recorded tool group, runs the same scope and test-file
  audits, then reopens the session. `handoff-clean` does the same kill before
  removing the worktree.
- Process inspection uses `kill -0` on recorded PIDs and process groups (checked inside Codex's sandbox: probe and group `TERM` both work), not
  `ps`, so it also works inside Codex's sandbox.

Still open, to be answered by field evidence rather than decisions: normal
event gaps for the local endpoint during long inference and long tools, which
set the initial 60/15-minute lease values.
