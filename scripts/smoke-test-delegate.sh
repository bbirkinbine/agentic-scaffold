#!/usr/bin/env bash
# Smoke-test the local delegate runner (.agentic/delegate-run.sh) against a
# stub OpenAI-compatible server. Bootstraps the custom flavor with --full,
# fills its runner with a small shell toolchain, writes a one-file packet,
# and drives: qualification (pass, wrong edit, fence, truncation, inline
# reasoning, unreachable endpoint, a setup change revoking it); runs (green
# on the first call, red then green with retry feedback, three reds to
# needs_frontier, fenced and truncated responses, a lint regression, a
# partial gate, a candidate whose gate run writes outside the target, an
# already-green baseline, an unconfigured gate, a missing credential, an
# HTTP error, a workspace that changes mid-run, a model that connects but
# answers past timeout_seconds); scoring (pending until
# review, review verdicts, demotion by interval and by review defect, the
# demoted warning, reset); and discovery and selection (explore in list
# order, rank by record, skip unqualified, demoted, and unreachable
# candidates, needs_frontier when none is selectable). CI never calls a
# real model.
#
# Usage:
#   scripts/smoke-test-delegate.sh
#
# Requires: bash, git, curl, jq, python3. No network beyond 127.0.0.1.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
STUB_PID=""
cleanup() {
  [[ -n "$STUB_PID" ]] && kill "$STUB_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  echo "DELEGATE SMOKE FAIL: $*" >&2
  exit 1
}

for dep in curl jq python3; do
  command -v "$dep" >/dev/null || fail "missing dependency: $dep"
done

mkdir "$WORK/project"
cd "$WORK/project"
git init -q -b main
bash "$REPO_DIR/custom/bootstrap.sh" --full >/dev/null
[[ -x .agentic/delegate-run.sh ]] || fail "--full did not install .agentic/delegate-run.sh"
cmp -s .agentic/delegate-run.sh "$REPO_DIR/workflow/bin/delegate-run.sh" ||
  fail "installed runner differs from workflow/bin/delegate-run.sh"

# --- a small shell project with an active gate ---------------------------------
python3 - <<'PY'
import re
from pathlib import Path

path = Path(".agentic/toolchain.sh")
text = path.read_text()
fills = {
    "TC_SOURCE_DIRS": "lib",
    "TC_TEST_DIRS": "tests",
    "tc_install": "no_tool",
    "tc_format": "no_tool",
    "tc_format_check": "no_tool",
    "tc_lint": 'local f; for f in lib/*.sh; do bash -n "$f" || return 1; done; ! grep -q FIXME lib/*.sh',
    "tc_typecheck": "no_tool",
    "tc_test": 'if (($#)); then local t; for t in "$@"; do bash "$t" || return 1; done; else bash tests/run.sh; fi',
}
for name, body in fills.items():
    if name.startswith("TC_"):
        text, n = re.subn(rf'^{name}="".*$', f'{name}="{body}"', text, flags=re.M)
    else:
        text, n = re.subn(rf"^{name}\(\) \{{ unfilled .*$", f"{name}() {{ {body}; }}", text, flags=re.M)
    if n != 1:
        raise SystemExit(f"fill: no single template line for {name}")
text = text.replace("TC_CONFIGURED=0", "TC_CONFIGURED=1", 1)
path.write_text(text)
PY
mkdir -p lib tests
cat >lib/greet.sh <<'SH'
greet() { echo "TODO"; }
SH
cp lib/greet.sh "$WORK/greet.baseline"
cat >tests/test_greet.sh <<'SH'
source lib/greet.sh
[[ "$(greet bob)" == "hello bob" ]] || { echo "expected 'hello bob', got '$(greet bob)'"; exit 1; }
SH
cat >tests/run.sh <<'SH'
for t in tests/test_*.sh; do bash "$t" || exit 1; done
SH
bash .agentic/toolchain.sh ready || fail "filled runner is not ready"
git add -A >/dev/null
git -c user.name=smoke -c user.email=smoke@example.invalid commit -qm baseline

