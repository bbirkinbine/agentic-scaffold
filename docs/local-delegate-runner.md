# Local Delegate Runner

**Status:** single-file mode removed 2026-10-17; the rest of this document is
history. The runner keeps `init`, `qualify`, `discover`, `policy`,
`activate`/`deactivate`, `record-review`, `status`, `reset`, the ledger, the
Wilson scoring, selection, and demotion, now used only by the phase handoff
([`local-phase-handoff.md`](local-phase-handoff.md)). The `run <packet>`
subcommand, the packet format, the scratch-copy verification, the
three-attempt retry loop, publication, and the `small`/`medium` buckets are
gone. The human's reason: a model with repository context and tools should
do better than one restricted to a one-file packet with no tools, even
locally — a stated expectation, not a measurement. The trials below cut the
other way for well-pinned leaf files, which survived review in this mode;
see `docs/influences.md` → "Single-file delegation removed (2026-10-17)" for
the counter-evidence and the condition for revisiting.
**Last updated:** 2026-10-17 (status only; body unchanged since 2026-10-15)

**Implemented.** `workflow/bin/delegate-run.sh` (installed as
`.agentic/delegate-run.sh` with `--full`) provides `init`, `qualify`, `discover`,
`policy`, `run <packet> [--model <name>] [--progress quiet|summary]`,
`record-review`, `status`, and `reset`. The contract's Implement step and
`/delegate` → "Automatic mode"
hand eligible plan files to the runner when `policy` prints `auto`, and
`/review` records verdicts with `record-review`.
Without `--model`, `run` selects from the checkout's `[[project]]`
candidates as specified under **Selection**. `run` covers the
packet header, the bucket recomputed from the file, the scratch snapshot
and red baseline, the three-attempt retry policy with feedback, the
transport rules, filters 1–3, the stale-workspace check, publication, and
the ledger; it refuses a model not qualified for its current setup and
warns, without blocking, on a demoted one. Scoring, the Wilson interval,
and both demotion triggers are computed from the ledger. Tested by
`scripts/smoke-test-delegate.sh` against a stub server, not yet against a
real local model. Differences from the text below: verification compares
each gate step to the baseline instead of requiring a fully green gate (see
filter 2); each verifier command runs under a per-step timeout
(`DELEGATE_STEP_TIMEOUT`, default 900 seconds) in its own process group,
and `run` refuses without `perl`, which provides that watchdog; every run
ends with a summary of wall time, attempts, and which gate steps passed or
could not verify the file; long model calls emit elapsed-time heartbeats in
interactive terminals, with `--progress quiet|summary` available to override
that default; `/delegate` traces each spec and plan requirement on the target
into the packet and refuses a packet that
contradicts the plan, while the runner assembles the packet's mechanical
sections (format 2), and `/review` tags findings by delegated file;
the post-execution audit covers unignored files only, because ignored
writes stay in the discarded scratch tree and the unignored files that
could fake a green result (configs, tests) are already audited, so an
enumerated allowlist of tool artifacts waits for a case where it would
catch something; the
qualification record lives beside the profile and scoring reads each
project's ledger, with no separate stack key; the reachability check is a
`GET /models` within five seconds. `init` prints a draft profile from
each server's listing (never writes it) and `project-types.md` carries the
founding setup sequence; activation is set by editing the profile
(`policy = "auto"` and `activation_approved = true`). Not built: coupled
packets and their plumbing check, and optional `calibrate`.

## Goal

Close the gap between `/delegate` (which writes a handoff packet and stops)
and a working local-execution loop: a stack-neutral runner that sends one
packet to a local model, applies the result in a scratch copy, verifies it, and
either hands a green candidate to frontier review or escalates the task back
to the frontier model. Which local model is used is decided by its recorded
outcomes on the project's own tasks, not by model size, vendor claims, or a
per-task human guess.

The first version discovers the models served by the machine's registered
inference endpoints, qualifies a model with one plumbing check, and then
lets it take real tasks on probation: every run is evidence, selection
ranks models by that evidence, and demotion stops using a model the
evidence shows to be failing. Quality never rests on this evidence — the
gate, the audit, and `/review` check every candidate whichever model
produced it — so the evidence decides efficiency, not safety. Each run makes
at most three attempts on one model; escalation notifies and returns
control and never switches models mid-run.
Automatic historical packet generation, model ladders, held-out tests, and
local orchestration are deferred until this loop has end-to-end evidence.

## Founding interview and optional setup

Local delegation is an optional implementation path within the existing
Spec → Plan → Test-first → Implement → Verify → Review workflow. Setup and
qualification happen during founding or later maintenance, not for every
feature. The scaffold connects to an existing inference service; installing
models or starting a model server is a separate task.

The founding agent follows this sequence, using answers already supplied
in the conversation instead of repeating questions:

1. **Ask about interest and availability.** "Would you like this project to
   use a local model for eligible implementation tasks, and is a server
   already running?" Default delegation to `off`. If the user declines or no
   server is available, continue normal project setup without requiring an
   endpoint.
