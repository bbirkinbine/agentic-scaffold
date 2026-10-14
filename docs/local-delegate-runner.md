# Local Delegate Runner

**Status:** draft; first slice implemented
**Last updated:** 2026-10-14

**Implemented (manual slice).** `workflow/bin/delegate-run.sh run <packet>
--model <name>` (installed as `.agentic/delegate-run.sh` with `--full`) runs
one packet against a model the human names from the profile, with no
admission check, labelled `manual` in its result and ledger record. It
covers the packet header, the scratch snapshot and red baseline, the
three-attempt retry policy with feedback, the transport rules, filters 1–3,
the stale-workspace check, publication, and the ledger, tested by
`scripts/smoke-test-delegate.sh` against a stub server. Two deliberate
differences from the text below: verification compares each gate step to
the baseline instead of requiring a fully green gate (see filter 2), and
the post-execution audit covers unignored files only; ignored tool
artifacts are not yet enumerated. Not built: admission, `calibrate`,
`discover`, selection, `record-review`, coupled packets, demotion, and the
automatic handoff.

## Goal

Close the gap between `/delegate` (which writes a handoff packet and stops)
and a working local-execution loop: a stack-neutral runner that sends one
packet to a local model, applies the result in a scratch copy, verifies it, and
either hands a green candidate to frontier review or escalates the task back
to the frontier model. Whether a local model is used at all is decided by
measured capability on the project's own tasks, not by model size, vendor
claims, or a per-task human guess.

The first version discovers the models served by the machine's registered
inference endpoints, selects one per run from those calibrated for the
task's bucket, and makes at most three attempts on it. Selection is by
recorded outcomes on this project, never by model size or name. Prepared
calibration packets supply the evidence. Escalation notifies and returns
control; it never switches models mid-run.
Automatic historical packet generation, model ladders, held-out tests, and
local orchestration are deferred until this loop has end-to-end evidence.

## Founding interview and optional setup

Local delegation is an optional implementation path within the existing
Spec → Plan → Test-first → Implement → Verify → Review workflow. Setup and
calibration happen during founding or later maintenance, not for every
feature. The scaffold connects to an existing inference service; installing
models or starting a model server is a separate task.

The founding agent follows this sequence, using answers already supplied
in the conversation instead of repeating questions:

1. **Ask about interest and availability.** "Would you like this project to
   use a local model for eligible implementation tasks, and is a server
   already running?" Default delegation to `off`. If the user declines or no
   server is available, continue normal project setup without requiring an
   endpoint or calibration.
2. **Ask for the endpoints.** Collect the base URL of each inference server
   the user wants available (a workstation Ollama, a llama.cpp or
   llama-swap host on the LAN, and so on) and, when a server requires
   authentication, the *name* of an environment variable holding its
   credential. Model IDs are discovered from the servers, not typed in;
   see **Discovery** below. For each discovered model the user wants as a
   candidate, confirm the quadruple fields the server does not report
   (quantization, runtime version) and the request settings to pin. Never accept a literal secret, and never resolve the variable
   into the conversation, process arguments, log, or profile. The HTTP client
   receives the value without exposing it in its command line, and verifier
   subprocesses run without that credential variable. Do not read other
   harnesses' configuration files to discover these values. Save the entry
   in the private machine profile only after explicit approval, using a
   client flow that visibly confirms the write outside the repository;
   otherwise print the entry for the human to save. Keep machine details out
   of committed interview notes.
3. **Verify and calibrate.** Check each endpoint against the runner's
   protocol, then verify runner dependencies and the project's toolchain.
   Run the prepared calibration suite described below on each candidate the
   user chooses; calibration takes real time per model, so it is never
   started for every discovered model by default. If the new project's
   toolchain or fixtures are not ready, record setup as pending and continue
   normal work with delegation off.
4. **Activate explicitly.** Present the calibration evidence and proposed
   admission. Only after approval of both admission and activation set this
   checkout's private project policy to `auto`. An endpoint or installed
   model alone never enables delegation. Reuse the saved choice on subsequent
   sessions.

The orchestrator running the interview and the local delegate are separate
selections. A hosted frontier model remains the orchestrator while this
runner calls the local endpoint directly. Calibrating a delegate says
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
| Endpoints, discovered models and their pinned settings, admissions, candidates, and `off`/`auto` policy | `~/.config/agentic/local-models.toml` | outside the repository |

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

