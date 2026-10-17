# Delegated run progress

**Status:** implemented and smoke-tested; no real-model progress trial yet.
On 2026-10-17 the one-file `run` mode was removed (see `docs/influences.md`
→ "Single-file delegation removed (2026-10-17)"); its heartbeat and
verification-stage progress went with it, and the handoff progress below is
what remains. Passages about one-file runs are history.
**Last updated:** 2026-10-17

## Goal

Give the frontier orchestrator and the human bounded, real-time evidence that a
local delegated run is alive and what stage it is in, without turning the
delegate runner into another interactive agent UI. Preserve the runner's
verification, timeout, containment, logging, and exit-status behavior.

The first version is deliberately small:

- a one-file `run` call reports elapsed-time heartbeats while the model is
  generating, then names each verification stage;
- a Pi `handoff` renders a compact live summary from Pi's existing JSON event
  stream: lifecycle transitions and bounded tool starts/ends;
- existing one-file result artifacts and complete handoff session events remain
  in ignored result logs for later diagnosis.

This is observability for the local-execution path already implemented in
`workflow/bin/delegate-run.sh`. It does not change which tasks are delegated or
which model performs them.

## Approved implementation plan

1. Extend `scripts/smoke-test-delegate.sh` first with delayed one-file and Pi
   JSONL fixtures that pin heartbeat, quiet-mode, bounded summary, redaction,
   malformed-event, exit-status, ledger, and cleanup behavior.
2. Add `--progress quiet|summary` to `run` and `handoff` in
   `workflow/bin/delegate-run.sh`. Default to `summary` only when stderr is a
   TTY; use a 15-second heartbeat, with `DELEGATE_PROGRESS_INTERVAL` available
   for deterministic tests.
3. Keep curl and Pi as the authoritative foreground processes. Run progress as
   a disposable sidecar so it cannot replace their exit status or block their
   output. Store Pi stdout as `harness.events.jsonl` and keep `harness.log` as
   the separate stderr/diagnostic log.
4. Render the runner into every stack, update the local-runner, phase-handoff,
   provenance, and current-state documentation, then run the full repository
   validation matrix.

The progress behavior applies to every supported delegated execution: Small or
Medium one-file packets and either phase-handoff bucket. Runs shorter than the
heartbeat interval simply produce stage transitions; qualification and model
selection are unchanged. One-file tasks larger than Medium remain unsupported
by the runner rather than receiving a different progress path.

## Success criteria

1. **A quiet run is visibly alive.** During a model or handoff wait longer
   than the configured heartbeat interval, the runner prints the run ID,
   current stage, model, attempt or phase, and elapsed wall time at least once
   per interval.
2. **One-file progress remains protocol-independent in v1.** `run` keeps its
   current non-streaming OpenAI-compatible request and reports heartbeats while
   the request is in flight. It then reports response receipt, extraction,
   formatting, focused tests, baseline-green gate steps, publication, and
   escalation. No server-specific reasoning field is required.
3. **Handoff tool activity is summarized live.** The runner continuously
   consumes Pi's strict JSONL output and prints, at minimum:
   - agent/turn start and settled state;
   - tool name and a bounded safe description at tool start;
   - success/failure and duration at tool end;
   - retry, compaction, and terminal error events.
4. **The default view is bounded.** It does not print raw thinking, generated
   source, complete Bash output, complete tool results, prompts, credentials,
   authorization headers, or unbounded arguments. Paths and commands are
   length-limited and passed through a new allowlisted credential-shaped
   redaction step before display.
5. **Raw evidence remains available.** Before execution, the runner prints the
   result/log location. It stores the complete Pi JSONL event stream as
   `harness.events.jsonl` and Pi stderr as `harness.log` under
   `.agentic/delegate/results/<run>/` without mixing the progress renderer's
   terminal text into those files.
6. **Automation stays quiet.** Progress mode is `summary` when stderr is an
   interactive terminal and `quiet` otherwise. `--progress quiet|summary`
   overrides that choice for `run` and `handoff`. Progress is written to
   stderr; result JSON and exit statuses do not change.
7. **Failure semantics do not regress.** The renderer cannot hide or replace
   the model/harness exit code. Existing process-group timeout, cancellation,
   lock cleanup, integrity-stop, retry, scoring, and candidate-publication
   behavior remains byte-for-byte equivalent where progress is not involved.
8. **All clients see the same behavior.** Claude Code, Codex CLI, and Pi invoke
   the same runner and require no client-specific progress adapter.
9. **Regression coverage is deterministic.** The delegate smoke test proves a
   slow one-file response emits a heartbeat; a stub Pi JSON stream renders
   tool start/end, retry, and error summaries; quiet mode emits none of those;
   sensitive and oversized fields are withheld; and every fixture preserves
   the expected exit status and ledger outcome.

## User-facing shape

Example one-file summary:

```text
delegate-run: progress: run 0007-parser-... — 'coder-a', small; logs: .agentic/delegate/results/0007-parser-.../
delegate-run: attempt 1/3: calling 'coder-a'
delegate-run: progress: generating — attempt 1/3 — 15s elapsed
delegate-run: progress: generating — attempt 1/3 — 30s elapsed
delegate-run: progress: response received — 37s
delegate-run: progress: extracting candidate
delegate-run: progress: verifying — format
delegate-run: progress: verifying — focused tests
delegate-run: progress: verifying — gate steps
delegate-run: green: published src/parser.ts (uncommitted) after attempt 1.
```