mkdir -p .agentic/delegate/packets
PACKET=.agentic/delegate/packets/0001-lib-greet-sh.md
cat >"$PACKET" <<'MD'
---
targets: [lib/greet.sh]
target_lines: 1
contract_items: 1
visible_tests: 1
test_targets: [tests/test_greet.sh]
new_dependencies: false
bucket: small
---
# Task

`greet NAME` prints `hello NAME`.

# Output contract

Return the complete final contents of `lib/greet.sh`, and nothing else.
MD
git check-ignore -q "$PACKET" || fail ".agentic/delegate/ is not gitignored in a fresh project"

# --- stub server and profile ----------------------------------------------------
QUEUE="$WORK/queue"
mkdir -p "$QUEUE"
python3 -I "$REPO_DIR/scripts/delegate-stub-server.py" "$QUEUE" "$WORK/port" &
STUB_PID=$!
for _ in $(seq 1 50); do [[ -s "$WORK/port" ]] && break; sleep 0.1; done
[[ -s "$WORK/port" ]] || fail "stub server did not start"
PORT="$(cat "$WORK/port")"

PROFILE="$WORK/local-models.toml"
cat >"$PROFILE" <<TOML
# smoke profile
[[endpoint]]
name = "stub"
base_url = "http://127.0.0.1:$PORT/v1"
credential_env = "STUB_TOKEN"

[[endpoint]]
name = "dead"
base_url = "http://127.0.0.1:9/v1"

[[model]]
name = "stub-coder"
endpoint = "stub"
model_id = "stub-model"
quant = "Q8_0"
runtime = "stub 1"
timeout_seconds = 30
request = '{"temperature": 0.2}'

[[model]]
name = "dead-coder"
endpoint = "dead"
model_id = "nothing"

[[model]]
name = "slow-coder"
endpoint = "stub"
model_id = "stub-model"
quant = "Q2_K"
runtime = "stub 1"
timeout_seconds = 2

[[model]]
name = "stub-coder-b"
endpoint = "stub"
model_id = "stub-model"
quant = "Q4_K"
runtime = "stub 1"
timeout_seconds = 30
TOML
export AGENTIC_DELEGATE_PROFILE="$PROFILE"
export STUB_TOKEN="smoke-secret-value"

GOOD='greet() { echo "hello $1"; }'
BAD='greet() { echo "hi $1"; }'

# respond <NN> <content> [finish_reason]
respond() {
  jq -n --arg c "$2" --arg f "${3:-stop}" \
    '{choices: [{index: 0, finish_reason: $f, message: {role: "assistant", content: $c}}]}' \
    >"$QUEUE/$1.json"
}