2. **Ask for the endpoints.** Collect the base URL of each inference server
   the user wants available (a workstation Ollama, a llama.cpp or
   llama-swap host on the LAN, and so on) and, when a server requires
   authentication, the *name* of an environment variable holding its
   credential. Model IDs are discovered from the servers, not typed in;
   see **Discovery** below. For each discovered model the user wants as a
   candidate, confirm the quadruple fields the server does not report
   (quantization, runtime version) and the request settings to pin. Never
   accept a literal secret, and never resolve the variable into the
   conversation, process arguments, log, or profile. The HTTP client
   receives the value without exposing it in its command line, and verifier
   subprocesses run without that credential variable. Do not read other
   harnesses' configuration files to discover these values. Save the entry
   in the private machine profile only after explicit approval, using a
   client flow that visibly confirms the write outside the repository;
   otherwise print the entry for the human to save. Keep machine details out
   of committed interview notes.
3. **Verify and qualify.** Check each endpoint against the runner's
   protocol, then verify runner dependencies and the project's toolchain.
   Run `qualify` on each candidate the user chooses; it takes one request
   per output shape and reports load and generation time. Ask the user to
   order the candidates; published benchmark results or the orchestrator's
   recommendation may inform that order, but they are a prior and never
   count as evidence. If the project's toolchain is not ready (the gate is
   unconfigured), record setup as pending and continue with delegation off.
4. **Activate explicitly.** Present the qualification results and the
   candidate order. Only after approval set this checkout's private project
   policy to `auto`. An endpoint or installed model alone never enables
   delegation. Reuse the saved choice on subsequent sessions.

The orchestrator running the interview and the local delegate are separate
selections. A hosted frontier model remains the orchestrator while this
runner calls the local endpoint directly. Evidence about a delegate says
nothing about that model's ability to orchestrate the workflow; running the
whole loop on a local model is out of scope for v1.

## State and artifact locations

Claude, Codex, and Pi use the same locations; no client owns delegation
state. Keep artifacts separated by lifecycle:

| Artifact | Canonical location | Repository status |
| --- | --- | --- |
| Feature requirements and approved plan | `docs/specs/NNNN-*.md` | tracked |
| Cross-cutting architecture decisions | `docs/adr/NNNN-*.md` | tracked when that profile is installed |
| Project-wide operational handoff | `docs/agent-handoff.md` | tracked |
| Delegate packets, results, scratch data, lock, and ledger | `.agentic/delegate/` | ignored |
| Endpoints, models and their pinned settings, qualification and demotion state, candidates, and `off`/`auto` policy | `~/.config/agentic/local-models.toml` | outside the repository |

A delegate packet is per-run execution state, not a feature spec, ADR, or
project-wide handoff. Store it under
`.agentic/delegate/packets/<spec-id>-<target-slug>.md`; the runner's other
local state lives alongside it. `/delegate` already writes packets there
(it previously used `docs/specs/`, where a second file with the active
spec's number would violate spec-number uniqueness and enter the status
dashboard), and the stack `.gitignore` sources already ignore
`.agentic/delegate/`.
The active spec remains the durable source of requirements and may name a
pending packet path in its phase handoff when resumption context is useful.

The private profile is the only policy source. Do not add activation to
`.agentic/scaffold-state`, a client configuration file, an ADR, or a spec.
Those files either have a different owner or could silently enable a new
checkout. A canonical local checkout path keys policy so moving or cloning a
repository requires fresh activation approval.

## The four decisions, and who makes each

Delegation needs four answers. Each goes to the decider that can answer it
cheapest and most reliably.

| Question | Decider | Mechanism |
| --- | --- | --- |
| Is this task *shaped* for delegation? | Frontier model, checked mechanically | `/delegate` preconditions plus task features recorded in the packet |
| Can *this model* do a task of this shape? | Measurement | A plumbing check to qualify, then the project's own run outcomes; see **Model evidence** |
| *Which* qualified model runs this task? | The runner, from the ledger | Deterministic exploration, then ranking by evidence; see **Selection** |
| Is the produced code good enough? | Gate, then frontier review | Runner checks, full toolchain gate, post-execution audit, existing `/review` |

**Who runs it.** At the implementation handoff, after the required approvals
and test-first evidence, the orchestrator session checks the saved policy.
With `off`, no profile, or no qualified, undemoted candidate for the task's
bucket, it follows the existing implementation workflow without creating a
delegation packet or calling a local endpoint. The mode and candidate list
come from the checkout's entry in the private profile. In `auto` mode, a
selectable candidate and a task
meeting `/delegate` preconditions trigger packet creation, runner invocation, and
reading the result. A plan that touches several files is walked in its
order of operations, one packet per eligible step, so some steps may be
delegated and others implemented by the orchestrator. A green candidate
moves on to the next step, and `/review` runs once the plan's files have
landed; a refusal or `needs_frontier` result means the orchestrator
implements that step itself.
A broken gate or changed workspace must be resolved first. In `off` mode,
`/delegate` retains its manual packet-only behavior and the human may run the
packet by hand.

The human sets policy once (`off` or `auto`), qualifies and orders the
candidates, and can reset a demotion. Per-task routing then follows that
policy and the recorded evidence. Runner policy does not override the
client's permissions.

### 1. Task shape

The frontier model already decomposes work in `/plan` and writes the packet
in `/delegate`. Extend the packet with a machine-readable header so the
runner can accept or refuse without reading prose:

```yaml
format: 2                     # the runner assembles the mechanical sections
targets: [src/pkg/parser.py]  # one entry per file the model returns
target_lines: 140          # summed current size, 0 for new files
expected_lines: 0          # a new file's planned size; sizes the bucket
contract_items: 6          # signatures/types/constants quoted in "Contracts"
visible_tests: 4
test_targets: [tests/test_parser.py]  # focused targets accepted by toolchain test
new_dependencies: false
bucket: small              # derived: see below
```

`bucket` is derived from the counts by fixed thresholds (for example
`small`: one file, ≤150 lines and ≤8 contract items; `medium`: one file,
≤300 and ≤15; `coupled`: two or three files, ≤300 lines in total and ≤15
contract items; anything larger is not delegable). File count is a bucket
dimension like the others, not a fixed rule: evidence is kept per bucket,
and a good record in one never implies another. The thresholds are a
starting point to be corrected by the ledger, not a claim about model
capability. The runner recomputes `target_lines` from the file rather than
trusting the header, so a mislabelled packet cannot land in a smaller
bucket. A new file has no size until it is generated, so `expected_lines`,
the frontier model's estimate, stands in; the runner refuses a packet whose
`bucket` is smaller than its counts give and keeps one that is larger. The
orchestrator routes models by `bucket` before the run, so the two must
agree (a 2026-10-14 trial routed by labels that the runner, then sizing
new files at zero lines, recorded in the other bucket).

A multi-file plan is split into one-file packets in dependency order
whenever each file can reach green on its own once its predecessors have
landed; `/delegate` already does this. A `coupled` packet is only for files
that cannot pass separately — a new type and its sole consumer, or a
signature change and its callers — and only when some candidate has passed
the multi-file plumbing check. Without one, that step goes to the frontier
model.
The single-shot, no-tools, whole-file rules apply unchanged: a coupled call
is still one request returning complete files, never a multi-turn edit.

With `format: 2` the frontier model writes only the sections that need
judgment — task, requirements traced from the spec and plan, contracts, and
out of bounds — and the runner appends the target as it exists in the
snapshot, the full test files, the live failure output from its own red
baseline, and the output contract. Copying those by hand cost frontier
output tokens roughly the size of the file being delegated, which erased
most of the saving for small files, and let the failure output go stale.
Each run saves the assembled message as `results/<run>/prompt.md`.

The judgment the frontier model contributes is *self-containment*: whether
every reference the executor needs is quoted. That cannot be fully checked
mechanically. On escalation, the orchestrator implements the targets and
records one of two causes in the ledger: `packet` if its own implementation
needed a signature, type, or constant the packet did not quote, `model`
otherwise. Packet defects do not count against the model; a rising
packet-defect rate is a signal to fix `/delegate`, not the model.

External research required by the task is completed by the frontier
orchestrator or a focused research subagent before packet creation. Record
source locators, retrieval dates, and license status under the spec's
`## External references`. The packet inlines only the task-relevant,
source-pinned claims; it never includes a raw research corpus or asks the
local delegate to resolve an external reference.

### 2. Model evidence

What a model can do is a property of the quadruple the existing doc already
says to pin — model, quantization, runtime version, harness version — plus
the request settings sent with every call (reasoning mode or thinking level,
sampling parameters), measured against *this project's* tasks. The same
weights with reasoning on and off are two profile entries with separate
records, and so are the same weights served from two machines (MLX through
Ollama on a workstation and llama.cpp through llama-swap on a LAN server
differ in runtime and usually quantization). Parameter count is a prior,
not evidence, and there is no upper or lower bound on model size: a model
the machine can serve is a candidate.

Evidence is used for efficiency, not safety. A poor model costs local time
and frontier redos, never a bad merge: the retry cap bounds its attempts,
and the gate, the post-execution audit, and `/review` check its output the
same way they check frontier-written code. That is why a model can earn its
place on real tasks instead of passing an upfront capability exam, which
would need many prepared fixtures per project and still measure little.
Ten tasks put a model scoring 6/10 anywhere from about 31% to 83% (95%
Wilson interval).

**Profile.** A per-machine file outside the repository (it names local
endpoints, which do not belong in a public tree), for example
`~/.config/agentic/local-models.toml`:

```toml
[[endpoint]]
name = "lan-gateway"
base_url = "http://<host>:<port>/v1"   # must pass the runner's protocol checks
credential_env = "LOCAL_MODEL_TOKEN"   # optional; variable name, never value

[[model]]
name = "coder-a-think"                 # profile entry: weights + settings
endpoint = "lan-gateway"
model_id = "..."                       # as reported by GET /v1/models
quant = "Q8_K"                         # confirmed by the user
runtime = "llama.cpp b5xxx"            # confirmed by the user
context = 131072
timeout_seconds = 900
request = '{"reasoning_effort": "medium", "temperature": 0.6}'  # optional pinned JSON

[[project]]
root = "/canonical/local/path/to/repo"
policy = "off"               # off | auto
candidates = ["coder-a-think", "coder-b"]   # exploration order
activation_approved = false
```

The optional per-model `request` JSON pins serving settings; existing profiles
without it continue to work. Deterministic sampling and lower reasoning may
help strict transformation tasks, but these are model/endpoint choices, not
hardcoded harness policy. Requalify after changing them.