## The three decisions, and who makes each

Delegation needs four answers. Each goes to the decider that can answer it
cheapest and most reliably.

| Question | Decider | Mechanism |
| --- | --- | --- |
| Is this task *shaped* for delegation? | Frontier model, checked mechanically | `/delegate` preconditions plus task features recorded in the packet |
| Can *this model* do a task of this shape? | Measurement | A per-machine capability profile built by calibration, updated by outcomes |
| *Which* admitted model runs this task? | The runner, from the ledger | Deterministic ranking of reachable, admitted candidates; see **Selection** |
| Is the produced code good enough? | Gate, then frontier review | Runner checks, full toolchain gate, post-execution audit, existing `/review` |

**Who runs it.** At the implementation handoff, after the required approvals
and test-first evidence, the orchestrator session checks the saved policy.
With `off`, no profile, or no candidate admitted for the task's bucket, it
follows the existing implementation workflow without creating a delegation
packet or calling a local endpoint. The mode and candidate list come from the
checkout's entry in the private profile. In `auto` mode, an admitted candidate
and a task
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

The human sets policy once (`off` or `auto`) and approves a model's admission
after calibration. Per-task routing then follows that policy and the recorded
evidence. Runner policy does not override the client's permissions.

### 1. Task shape

The frontier model already decomposes work in `/plan` and writes the packet
in `/delegate`. Extend the packet with a machine-readable header so the
runner can admit or refuse without reading prose:

```yaml
targets: [src/pkg/parser.py]  # one entry per file the model returns
target_lines: 140          # summed current size, 0 for new files
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
dimension like the others, not a fixed rule: each bucket is admitted only
by its own calibration, and admission in one never implies another. The
thresholds are a starting point to be corrected by the ledger, not a claim
about model capability.

A multi-file plan is split into one-file packets in dependency order
whenever each file can reach green on its own once its predecessors have
landed; `/delegate` already does this. A `coupled` packet is only for files
that cannot pass separately — a new type and its sole consumer, or a
signature change and its callers — and only when some candidate holds a
`coupled` admission. Without one, that step goes to the frontier model.
The single-shot, no-tools, whole-file rules apply unchanged: a coupled call
is still one request returning complete files, never a multi-turn edit.

The judgment the frontier model contributes is *self-containment*: whether
every reference the executor needs is quoted. That cannot be fully checked
mechanically. On escalation, the orchestrator implements the targets and
records one of two causes in the ledger: `packet` if its own implementation
needed a signature, type, or constant the packet did not quote, `model`
otherwise. Packet defects do not count toward a model's demotion; a rising
packet-defect rate is a signal to fix `/delegate`, not the model.

External research required by the task is completed by the frontier
orchestrator or a focused research subagent before packet creation. Record
source locators, retrieval dates, and license status under the spec's
`## External references`. The packet inlines only the task-relevant,
source-pinned claims; it never includes a raw research corpus or asks the
local delegate to resolve an external reference.

### 2. Model capability

Capability is a property of the quadruple the existing doc already says to
pin — model, quantization, runtime version, harness version — plus the
request settings sent with every call (reasoning mode or thinking level,
sampling parameters), measured against *this project's* tasks. The same
weights with reasoning on and off are two profile entries with separate
admissions. Parameter count is a prior, not an admission rule, and there is
no upper or lower bound on model size: a model the machine can serve is a
candidate, and calibration decides whether it is admitted.

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
harness = "delegate-run-v1"
context = 131072
request = { reasoning_effort = "medium", temperature = 0.6 }  # pinned