reset_case() {
  cp "$WORK/greet.baseline" lib/greet.sh
  rm -rf "$QUEUE"/*.json "$QUEUE"/*.status "$QUEUE"/*.delay "$QUEUE/requests"
  mkdir -p "$QUEUE/requests"
}

# expect_run <status> <model> : runs the runner, asserts its exit status.
expect_run() {
  local want="$1" model="$2" got=0
  bash .agentic/delegate-run.sh run "$PACKET" --model "$model" >"$WORK/run.out" 2>&1 || got=$?
  [[ "$got" == "$want" ]] || {
    cat "$WORK/run.out" >&2
    fail "expected exit $want, got $got (model $model)"
  }
}

last_result() { jq -c 'select((.type // "run") == "run")' .agentic/delegate/ledger.jsonl | tail -n 1; }
greet_is() { [[ "$(cat lib/greet.sh)" == "$1" ]]; }
runner() { bash .agentic/delegate-run.sh "$@"; }

# The plumbing file and its expected edit, regenerated from the runner itself.
plumbing() {
  bash -c 'source <(sed -n "/^PLUMBING_COUNT=/,/^# Whitespace-insensitive/p" .agentic/delegate-run.sh); '"$1"
}

# qualify_with <status> <model> <plumbing-reply> [finish] : queue a warm-up and a reply.
qualify_with() {
  reset_case
  respond 01 "OK"
  respond 02 "$3" "${4:-stop}"
  local got=0
  runner qualify "$2" >"$WORK/qualify.out" 2>&1 || got=$?
  [[ "$got" == "$1" ]] || { cat "$WORK/qualify.out" >&2; fail "qualify $2: expected exit $1, got $got"; }
}

# state_of <model> <bucket> : the bucket line from `status`.
state_of() {
  local out
  out="$(runner status 2>&1)"
  grep -A2 "^$1 " <<<"$out" | grep "^  $2:" || true
}
# state_has <model> <bucket> <text>
state_has() { [[ "$(state_of "$1" "$2")" == *"$3"* ]]; }

# --- 0. qualification -----------------------------------------------------------
reset_case
expect_run 2 stub-coder
grep -q 'unqualified' "$WORK/run.out" || fail "an unqualified model was not refused"
[[ -z "$(ls "$QUEUE/requests")" ]] || fail "an unqualified model was called"

EXPECTED="$(plumbing plumbing_expected)"
qualify_with 5 stub-coder "$(plumbing plumbing_file)"
grep -q 'differs from the expected edit' "$WORK/qualify.out" || fail "an unedited plumbing reply passed"
qualify_with 5 stub-coder $'```python\n'"$EXPECTED"$'\n```'
grep -q 'code fence' "$WORK/qualify.out" || fail "a fenced plumbing reply passed"
qualify_with 5 stub-coder "$EXPECTED" length
qualify_with 0 stub-coder $'<think>\nrename one def\n</think>\n'"$EXPECTED"$'\n\n'
grep -q "qualified: 'stub-coder'" "$WORK/qualify.out" || fail "qualify did not report a pass"
jq -e '.messages[0].content | contains("weighted_metric_17")' "$QUEUE/requests/02.json" >/dev/null ||
  fail "the plumbing packet was not sent"
[[ "$(jq -s 'map(select(.result == "pass")) | length' "$WORK/local-models-qualified.jsonl")" == 1 ]] ||
  fail "the qualification record was not written beside the profile"
if grep -q smoke-secret-value "$WORK/local-models-qualified.jsonl"; then fail "credential leaked into qualification"; fi
status_out="$(runner status 2>&1)"
[[ "$status_out" == *"stub-coder (stub-model, setup "*"): qualified"* ]] ||
  { echo "$status_out" >&2; fail "status does not show stub-coder qualified"; }

# A setup change (here, the request settings) needs a new qualification.
sed -i.bak 's/"temperature": 0.2/"temperature": 0.3/' "$PROFILE"
reset_case
expect_run 2 stub-coder
grep -q 'unqualified' "$WORK/run.out" || fail "a changed setup kept its qualification"
mv "$PROFILE.bak" "$PROFILE"

# --- 1. green on the first call ---------------------------------------------------
reset_case
respond 01 "$GOOD"
expect_run 0 stub-coder
greet_is "$GOOD" || fail "green candidate was not published"
[[ "$(last_result | jq -r .outcome)" == green ]] || fail "ledger outcome is not green"
[[ "$(last_result | jq -r .mode)" == manual ]] || fail "ledger record is not labelled manual"
[[ "$(last_result | jq '.attempts | length')" == 1 ]] || fail "green run used more than one attempt"
[[ "$(cat "$QUEUE/requests/01.auth")" == "Bearer smoke-secret-value" ]] || fail "credential not sent"
jq -e '.temperature == 0.2 and .model == "stub-model" and .stream == false' "$QUEUE/requests/01.json" >/dev/null ||
  fail "request settings from the profile were not applied"
jq -e '.messages[0].content | contains("targets:") | not' "$QUEUE/requests/01.json" >/dev/null ||
  fail "packet front matter was sent to the model"
if grep -rq smoke-secret-value .agentic/delegate; then fail "credential value leaked into delegation state"; fi
git diff --cached --quiet || fail "runner staged changes"

# --- 2. red, then green with feedback ------------------------------------------------
reset_case
respond 01 "$BAD"
respond 02 "$GOOD"
expect_run 0 stub-coder
greet_is "$GOOD" || fail "second-attempt green was not published"
jq -e '.messages | length == 3' "$QUEUE/requests/02.json" >/dev/null || fail "retry lacks previous candidate and feedback"
jq -e '.messages[1].content | contains("hi $1")' "$QUEUE/requests/02.json" >/dev/null ||
  fail "retry did not carry the previous candidate"
jq -e '.messages[2].content | contains("expected '"'"'hello bob'"'"'")' "$QUEUE/requests/02.json" >/dev/null ||
  fail "retry did not carry the failure output"

# --- 3. three reds: needs_frontier, nothing published ----------------------------
reset_case
respond 01 "$BAD"; respond 02 "$BAD"; respond 03 "$BAD"
expect_run 10 stub-coder
cmp -s lib/greet.sh "$WORK/greet.baseline" || fail "a red candidate was published"
[[ "$(last_result | jq -r .outcome)" == needs_frontier ]] || fail "outcome is not needs_frontier"
grep -q needs_frontier "$WORK/run.out" || fail "needs_frontier was not announced"
run_dir=".agentic/delegate/results/$(last_result | jq -r .run)"
[[ ! -e "$run_dir/candidate" ]] || fail "failed local code was kept for the orchestrator"

# --- 4. fenced, truncated, then inline reasoning + green -------------------------
reset_case
respond 01 $'```bash\n'"$GOOD"$'\n```'
respond 02 "$GOOD" length
respond 03 $'<think>\nplan the function\n</think>\n'"$GOOD"
expect_run 0 stub-coder
greet_is "$GOOD" || fail "reasoning block was not stripped from the candidate"
[[ "$(last_result | jq -r '[.attempts[].outcome] | join(",")')" == "format,format,green" ]] ||
  fail "fence and truncation were not rejected as format failures"

# --- 4b. a candidate that hangs its tests times out and is retried --------------
reset_case
respond 01 'greet() { sleep 60; echo "hello $1"; }'
respond 02 "$GOOD"
DELEGATE_STEP_TIMEOUT=3 expect_run 0 stub-coder
greet_is "$GOOD" || fail "the run did not recover after a timed-out attempt"
jq -e '.messages[2].content | contains("timed out after 3s")' "$QUEUE/requests/02.json" >/dev/null ||
  fail "the timeout was not reported back to the model"

# --- 5a. focused tests pass but a step green before the run goes red -------------
reset_case
respond 01 'greet() { echo "hello $1"; } # FIXME'
respond 02 "$GOOD"
expect_run 0 stub-coder
[[ "$(last_result | jq -r '.attempts[0].detail')" == *"now fail: lint"* ]] ||
  fail "a lint regression was not caught"
[[ "$(last_result | jq -r .gate)" == full ]] || fail "a fully green run was not reported as full"

# --- 5b. another plan file not landed: partial gate, still published ------------
reset_case
cat >tests/test_other.sh <<'SH'
source lib/other.sh 2>/dev/null && other || exit 1
SH
respond 01 "$GOOD"
expect_run 0 stub-coder
greet_is "$GOOD" || fail "partial-gate candidate was not published"
[[ "$(last_result | jq -r .gate)" == partial ]] || fail "pre-existing red step was not reported as partial"
[[ "$(last_result | jq -r '.unverified_steps | join(",")')" == test ]] || fail "unverified steps not named"
grep -q 'partial gate' "$WORK/run.out" || fail "partial gate was not announced"
rm tests/test_other.sh

# --- 5c. a candidate whose gate run writes outside the target --------------------
reset_case
respond 01 'greet() { echo "hello $1"; }; echo tampered >tests/run.sh'
expect_run 4 stub-coder
cmp -s lib/greet.sh "$WORK/greet.baseline" || fail "tampering candidate was published"
[[ "$(last_result | jq -r .outcome)" == integrity ]] || fail "tampering was not an integrity stop"
grep -q 'tests/run.sh' "$WORK/run.out" || fail "integrity stop did not name the changed file"
git diff --quiet tests/ || fail "tampering reached the real workspace"

# --- 6. already-green baseline is refused before any call ------------------------
reset_case
printf '%s\n' "$GOOD" >lib/greet.sh
expect_run 2 stub-coder
[[ -z "$(ls "$QUEUE/requests")" ]] || fail "a model was called for an already-green task"
grep -q 'already pass' "$WORK/run.out" || fail "already-green refusal reason missing"

# --- 7. unconfigured gate is refused ----------------------------------------------
reset_case
sed -i.bak 's/^TC_CONFIGURED=1/TC_CONFIGURED=0/' .agentic/toolchain.sh
expect_run 2 stub-coder
grep -q 'unconfigured' "$WORK/run.out" || fail "unconfigured gate was not named"
mv .agentic/toolchain.sh.bak .agentic/toolchain.sh

# --- 8. missing credential, unreachable endpoint, HTTP error ---------------------
reset_case
respond 01 "$GOOD"
STUB_TOKEN="" expect_run 2 stub-coder
grep -q "STUB_TOKEN" "$WORK/run.out" || fail "missing credential variable was not named"
got=0
runner qualify dead-coder >"$WORK/qualify.out" 2>&1 || got=$?
[[ "$got" == 3 ]] || { cat "$WORK/qualify.out" >&2; fail "unreachable endpoint: expected exit 3, got $got"; }
grep -q unreachable "$WORK/qualify.out" || fail "unreachable endpoint was not named"
[[ "$(jq -s 'map(select(.model == "dead-coder")) | length' "$WORK/local-models-qualified.jsonl")" == 0 ]] ||
  fail "an unreachable endpoint was recorded as a qualification result"
reset_case
respond 01 '{}'
echo 500 >"$QUEUE/01.status"
expect_run 3 stub-coder
cmp -s lib/greet.sh "$WORK/greet.baseline" || fail "HTTP error published something"

# --- 9. the workspace changes while the model runs --------------------------------
reset_case
respond 01 "$GOOD"
echo 2 >"$QUEUE/01.delay"
got=0
bash .agentic/delegate-run.sh run "$PACKET" --model stub-coder >"$WORK/run.out" 2>&1 &
runner=$!
for _ in $(seq 1 100); do [[ -e "$QUEUE/requests/01.json" ]] && break; sleep 0.05; done
echo "# edited during the run" >>tests/run.sh
wait "$runner" || got=$?
[[ "$got" == 4 ]] || { cat "$WORK/run.out" >&2; fail "stale workspace: expected exit 4, got $got"; }
cmp -s lib/greet.sh "$WORK/greet.baseline" || fail "candidate was published over a changed workspace"
grep -q '# edited during the run' tests/run.sh || fail "the user's edit was lost"
run_dir=".agentic/delegate/results/$(last_result | jq -r .run)"
[[ -f "$run_dir/candidate" ]] || fail "green candidate was not kept after a stale-workspace stop"
git checkout -q tests/run.sh

# --- 9b. a model that connects but answers too slowly -----------------------------
qualify_with 0 slow-coder "$EXPECTED"
reset_case
respond 01 "$GOOD"
echo 4 >"$QUEUE/01.delay"
expect_run 10 slow-coder
cmp -s lib/greet.sh "$WORK/greet.baseline" || fail "a timed-out run published something"
[[ "$(last_result | jq -r '.attempts | map(.outcome) | join(",")')" == timeout ]] ||
  fail "a post-connect timeout was not one timeout attempt: $(last_result | jq -c .attempts)"
grep -q 'raise timeout_seconds' "$WORK/run.out" || fail "the timeout did not suggest raising timeout_seconds"
state_has slow-coder small '0/1 passed' || fail "a model timeout was not scored: $(state_of slow-coder small)"
reset_case
respond 01 "OK"
echo 4 >"$QUEUE/01.delay"
got=0
runner qualify slow-coder >"$WORK/qualify.out" 2>&1 || got=$?
[[ "$got" == 5 ]] || { cat "$WORK/qualify.out" >&2; fail "a slow first response: expected qualify exit 5, got $got"; }
status_out="$(runner status 2>&1)"
[[ "$status_out" == *"slow-coder (stub-model, setup "*"): unqualified"* ]] ||
  { echo "$status_out" >&2; fail "a timed-out qualify left the model qualified"; }

# --- 10. scoring, review, demotion, reset ----------------------------------------
# Fresh record for these checks.
runner reset stub-coder small >/dev/null 2>&1
reset_case
respond 01 "$GOOD"
expect_run 0 stub-coder
run_id="$(last_result | jq -r .run)"
[[ "$(last_result | jq -r .bucket)" == small ]] || fail "bucket was not computed from the file"
state_has stub-coder small '0/0 passed, 1 awaiting review' || fail "a published run was not pending: $(state_of stub-coder small)"
grep -q "record-review $run_id" "$WORK/run.out" || fail "the run did not print its record-review command"
runner record-review "$run_id" pass >/dev/null 2>&1 || fail "record-review pass failed"
state_has stub-coder small '1/1 passed' || fail "a review pass was not scored: $(state_of stub-coder small)"
runner record-review nope pass >/dev/null 2>&1 && fail "record-review accepted an unknown run"

for _ in 1 2 3 4 5; do
  reset_case
  respond 01 "$BAD"; respond 02 "$BAD"; respond 03 "$BAD"
  expect_run 10 stub-coder
done
state_has stub-coder small '1/6 passed' || fail "needs_frontier runs were not scored: $(state_of stub-coder small)"
if state_has stub-coder small DEMOTED; then fail "1/6 demoted (upper bound is above 50%)"; fi
for _ in 6 7 8; do
  reset_case
  respond 01 "$BAD"; respond 02 "$BAD"; respond 03 "$BAD"
  expect_run 10 stub-coder
done
state_has stub-coder small 'DEMOTED' || fail "1/9 was not demoted: $(state_of stub-coder small)"
reset_case
respond 01 "$GOOD"
expect_run 0 stub-coder
grep -q 'demoted for small tasks' "$WORK/run.out" || fail "a manual run of a demoted model did not warn"
runner reset stub-coder small >/dev/null 2>&1
if state_has stub-coder small DEMOTED; then fail "reset did not clear the demotion"; fi

reset_case
respond 01 "$GOOD"
expect_run 0 stub-coder
runner record-review "$(last_result | jq -r .run)" model-defect >/dev/null 2>&1
state_has stub-coder small 'DEMOTED' || fail "a model-defect review did not demote"
runner reset stub-coder small >/dev/null 2>&1
reset_case
respond 01 "$GOOD"
expect_run 0 stub-coder
runner record-review "$(last_result | jq -r .run)" packet-defect >/dev/null 2>&1
state_has stub-coder small '0/0 passed' || fail "a packet-defect review was scored against the model"

# --- 11. discover and selection ----------------------------------------------------
cat >>"$PROFILE" <<TOML

[[project]]
root = "$WORK/project"
policy = "off"
candidates = ["stub-coder", "dead-coder", "stub-coder-b"]
TOML
disc="$(runner discover 2>&1)"
[[ "$disc" == *"stub-model -> stub-coder: qualified, project candidate"* ]] ||
  { echo "$disc" >&2; fail "discover did not match stub-coder"; }
[[ "$disc" == *"stub-model -> stub-coder-b: unqualified, project candidate"* ]] || fail "discover did not show stub-coder-b"
[[ "$disc" == *"dead: unreachable"* ]] || fail "discover did not report the dead endpoint"

pol="$(runner policy 2>&1)" && fail "policy reported auto with policy = off"
[[ "$pol" == "off: policy is 'off'" ]] || fail "policy off reason wrong: $pol"
sed -i.bak 's/^policy = "off"$/policy = "auto"/' "$PROFILE" && rm -f "$PROFILE.bak"
pol="$(runner policy 2>&1)" && fail "policy reported auto without activation approval"
[[ "$pol" == *"activation_approved is not true"* ]] || fail "missing-approval reason wrong: $pol"
printf 'activation_approved = true\n' >>"$PROFILE"
pol="$(runner policy 2>&1)" || fail "policy is not auto when approved with a qualified candidate: $pol"
[[ "$pol" == "auto (qualified candidates: stub-coder)" ]] || fail "policy did not list qualified candidates: $pol"

# dead-coder looks qualified (its setup has a pass on record) but cannot be reached.
dead_fp="$(runner status 2>&1 | sed -n 's/^dead-coder (.*, setup \([0-9a-f]*\)).*/\1/p')"
[[ -n "$dead_fp" ]] || fail "status did not print dead-coder's setup"
jq -c -n --arg f "$dead_fp" '{model: "dead-coder", fingerprint: $f, result: "pass"}' >>"$WORK/local-models-qualified.jsonl"

expect_select() { # <status>
  local want="$1" got=0
  runner run "$PACKET" >"$WORK/run.out" 2>&1 || got=$?
  [[ "$got" == "$want" ]] || { cat "$WORK/run.out" >&2; fail "selected run: expected exit $want, got $got"; }
}
selected() { last_result | jq -r '"\(.selection.phase) \(.selection.chosen)"'; }

runner reset stub-coder small >/dev/null 2>&1
reset_case
respond 01 "$GOOD"
expect_select 0
[[ "$(selected)" == "explore stub-coder" ]] || fail "first selection was not explore stub-coder: $(selected)"
[[ "$(last_result | jq -r .mode)" == selected ]] || fail "selected run not labelled"
last_result | jq -e '.selection.considered[] | select(.model == "dead-coder") | .why == "unreachable"' >/dev/null ||
  fail "an unreachable candidate was not skipped as unreachable"
last_result | jq -e '.selection.considered[] | select(.model == "stub-coder-b") | .why == "unqualified"' >/dev/null ||
  fail "an unqualified candidate was not skipped"
runner record-review "$(last_result | jq -r .run)" pass >/dev/null 2>&1
for _ in 2 3 4 5; do
  reset_case
  respond 01 "$GOOD"
  expect_select 0
  runner record-review "$(last_result | jq -r .run)" pass >/dev/null 2>&1
done
state_has stub-coder small '5/5 passed' || fail "stub-coder did not reach five scored runs: $(state_of stub-coder small)"

qualify_with 0 stub-coder-b "$EXPECTED"
reset_case
respond 01 "$BAD"; respond 02 "$BAD"; respond 03 "$BAD"
expect_select 10
[[ "$(selected)" == "explore stub-coder-b" ]] || fail "a new qualified candidate was not explored: $(selected)"
[[ "$(last_result | jq -r .selection.runner_up)" == stub-coder ]] || fail "runner-up not recorded"
for _ in 2 3 4 5; do
  reset_case
  respond 01 "$BAD"; respond 02 "$BAD"; respond 03 "$BAD"
  expect_select 10
done
state_has stub-coder-b small DEMOTED || fail "0/5 was not demoted: $(state_of stub-coder-b small)"
reset_case
respond 01 "$GOOD"
expect_select 0
[[ "$(selected)" == "rank stub-coder" ]] || fail "selection did not rank stub-coder after exploration: $(selected)"
grep -q "selected 'stub-coder' by record" "$WORK/run.out" || fail "the selection reason was not printed"

# Nothing selectable: needs_frontier before any model call. A review defect
# on stub-coder's last run demotes it; stub-coder-b is already demoted and
# dead-coder is unreachable.
runner record-review "$(last_result | jq -r .run)" model-defect >/dev/null 2>&1
reset_case
respond 01 "$GOOD"
expect_select 10
grep -q 'no selectable candidate' "$WORK/run.out" || fail "an empty selection did not say why"
[[ -z "$(ls "$QUEUE/requests")" ]] || fail "a model was called with nothing selectable"

# --- 12. lock and ledger --------------------------------------------------------
[[ ! -e .agentic/delegate/lock ]] || fail "lock was left behind"
[[ "$(wc -l <.agentic/delegate/ledger.jsonl | tr -d ' ')" -ge 9 ]] || fail "not every run reached the ledger"
jq -e . .agentic/delegate/ledger.jsonl >/dev/null || fail "ledger has malformed records"
[[ -z "$(git status --porcelain --ignored=no -- .agentic/delegate)" ]] || fail "delegation state is not ignored"

echo "smoke-test OK: delegate runner"