The founding interview above creates or reuses this profile. Resolve `root`
from the physical repository root, without following a remote URL as project
identity; a second clone is a separately approved checkout. The project
entry lists its candidates explicitly and in order; a discovered model that
is not a candidate is never called for the project. Activation changes
`policy` and `activation_approved` together after approval. With no
profile, no approved auto policy, or no selectable candidate for the
bucket, implement with the frontier model. All clients read this same
runner-owned profile rather than their own model configuration.

The runner keeps each candidate's state beside the profile, keyed by model
entry, project, stack, and bucket, and fingerprinted by the quadruple,
request settings, harness version, and server-reported model ID:

| State | Meaning | Leaves it by |
| --- | --- | --- |
| unqualified | Never checked, or its fingerprint changed | Passing `qualify` |
| qualified | Takes real tasks; every run is evidence | Demotion, or a fingerprint change |
| demoted | The evidence shows it failing; not selected | The human resetting it, which starts a fresh record |

**Discovery.** `delegate-run.sh discover` sends `GET /v1/models` to each
registered endpoint and lists what each server reports, marking every model
as a candidate (with its state per bucket) or available and unused. Ollama,
llama.cpp's server, llama-swap, vLLM, and LM Studio serve this listing over
their OpenAI-compatible APIs, so discovery is the same under Claude, Codex,
and Pi: which models exist is a property of the machine's servers, not of
the orchestrating harness. Discovery reports and never edits the profile.
Adding a candidate, confirming its quadruple, and pinning its request
settings is a setup step the user approves. Two cautions:

- A listing is not a load state. A swap-on-demand gateway such as
  llama-swap lists every configured model and loads one on first request,
  so the first call can include model load time — long for a large model
  spread across several GPUs or partly offloaded to system RAM. `qualify`
  measures it, and `timeout_seconds` must allow for it.
- A listing is not a quadruple. `/v1/models` returns IDs, not quantization
  or runtime version, and a server can serve different weights under the
  same ID after a change. Record what the server reports alongside the
  user-confirmed fields; a changed report changes the fingerprint and
  returns the model to unqualified.

Discovery does not read harness model configuration. Those files can hold
credentials inline next to the endpoint list — Pi's `models.json` stores a
provider `apiKey` beside its `baseUrl` — so reading one to save a few setup
questions would put secrets into the agent's context.

**Qualification.** `delegate-run.sh qualify <model>` answers one question:
does this exact setup return a usable file? The runner ships one
already-solved plumbing packet per output shape (single-file, and multi-file
for `coupled`) whose correct output is fully determined by the packet
(rename a function and change a constant, for example), so the check needs
no project fixture and no gate. Each plumbing packet is sized like the
largest bucket it qualifies — a `medium` file of a few hundred lines in and
out, and a `coupled` set at its total-line limit — because a tiny reply fits
anywhere while a real one can hit the server's output-token limit, exhaust
context with reasoning on, or outrun `timeout_seconds` on a model that must
load first. The transformation stays trivial so grading stays exact. The
response must be complete, unfenced, without preamble or leaked reasoning,
and match the expected file after whitespace normalization, using the
production request settings and transport rules. Fenced output is a
qualification failure, never silently unwrapped. Direct file-return calls
(warm-up, qualification, initial delegation and retries) put a fixed
raw-file contract in the system message: the reply is written verbatim as
the target file, with no fence, preamble, filename, patch or commentary.
The source and test files in user packets use byte-counted neutral framing
rather than Markdown code blocks: exactly the advertised number of bytes
belongs to each file, even if its contents resemble an end marker. This is
transport/protocol enforcement across models, not model-specific prompting.
Changing the contract bumps the harness version and invalidates prior
qualifications. Full Pi phase handoffs still use normal agent conversations
and tools; they do not receive this system message. This catches the
serialization failures [`workflow/docs/local-executor.md`](../workflow/docs/local-executor.md) names as dominant, before any real
task depends on them. It records load time and generation time and warns
when `timeout_seconds` leaves little margin. Qualification is per model
entry, not per project: plumbing is a property of the machine's setup. A
failure leaves the model unqualified with the reason.

**Selection.** `delegate-run.sh run <packet>` picks one model per run,
deterministically, and records why:

1. Start from the project's candidates, in their listed order.
2. Keep those qualified and not demoted for the packet's bucket, whose
   fingerprint still matches.
3. Drop any whose endpoint fails a cheap reachability check. An unreachable
   endpoint is an infrastructure fact, not a model failure, and is not
   recorded against the model.
4. **Explore.** If any remaining candidate has fewer than 5 scored runs in
   this bucket, choose the first such candidate in list order.
5. **Rank.** Otherwise rank by the lower bound of the 95% Wilson interval
   on its success rate over its last 20 scored runs in the bucket, so a
   short record ranks below an equally good long one. Break ties by lower
   median wall time, then by list order.
6. Use the chosen model for every attempt in the run. If none remain,
   return `needs_frontier` with the reason.

A scored run is one the model was responsible for: a success is a candidate
that published and then passed review (`record-review pass`); a failure is
`needs_frontier` (including a model timeout, below) or `model-defect`. Refusals, infrastructure failures,
integrity stops caused by the workspace, and `packet-defect` outcomes are
not scored. A published candidate awaiting review counts as pending, not
yet as a success. Manual runs (`--model`) are scored like automatic ones,
so trying a model by hand builds the same record.