[[project]]
root = "/canonical/local/path/to/repo"
policy = "off"               # off | auto
candidates = ["coder-a-think", "coder-b"]
activation_approved = false
```

The founding interview above creates or reuses this profile. Resolve `root`
from the physical repository root, without following a remote URL as project
identity; a second clone is a separately approved checkout. No admissions
exist until calibration runs. The project entry lists its candidates
explicitly; a discovered model that is not a candidate is never called for
the project, and the runner chooses only among admitted candidates as
described under **Selection**. Activation changes `policy` and
`activation_approved` together after approval. With no profile, no approved
auto policy, or no candidate admitted for the bucket, implement with the
frontier model. Model size alone never grants or denies admission. All
clients read this same runner-owned profile rather than their own model
configuration.

**Discovery.** `delegate-run.sh discover` sends `GET /v1/models` to each
registered endpoint and lists what each server reports, marking every model
as one of: candidate and admitted (with buckets), candidate pending
calibration, or available and unused. Ollama, llama.cpp's server,
llama-swap, vLLM, and LM Studio serve this listing over their
OpenAI-compatible APIs, so discovery is the same under Claude, Codex, and Pi:
which models exist is a property of the machine's servers, not of the
orchestrating harness. Discovery reports and never edits the profile.
Adding a candidate, confirming its quadruple, and pinning its request
settings is a setup step the user approves. Two cautions:

- A listing is not a load state. A swap-on-demand gateway such as
  llama-swap lists every configured model and loads one on first request,
  so the first call can include model load time. Timeouts separate a load
  allowance from the generation timeout, and calibration records both.
- A listing is not a quadruple. `/v1/models` returns IDs, not quantization
  or runtime version, and a server can serve different weights under the
  same ID after a change. Record what the server reports alongside the
  user-confirmed fields; a changed report invalidates admission the same
  way a quadruple change does.

Discovery does not read harness model configuration. Those files can hold
credentials inline next to the endpoint list — Pi's `models.json` stores a
provider `apiKey` beside its `baseUrl` — so reading one to save a few setup
questions would put secrets into the agent's context.

**Selection.** `delegate-run.sh run <packet>` picks one model per run,
deterministically, and records why:

1. Start from the project's candidates.
2. Keep those admitted for the packet's bucket in this project and stack,
   not demoted, and whose quadruple, request settings, and server-reported
   ID still match their admission.
3. Drop any whose endpoint fails a cheap reachability check. An unreachable
   endpoint is an infrastructure fact, not a model failure, and is not
   recorded against the model.
4. Rank the remainder by success rate within three attempts in that bucket,
   over the last 20 ledger runs in that bucket, counting calibration runs
   until production runs accumulate. Break ties by lower median wall time
   from the ledger, then by profile entry name.
5. Use the top-ranked model for every attempt in the run. If none remain,
   return `needs_frontier` with the reason.

The result names the chosen model, the runner-up, and the numbers that
decided it, so the human can see why one candidate ran instead of another. A model
that stops being chosen keeps its last measured rate rather than accruing
new evidence; re-calibration refreshes it. A preference for speed over success rate, or a
human-pinned favorite, is not in v1: both are policy choices that need the
same evidence as the ranking, and a pinned favorite is what calibration
replaces.

**Calibration.** `delegate-run.sh calibrate <model> --suite <path>` consumes
prepared packets and reproducible fixtures. The frontier session or human
prepares them separately; the runner makes no frontier calls and does not
mine Git history. Each fixture records its source, stack, packet, starting
file tree, focused test targets, and known-good target file. It runs two
stages:

1. *Plumbing* — one already-solved packet per output shape being
   calibrated (single-file, and multi-file when `coupled` is). The model
   must return parseable whole files with no fence, preamble, or
   truncation, and a multi-file response must use the delimiter format in
   the packet's output contract. This catches the
   serialization failures
   [`workflow/docs/local-executor.md`](../workflow/docs/local-executor.md)
   names as dominant. A
   plumbing failure ends calibration; there is no point measuring reasoning
   through a broken pipe.
2. *Behavioral tasks* — validate each fixture before scoring it. Its focused
   tests must fail for the intended missing behavior against the starting
   implementation. Applying only the known-good target must make those tests
   and the full gate pass. Already-green baselines, broken fixtures, and
   unrelated failures are ineligible. Run eligible tasks with the production
   retry policy below. A bucket is admitted when at least 60% of at least
   10 distinct eligible tasks succeed within three attempts. Record task and
   per-attempt outcomes; this measures the feedback loop, not independent
   sample pass@3. Each bucket needs its own ten tasks of that shape; a
   `coupled` fixture must have targets that cannot pass separately, or it
   measures nothing a sequence of one-file packets would not.

Admission is scoped to the project. A model's score depends on the
language, the codebase's conventions, and how much contract context a
typical file needs, so a result from one repository does not transfer
cleanly to another. Calibration sources, in order of preference:

1. **Prepared tasks from this repository**, including manually reconstructed
   historical changes. This is the only source that grants full admission.
   A commit that changes one source file alongside tests is only a candidate;
   it still needs the red/green fixture validation above.
2. **Prepared tasks from another repository of the same stack**, with their
   origin recorded in the suite. Grants provisional admission.
3. **A canned suite for a supported stack**, for day zero. Grants provisional
   admission. A custom stack needs project-supplied fixtures; its language
   and test framework cannot be inferred from the name `custom`.

Provisional admission is labelled in every result. Promotion requires an
explicit calibration on prepared tasks from this repository and approval
of the resulting admission. There is no automatic history scan in v1.
A model never carries admission across stacks.

The profile therefore records admission per project and stack, while the
endpoint and quadruple stay per machine:

```toml
[[model.admission]]
project_root = "/canonical/local/path/to/repo"
stack = "python"
buckets = ["small"]
source = "project"        # project | other-repo | canned
```

**Retry policy.** Use the model chosen for the run for at most three calls
total, including the initial call. Each attempt starts from the same clean
scratch snapshot. The first request contains the packet; subsequent requests
contain the packet, the previous candidate, and bounded failure diagnostics.
Calibration uses the same request settings, feedback construction, reset
behavior, and attempt limit as production. Changes to these rules change
the harness version and invalidate admission.

When the budget is spent, return `needs_frontier` with the packet path, cause,
and last bounded failure diagnostics, without the failed local code, so the
orchestrator does not anchor on a wrong approach. Infrastructure failures
(such as an unreachable endpoint or unavailable verifier) stop the run and
are recorded separately from model-quality failures; they do not demote the
model or trigger an unbounded transport retry.

`needs_frontier` is a machine-readable result printed with a prominent
notice naming the reason and the packet path. The runner does no model
routing: the orchestrator that invoked it implements the step, and the
handoff state lives in the spec, packet, and ledger rather than only in
conversation, so a human can resume it in any client.

**Demotion.** Every run appends to the ignored local ledger
`.agentic/delegate/ledger.jsonl`. If, over the last 20 runs in
a bucket, the model-caused escalation rate exceeds 50% or a green candidate
was rejected by review for a defect in the delegated implementation, the
runner stops admitting that model for that bucket and says so.
Re-calibration re-admits it. Runtime or model upgrades change
the quadruple, which invalidates admission and requires both calibration
stages plus approval before another real task.

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
   and the whole suite — plus the packet's focused tests. Exit 3 refuses
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
settings with calibration evidence. An "OpenAI-compatible" label alone does
not establish compatibility; the configured server must pass the plumbing
fixtures.

## Why not a learned classifier

A routing classifier would answer question 2 by predicting success from
task features. It is the wrong first tool here:

- The features that matter are few and countable (file count, file size,
  contract count, test count, bucket, model quadruple). Fixed thresholds plus
  measured admission cover them, and a human can read why a task was
  refused.
- A classifier needs labeled outcomes per model and per project. Nobody
  has them yet; the ledger is what would produce them.
- It adds a model whose own accuracy needs evaluating, and its errors are
  silent in exactly the way the local-executor doc warns about.

The ledger keeps the option open. If a project accumulates a few hundred
runs and the thresholds visibly misroute — admitting tasks that escalate,
or refusing tasks that would have passed — that data is the training set,
and a classifier can be compared against the rules on it.

## Success criteria

- Founding setup asks about optional local delegation, defaults it to `off`,
  and asks only for details not already supplied. Declined setup or an
  unavailable server leaves the normal workflow usable without model calls.
  Saved settings prevent repeated onboarding on resumption.
- An endpoint alone cannot enable delegation. Admission and activation
  require approval; incomplete prerequisites leave setup pending and policy
  off. The private profile persists policy per canonical checkout, and a new
  clone or moved checkout requires fresh activation. Private endpoints and
  credential values never enter tracked project documents.
- The implementation handoff creates a packet automatically only when policy,
  admission, and task eligibility permit it. Existing manual `/delegate`
  packet creation remains available while automatic delegation is off.
  External research is resolved first; packets contain bounded, source-pinned
  claims rather than raw source material or unresolved references.
- `delegate-run.sh run <packet>` checks policy, packet metadata, and the
  candidates' admissions, selects a model as specified, then validates the
  snapshot and execution prerequisites. Every refusal includes a reason.
- With no profile or no candidate admitted for the bucket, the runner
  refuses and recommends frontier implementation; no model call is made.
- `discover` lists every model each registered endpoint reports, with its
  candidate and admission state, and never changes the profile. It reads no
  harness configuration.
- Selection is deterministic for a given profile and ledger, excludes
  unreachable endpoints without recording a model failure, never chooses an
  uncalibrated, demoted, or changed model, ignores model size, and names
  the chosen model, the runner-up, and the deciding numbers in the result.
- An admitted run reproduces pending edits and tests in a scratch copy,
  confirms the intended red baseline, and runs filters 1–3. It stops after
  at most three calls to the chosen model and prints `needs_frontier`
  with the last failure diagnostics.
- An unconfigured or broken verifier, an integrity violation, or a stale
  workspace cannot produce a green result.
- A green candidate lands in the working tree uncommitted, with a reminder
  that `/review` is still required. After final review, the orchestrator
  records `pass`, `model-defect`, or `packet-defect`; unrelated findings do
  not demote the model.
- `calibrate` consumes prepared fixtures, proves each behavioral task red
  before and green after its known-good implementation, and uses the same
  retry policy as production. It writes proposed admissions and requires
  explicit confirmation before updating the profile.
- Every run and calibration appends a ledger record; demotion triggers as
  specified. Stack source `.gitignore` templates and rendered projects ignore
  `.agentic/delegate/`, including packets, results, the ledger, scratch area,
  and locking state.
- The runner calls only `.agentic/toolchain.sh` for language checks and
  names no language tool. Unsupported custom configurations refuse with an
  explanation; there is no claim of automatic support for every language.
- A smoke test drives the runner against a stub OpenAI-compatible server
  (a canned response file and a canned `/v1/models` listing), covering
  discovery, selection between two admitted candidates, an unreachable
  endpoint, a changed server-reported model, admit, refuse, green,
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
  format, pending calibration, and approved activation. They prove that
  setup does not modify the primary harness model, persist or log credential
  values, expose them in process arguments, or pass the configured credential
  variable into candidate verification.
- Live acceptance separately exercises the shared runner through Claude,
  Codex, and a trusted/reloaded Pi project with a pinned local endpoint,
  covering `/delegate`, candidate publication, `needs_frontier`, and review
  recording. It requires the same explicit token-use authorization as the
  existing live harnesses. A stub-server pass proves runner behavior, not
  model capability or client parity; a real pinned local model must
  separately pass calibration before capability is claimed.

## Deferred until after v1

- **Automatic history reconstruction.** First prove prepared fixtures work.
  Later mining must retain the behavior-specific red/green eligibility
  checks; changed-file counts alone are insufficient.
- **Model ladders.** Switching to the runner-up after a failed attempt within
  one run. V1 selects one model per run and keeps it for every attempt.
  Evaluate the exact selection and retry allocation policy before admitting
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
- **Reading harness configuration during setup.** Reusing endpoint URLs
  from Codex or Pi configuration saves a few questions, but those files can
  hold credentials inline (Pi's `models.json` keeps `apiKey` beside
  `baseUrl`). Server discovery already removes the model-ID questions;
  revisit only if typing endpoint URLs proves to be friction.

## Non-goals

- An agentic local executor with tool access (Tier 3 in
  [`workflow/docs/local-executor.md`](../workflow/docs/local-executor.md)).
- Delegating spec, plan, test-first, or review phases.
- Choosing or recommending specific models in scaffold files.
- Committing endpoints, hostnames, or machine profiles to any repository.
- Installing model weights or managing inference-server processes.
- Cost savings as the success measure. The doc's honest-expectations
  section stands: the expected wins are latency, privacy, and learning
  where the envelope is.

## Open questions

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
installed with `--full` alongside `/delegate`), with `discover`, `calibrate`,
`run`, and `record-review` subcommands. Extend the renderer,
bootstrap managed-file inventory, profile transitions, and update tests for
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

Add prepared calibration fixtures for supported stacks and document the
project-supplied custom-suite format. Add stub-server and setup tests under
`scripts/`. Keep `/test-first` unchanged in v1; its pending tests become part
of the runner snapshot. Update `workflow/docs/local-executor.md` and usage
READMEs when the runner exists, and move the `AGENTS.md` open item to the
implemented status with remaining live evidence identified.