Example handoff summary:

```text
delegate-run: progress: handoff handoff-0007-parser-... — 'coder-a', phase:implement; logs: .agentic/delegate/results/handoff-0007-parser-.../
delegate-run: progress: agent started
delegate-run: progress: tool start: read — AGENTS.md
delegate-run: progress: tool end: read — passed (7ms)
delegate-run: progress: tool start: bash — .agentic/toolchain.sh test
delegate-run: progress: tool end: bash — failed (3100ms)
delegate-run: progress: tool start: edit — src/parser.ts
delegate-run: progress: agent settled
delegate-run: progress: independently verifying — plan scope
delegate-run: progress: independently verifying — full gate
```

The summary describes observable actions, not hidden reasoning. A local server
that exposes reasoning text does not make that text part of the default UI.

## Implementation constraints

### One-file calls

`call_model` waits inside foreground `curl` with `stream: false`. A disposable
heartbeat sidecar reports elapsed time while the same request runs and is
stopped before the response is classified. `curl --max-time` continues to own
the per-call model timeout, and the runner collects its exact exit status and
timing fields before applying the existing timeout versus infrastructure
classification.

Do not adopt SSE in this version. Streaming response formats and reasoning
fields vary among otherwise OpenAI-compatible local servers; adding them would
mix transport compatibility work with the small observability change.

### Pi handoffs

Pi already emits strict JSONL in `--mode json`. Redirect its stdout directly to
`harness.events.jsonl`, so no parser or pipe can block Pi or replace its exit
status. A disposable watcher reads complete LF-delimited records from the
appending file, parses recognized event types with `jq`, emits bounded summary
lines to runner stderr, and ignores malformed or unknown records. The untouched
file remains the raw evidence.

Keep Pi stderr in the separate `harness.log` diagnostic file. Pi and the
existing watchdog remain the authoritative foreground process; watcher failure
cannot replace their exit status. Stop and drain the watcher before classifying
the harness result so final records are not lost.

Useful Pi events for v1 are `agent_start`, `agent_settled`, `turn_start`,
`tool_execution_start`, `tool_execution_end`, `auto_retry_start`,
`auto_retry_end`, `compaction_start`, `compaction_end`, and terminal message
errors. Text/thinking deltas and tool-result bodies are retained but not
rendered.

### Redaction and bounds

- Show a read/edit/write path, not file contents.
- Show a Bash command only after credential-shaped redaction and truncate it
  to a fixed byte count.
- Never render environment values, request JSON, headers, prompts, tool
  results, or model response text in summary mode.
- Ignore malformed JSON in the optional renderer while retaining it raw; fail
  the handoff only when the harness itself fails, not because a progress line
  could not be rendered.

## Non-goals

- Replacing Pi's TUI or embedding a child TUI in Claude Code or Codex.
- Showing raw chain-of-thought, reasoning tokens, complete generated code, or
  complete tool output live.
- Streaming one-file candidates with SSE.
- A browser dashboard, notification service, RPC server, or multi-run monitor.
- A persistent `progress.json`, `watch <run>`, or attachment protocol. Those
  remain possible follow-ups if terminal summaries prove insufficient.
- Changing task routing among `direct`, `files`, and `handoff`.
- Changing model qualification, scoring, demotion, retry, or review policy.
- Implementing project-wide model/data-boundary policy.
- Claiming local-model capability from progress output; only gate and review
  establish quality.

## Risks

- A naive pipeline can report the renderer's exit status instead of Pi's or
  leave Pi running after timeout.
- Tool arguments and results can contain secrets even when the tool name looks
  harmless; summary extraction must be allowlisted and bounded.
- Excess output recreates the noise the delegated run was meant to keep out of
  the frontier context. The default should favor one line per meaningful
  transition, not token deltas.
- Some local endpoints remain silent until a complete response. Heartbeats are
  evidence that the runner is waiting, not evidence that the model is making
  forward progress.
- Redirected CI logs should not gain periodic chatter unless explicitly
  requested with `--progress summary`.

## Acceptance plan

Extend `scripts/smoke-test-delegate.sh` and its loopback fixtures to cover:

1. a delayed chat-completion response that exceeds a short test heartbeat and
   still produces the same green candidate and timing record;
2. quiet mode over the same delayed response;
3. a stub handoff harness that emits representative Pi JSONL events slowly,
   including successful and failed tools, retry, compaction, malformed/unknown
   records, and a terminal event;
4. command/path truncation and credential-shaped redaction;
5. harness exit 0, nonzero, and timeout with the renderer active;
6. renderer failure or early exit without deadlocking the harness;
7. unchanged ledger outcomes, raw logs, worktree audits, and cleanup.

Run the repository's full shell, adapter, render, and smoke validation because
the runner is rendered into every stack and invoked identically by Claude,
Codex, and Pi.

## External references

- Pi JSON Event Stream, https://pi.dev/docs/json, retrieved 2026-10-15,
  license/status: Pi repository documentation, MIT. Authoritative for JSONL
  framing and agent, message, tool, retry, and compaction event shapes.

## Resolved decisions

- The default heartbeat interval is 15 seconds.
- Summary mode omits all assistant text and reasoning.
- `harness.events.jsonl` holds raw Pi stdout; `harness.log` remains the
  stderr/diagnostic path.
- Progress applies uniformly to every supported `run` and `handoff` bucket;
  task size changes routing and verification, not observability.