The result names the chosen model, the runner-up, the phase (explore or
rank), and the numbers behind it, so the human can see why one candidate
ran instead of another. A model that stops being chosen keeps its last
record rather than accruing new evidence; a manual `--model` run, or an
optional calibration suite, adds to it. A preference for speed over success
rate, or a human-pinned favorite, is not in v1 beyond the exploration order.

**Demotion.** Every run appends to the ignored local ledger
`.agentic/delegate/ledger.jsonl`. A qualified model is demoted for a bucket
when either holds:

- it has at least 5 scored runs there and the upper bound of the 95% Wilson
  interval on its success rate over the last 20 is below 50% — the
  evidence says it fails more often than it succeeds (0/5 qualifies;
  1/5 does not yet); or
- a published candidate is recorded as `model-defect` by review — the gate
  was green and the feature was wrong, the failure the gate cannot catch.

Demotion is reported in the run result and by `discover`. It stands until
the human resets it, which starts a fresh record; a fingerprint change
returns the model to unqualified instead.

**Unsourced starting points.** The interval is Wilson's score interval
(E. B. Wilson, 1927; see `docs/influences.md`). The exploration minimum
(5 runs), the ranking and demotion window (20 runs), the 95% interval, and the 50%
demotion line are design choices, not measured values; nothing published
sets them for this task shape. They are chosen so a clearly broken model is
dropped within about five tasks while a short record cannot outrank a
proven one. Tune them from the ledger once projects have run enough tasks
to show misrouting.

**Optional calibration.** `delegate-run.sh calibrate <model> --suite <path>`
runs prepared tasks through the production loop without touching the
workspace: each fixture records its source, stack, packet, starting file
tree, focused test targets, and known-good target file, and is validated
first (focused tests red against the starting tree; the known-good target
makes them and the gate pass; already-green or broken fixtures are
ineligible). It is a way to compare candidates side by side or to build a
record faster, never a requirement before first use. Runs on fixtures from
this repository are scored like real runs (success when green, since there
is no review); fixtures from another repository or a canned suite are
reported for comparison and never scored, because a model's record does not
transfer cleanly between codebases. A model's record never crosses stacks.

**Retry policy.** Use the model chosen for the run for at most three calls
total, including the initial call. Each attempt starts from the same clean
scratch snapshot. The first request contains the packet; subsequent requests
contain the same fixed system contract, then the original user packet, the
previous assistant candidate, and bounded corrective user diagnostics, in
that order. Qualification uses the production request settings and transport
rules but sends a single request with no retry: a setup that needs a retry to
return a clean file is not qualified. Calibration uses the same request
settings, feedback construction, reset behavior, and attempt limit as
production. Changes to
these rules change the harness version, and so every fingerprint.

When the budget is spent, return `needs_frontier` with the packet path, cause,
and last bounded failure diagnostics, without the failed local code, so the
orchestrator does not anchor on a wrong approach. Infrastructure failures
(such as an unreachable endpoint or unavailable verifier) stop the run and
are recorded separately from model-quality failures; they are not scored
and do not trigger an unbounded transport retry.

`timeout_seconds` limits each model call, not the task, and covers queueing,
any model swap and load, all reasoning, and the reply. The call is not
streamed, so the runner cannot tell long thinking from a stall; summary mode
therefore reports only that the curl process is still waiting and how long it
has waited, not that inference is making forward progress. A call that
connected and then ran past the limit is the model's setup being too slow
for its limit, not a server failure: the run ends with `needs_frontier`
without retrying (a retry would most likely time out again), the attempt is
recorded as `timeout`, and the run is scored as a failure, so a model that
habitually thinks past its limit is demoted like any other failing one. A
call that never connected stays an unscored infrastructure failure. In
`qualify`, a timeout on either request fails the qualification.

Progress is `summary` when stderr is a terminal and `quiet` when redirected;
`--progress quiet|summary` overrides it. Summary mode prints the run ID and
ignored result directory before the model call, emits a heartbeat every 15
seconds (overrideable with `DELEGATE_PROGRESS_INTERVAL`), and names extraction,
verification, and publication stages. Progress goes to stderr and does not
change result JSON, ledger records, retry accounting, or exit status. The same
behavior applies to Small and Medium packets; tasks outside those supported
buckets are still refused rather than given a different progress path.

`needs_frontier` is a machine-readable result printed with a prominent
notice naming the reason and the packet path. The runner does no model
routing: the orchestrator that invoked it implements the step, and the
handoff state lives in the spec, packet, and ledger rather than only in
conversation, so a human can resume it in any client.

### 3. Output quality

A candidate passes through three runner filters before frontier review.
A candidate failure spends an attempt; an integrity violation stops the run.

1. **Runner checks (mechanical, no model).** The output contains exactly
   one complete file per declared target, each once, in the packet's
   delimiter format when there is more than one; only the target paths
   change; test files are byte-identical to
   before (hash comparison, as the test-first fingerprint audit already
   does); transport metadata does not report truncation. Reject unsafe target
   paths and symlink escapes before writing. Language-level completeness and
   import restrictions need stack-specific checks or frontier review; a
   language-neutral shell parser cannot prove them.
2. **Full gate.** Syntax-check `.agentic/toolchain.sh`, then run `ready`.
   Exit 0 permits running each gate step — lint, format-check, typecheck,
   deps, and the whole suite — plus the packet's focused tests. Exit 3 refuses
   delegation because verification is unconfigured; any other failure
   reports a broken verifier. Never treat a skipped gate as green. The
   focused tests must pass, and every step that was green on the baseline
   must stay green: a green focused test with a broken neighbor is red.
   A step already red on the baseline cannot be held against the candidate
   — in a multi-file plan, the other plan files' tests (and often the type
   check) fail until those files land — so it is reported as unverified
   and the result is a `partial` gate. The full gate is required once every
   plan file has landed, as it is for frontier-written code.
3. **Post-execution audit.** Compare file contents, types, and modes with
   the baseline after the gate, including failed runs. Only the supplied
   targets may differ; the gate must not alter that candidate either. Tests
   and fixtures remain byte-identical. Enumerate permitted tool artifacts
   explicitly rather than exempting every ignored path. Unexpected writes
   invalidate the result and stop the run before promotion.
4. **Frontier review.** `/review` and, when the spec calls for it,
   `/review-adversarial`, unchanged, over the complete change set against
   the spec. This is the only filter that catches "gate green, feature
   wrong," and the ledger records its verdict because it is the demotion
   signal that matters most. The runner cannot see review, so `/review`
   gains one orchestration step. The reviewer stays read-only. After findings
   are closed and a fresh review establishes the final disposition, the
   orchestrator calls
   `delegate-run.sh record-review <packet> pass|model-defect|packet-defect`.
   A docs or broader-change finding does not count against the model; close it
   and record `pass` if the delegated implementation itself was accepted.
   Record `model-defect` or `packet-defect` even when the frontier model then
   repairs the targets, preserving attribution without treating an intermediate
   review verdict as final.

The model receives text and returns text; it has no repository tools.
Executing its returned code during verification is a separate trust boundary.

### 4. Workspace snapshot and execution boundary

Before any model call, capture the current base revision and a deterministic
workspace set: every tracked file plus every unignored untracked file, except
`.agentic/delegate/`. Record staged and unstaged state and a manifest of each
included path's contents, type, and mode. Include the pending `/test-first`
output. Do not copy ignored files implicitly: when a gate requires an ignored
fixture, the packet must declare that exact path and setup must approve it as
an input; otherwise refuse. The runner rejects `.env` files, private keys,
credential files, and any project-specific secret paths even when declared.
The same inclusion and exclusion rules govern the pre-publication freshness
check, including detection of newly created unignored files, so runner
bookkeeping cannot stale its own run and a
subjective notion of “relevant” cannot hide workspace changes.

Create the scratch tree from that snapshot, not from `HEAD` alone. Run
`ready`, then `.agentic/toolchain.sh test <target ...>` with the packet's
focused targets. Require a recorded failure for the intended missing
behavior, consistent with `/test-first`; unrelated or already-green results
stop the run. Fingerprint the resulting inputs and bind them to the packet
and ledger record. Provision dependencies before freezing this baseline.

The scratch tree is a plain copy with no `.git` directory, not a Git
worktree: a worktree shares Git metadata with its parent and separates
files without isolating execution. Verification runs inside whatever
sandbox the invoking client provides, and the post-execution audit above
detects writes inside the scratch tree. This is the same trust level the
workflow already gives frontier-written code, which runs `toolchain.sh gate`
under the client's sandbox or none. It does not prevent writes outside the
scratch tree, credential access, or network use by the candidate's code.
A dedicated sandbox for candidate execution is deferred; see below.

Only a candidate passing filters 1–3 may return to the working tree. Before
copying it, recheck the original workspace against the captured manifest,
including new untracked inputs and target existence. If it changed while
the model was running, preserve both the user's work and the scratch result
and require a fresh run. Publish only the targets, uncommitted, without
changing the index; a multi-file candidate publishes all its targets or
none. Serialize publication against other runner instances
and perform the freshness check immediately before replacement.

### 5. Client and transport compatibility

Claude's `/delegate`, Codex's `$delegate`, and Pi's matching prompt invoke
the same runner. Update both the description and terminal instructions of
the shared command: manual "produce the packet and stop" behavior remains
for `off`; `auto` continues into the runner. The runner owns its path controls.
Setup consent owns endpoint use and private profile
writes; do not treat project trust or a client's tool UI as a security
boundary. In particular, Pi does not ask for approval before every tool call,
and its project trust controls resource loading rather than shell network or
filesystem access.

The runner performs no client-specific behavior. Setup must not switch the
primary model or rewrite harness settings to enable delegation.

V1 uses a defined subset of non-streaming `/v1/chat/completions`: text
messages in, one final text candidate out, and no tool calls. Specify request
and output limits, a total timeout, and handling of HTTP errors, malformed
JSON, missing/empty content, reasoning fields, and non-success finish reasons.
Reject truncated responses rather than applying partial files. Record request
settings in every ledger record. An "OpenAI-compatible" label alone does
not establish compatibility; the configured server must pass `qualify`.

## Why not a learned classifier

A routing classifier would answer question 2 by predicting success from
task features. It is the wrong first tool here:

- The features that matter are few and countable (file count, file size,
  contract count, test count, bucket, model quadruple). Fixed thresholds plus
  recorded outcomes cover them, and a human can read why a task was
  refused.
- A classifier needs labeled outcomes per model and per project. Nobody
  has them yet; the ledger is what would produce them.
- It adds a model whose own accuracy needs evaluating, and its errors are
  silent in exactly the way the local-executor doc warns about.

The ledger keeps the option open. If a project accumulates a few hundred
runs and the thresholds visibly misroute — sending tasks that escalate,
or refusing tasks that would have passed — that data is the training set,
and a classifier can be compared against the rules on it.

## Success criteria

- Founding setup asks about optional local delegation, defaults it to `off`,
  and asks only for details not already supplied. Declined setup or an
  unavailable server leaves the normal workflow usable without model calls.
  Saved settings prevent repeated onboarding on resumption.
- An endpoint alone cannot enable delegation. Qualification and activation
  require approval; incomplete prerequisites leave setup pending and policy
  off. The private profile persists policy per canonical checkout, and a new
  clone or moved checkout requires fresh activation. Private endpoints and
  credential values never enter tracked project documents.
- The implementation handoff creates a packet automatically only when policy,
  a selectable candidate, and task eligibility permit it. Existing manual `/delegate`
  packet creation remains available while automatic delegation is off.
  External research is resolved first; packets contain bounded, source-pinned
  claims rather than raw source material or unresolved references.
- `delegate-run.sh run <packet>` checks policy, packet metadata (recomputing
  the bucket from the file), and the candidates' states, selects a model as
  specified, then validates the snapshot and execution prerequisites. Every
  refusal includes a reason.
- With no profile or no selectable candidate for the bucket, the runner
  refuses and recommends frontier implementation; no model call is made.
- `qualify` passes a working setup with one request per output shape,
  fails a fenced, truncated, preambled, or reasoning-leaking response with
  the reason, records load and generation time, and needs no project
  fixture.
- `discover` lists every model each registered endpoint reports, with its
  candidate state per bucket, and never changes the profile. It reads no
  harness configuration.
- Selection is deterministic for a given profile and ledger: it explores
  candidates with fewer than 5 scored runs in list order, then ranks by the
  interval lower bound; excludes unreachable endpoints without scoring a
  failure; never chooses an unqualified, demoted, or changed model; ignores
  model size; and names the chosen model, the runner-up, the phase, and the
  deciding numbers in the result.
- Scoring counts only outcomes the model was responsible for, counts manual
  runs, and treats a published candidate as pending until review. Demotion
  triggers on the interval rule or a `model-defect` review, is reported,
  and stands until the human resets it.
- A selected run reproduces pending edits and tests in a scratch copy,
  confirms the intended red baseline, and runs filters 1–3. It stops after
  at most three calls to the chosen model and prints `needs_frontier`
  with the last failure diagnostics.
- An unconfigured or broken verifier, an integrity violation, or a stale
  workspace cannot produce a green result.
- A green candidate lands in the working tree uncommitted, with a reminder
  that `/review` is still required. After final review, the orchestrator
  records `pass`, `model-defect`, or `packet-defect`; unrelated findings do
  not demote the model.
- Optional `calibrate` consumes prepared fixtures, proves each task red
  before and green after its known-good implementation, uses the same retry
  policy as production, never touches the workspace, and scores only
  fixtures from this repository.
- Every run, qualification, and calibration appends a ledger record. Stack
  source `.gitignore` templates and rendered projects ignore
  `.agentic/delegate/`, including packets, results, the ledger, scratch
  area, and locking state.
- The runner calls only `.agentic/toolchain.sh` for language checks and
  names no language tool. Unsupported custom configurations refuse with an
  explanation; there is no claim of automatic support for every language.
- A smoke test drives the runner against a stub OpenAI-compatible server
  (a canned response file and a canned `/v1/models` listing), covering
  qualification pass and fail, discovery, exploration then ranking between
  two qualified candidates, demotion after repeated failures, an unreachable
  endpoint, a changed server-reported model, refuse, green,
  red-then-escalate,
  and a test-file-tampering candidate. Include uncommitted/untracked tests,
  stale-target publication, already-green calibration fixtures, matching
  retry feedback, unconfigured/broken gates, malformed/truncated responses,
  timeouts, and a candidate whose gate run writes outside the target inside
  the scratch tree. Multi-file fixtures cover a missing target, an extra
  or undeclared path, a duplicated target, and a coupled candidate in which
  one file fails so neither is published. CI never calls a real model.
- Setup fixtures cover no server, declined setup, missing details, a literal
  credential offered in place of a variable name, an incompatible API
  format, a failed qualification, and approved activation. They prove that
  setup does not modify the primary harness model, persist or log credential
  values, expose them in process arguments, or pass the configured credential
  variable into candidate verification.
- Live acceptance separately exercises the shared runner through Claude,
  Codex, and a trusted/reloaded Pi project with a pinned local endpoint,
  covering `/delegate`, candidate publication, `needs_frontier`, and review
  recording. It requires the same explicit token-use authorization as the
  existing live harnesses. A stub-server pass proves runner behavior, not
  model capability or client parity; capability is claimed only from a real
  pinned local model's recorded runs.

## Deferred until after v1

- **Automatic history reconstruction.** Turning past commits into
  calibration fixtures. Later mining must retain the behavior-specific
  red/green eligibility checks; changed-file counts alone are insufficient.
- **Model ladders.** Switching to the runner-up after a failed attempt within
  one run. V1 selects one model per run and keeps it for every attempt.
  Evaluate the exact selection and retry allocation policy before adopting
  it. A per-model three-attempt score does not validate a
  ladder that gives each model one attempt.
- **Held-out tests.** V1 makes no test-secrecy claim. A future version needs
  an explicit stack interface for test selection and diagnostic separation.
  Hidden assertions must be absent from initial packets, verbatim baseline
  output, retry feedback, and all other model-bound diagnostics. Randomly
  omitting test functions is not a portable isolation mechanism.
- **Dedicated execution sandbox.** A boundary that stops candidate code from
  writing outside the scratch tree, reading host credentials, or using the
  network. It must be demonstrated per platform before the runner relies
  on it, and it would apply equally to frontier-written code.
- **Local orchestration and automatic model switching.** Running the whole
  loop on a local model, with a client switching to a frontier model when
  `needs_frontier` or a frontier-only phase arrives (Pi's `pi.setModel()`
  makes this possible there). It conflicts with the non-goal below until
  local models are shown to handle those phases, and Claude and Codex do
  not expose the active model to the runner.
- **A tool-using delegate as a measured candidate.** After v1 has
  real-model evidence, run an agent harness inside the same scratch copy as
  one more candidate setup, with the harness and its version pinned as part
  of the quadruple, and compare its recorded outcomes with the single-shot
  runner's on the same packets. The scratch copy, the gate, the
  post-execution audit, and publish-only-on-pass apply unchanged. The
  dedicated execution sandbox above becomes a prerequisite, because the
  model itself would run commands. What single-shot gives up, and this
  would measure, is the model recovering from a thin packet by exploring;
  multi-file work stays with the frontier model either way.
- **Reading harness configuration during setup.** Reusing endpoint URLs
  from Codex or Pi configuration saves a few questions, but those files can
  hold credentials inline (Pi's `models.json` keeps `apiKey` beside
  `baseUrl`). Server discovery already removes the model-ID questions;
  revisit only if typing endpoint URLs proves to be friction.

## Non-goals

- An agentic local executor with tool access in v1 (Tier 3 in
  [`workflow/docs/local-executor.md`](../workflow/docs/local-executor.md)).
  It is a deferred, measured candidate; see **A tool-using delegate as a
  measured candidate** above.
- Delegating spec, plan, test-first, or review phases.
- Choosing or recommending specific models in scaffold files.
- Committing endpoints, hostnames, or machine profiles to any repository.
- Installing model weights or managing inference-server processes.
- Cost savings as the success measure. The doc's honest-expectations
  section stands: the expected wins are latency, privacy, and learning
  where the envelope is.

## Open questions

- Should records be keyed by task class as well as bucket? Scoring reads
  one ledger per project with buckets by size only. Outside reports
  suggest local models' strengths differ by task type (parsers and regular
  expressions versus tests and runtime behaviour) and that single-run
  rankings mislead. A class key would split already-small records further,
  so it needs a definition of class the frontier model can assign
  mechanically, and enough runs per class to rank. Read
  opencode-model-router's per-class outcome records and shadow mode, which
  logs routing decisions without acting on them, before designing this.

- What prepared-fixture format captures dependency setup and permitted tool
  artifacts reproducibly across Python, TypeScript, and project-owned custom
  runners?
- Optional mutation testing as an additional filter, exposed as an optional
  toolchain subcommand where a stack supports it.
- How to pin quantization and runtime version when a server reports neither,
  beyond user confirmation. llama.cpp exposes some build and model metadata
  on endpoints outside the OpenAI-compatible surface; a per-runtime probe
  would tighten the change check but adds runtime-specific code.
- Bash plus `curl` and `jq` matches the repository, but `jq` becomes a new
  consumer dependency for `--full`. Profile and packet parsing also need a
  defined TOML/YAML parser; `jq` alone does not parse either format.

## Sketch

Add `workflow/bin/delegate-run.sh` (rendered to `.agentic/delegate-run.sh`,
installed with `--full` alongside `/delegate`), with `qualify`, `discover`,
`run`, `record-review`, `status`, `reset`, and optional `calibrate`
subcommands. Extend the renderer, bootstrap managed-file inventory, profile transitions, and update tests for
that executable. Update `workflow/commands/delegate.md` to emit the header,
add the `coupled` packet shape and its delimiter output contract, and honor
`off`/`auto` (per-file sequencing of a multi-file plan and the
`.agentic/delegate/packets/` location have already landed there);
update `/review` so its orchestrator records the final attributable outcome
for a delegated candidate while its reviewer remains read-only. Re-render the
Claude, Codex, and Pi surfaces from these sources.

Add the optional local-delegation setup sequence to the founding guidance in
`workflow/docs/project-types.md` and its new-project checklist references.
Keep the README and checklist founding prompts identical if they change.
Record only the feature choice and pending setup actions in project-facing
interview artifacts; keep connection details and credentials private. Wire
the policy check into the implementation handoff in the shared workflow.

Ship the stack-neutral plumbing packets `qualify` uses. Document the
optional calibration fixture format; canned suites for supported stacks are
optional and never scored. Add stub-server and setup tests under
`scripts/`. Keep `/test-first` unchanged in v1; its pending tests become part
of the runner snapshot. Update `workflow/docs/local-executor.md` and usage
READMEs when the runner exists, and move the `AGENTS.md` open item to the
implemented status with remaining live evidence identified.
