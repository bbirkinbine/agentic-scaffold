#!/usr/bin/env bash
# Smoke-test the local delegate runner (.agentic/delegate-run.sh) against a
# stub OpenAI-compatible server. Bootstraps the custom flavor with --full,
# fills its runner with a small shell toolchain, writes a one-file packet,
# and drives: init (a draft profile, never written, readable by the
# runner, skipping what exists); qualification (pass, wrong edit, fence,
# truncation, inline reasoning, unreachable endpoint, a setup change
# revoking it); runs (green
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

# Frontier-only projects must not need jq or a local profile.
mkdir -p "$WORK/no-jq-bin"
for dep in dirname date; do ln -s "$(command -v "$dep")" "$WORK/no-jq-bin/$dep"; done
got=0
PATH="$WORK/no-jq-bin" /bin/bash .agentic/delegate-run.sh policy --profile "$WORK/absent.toml" >"$WORK/no-profile.out" 2>&1 || got=$?
[[ "$got" == 1 ]] && grep -q '^off: no profile' "$WORK/no-profile.out" || fail "no-profile policy needs local dependencies"

# Options that require a value must fail promptly instead of looping on a
# failed `shift 2`.
python3 - <<'PY'
import subprocess

runner = ".agentic/delegate-run.sh"
cases = [
    ["run", "packet", "--model"],
    ["run", "packet", "--progress"],
    ["qualify", "model", "--profile"],
    ["init", "--key-env"],
    ["handoff", "spec", "--phase"],
    ["handoff", "spec", "--progress"],
    ["status", "--profile"],
    ["discover", "--profile"],
    ["policy", "--profile"],
    ["activate", "--profile"],
]
for args in cases:
    try:
        result = subprocess.run(
            ["bash", runner, *args], capture_output=True, text=True, timeout=2
        )
    except subprocess.TimeoutExpired as error:
        raise SystemExit(f"option parser hung: {' '.join(args)}") from error
    output = result.stdout + result.stderr
    if result.returncode != 2 or "requires a value" not in output:
        raise SystemExit(
            f"bad missing-option result for {' '.join(args)}: "
            f"exit {result.returncode}, output {output!r}"
        )
PY

for command in run handoff; do
  got=0
  bash .agentic/delegate-run.sh "$command" placeholder --progress noisy >"$WORK/progress-option.out" 2>&1 || got=$?
  [[ "$got" == 2 ]] && grep -q 'unknown progress mode' "$WORK/progress-option.out" ||
    fail "$command accepted an unknown progress mode"
done
help="$(bash .agentic/delegate-run.sh --help)"
[[ "$help" == *'run <packet> [--model <name>] [--progress quiet|summary]'* &&
  "$help" == *'handoff <spec> --allow-commit'* && "$help" == *'Progress is `summary`'* ]] ||
  fail "runner help omitted the progress interface"

# An existing project owns .gitignore. Updating adds only the new runtime
# entries, preserving custom content and remaining idempotent.
git check-ignore -q .pi/npm/.gitignore || fail "a fresh project does not ignore Pi's package directory"
sed '/^\.agentic\/delegate\/$/d; /^\.pi\/npm\/$/d' .gitignore >"$WORK/ignore.before"
printf '\n# Project-specific rule\nlocal-output/\n' >>"$WORK/ignore.before"
cp "$WORK/ignore.before" .gitignore
bash "$REPO_DIR/custom/bootstrap.sh" --update >/dev/null
git check-ignore -q .agentic/delegate/packets/probe.md || fail "--update did not ignore delegation state"
git check-ignore -q .pi/npm/.gitignore || fail "--update did not ignore Pi's package directory"
head -n "$(wc -l <"$WORK/ignore.before" | tr -d ' ')" .gitignore >"$WORK/ignore.prefix"
cmp -s "$WORK/ignore.before" "$WORK/ignore.prefix" || fail "--update changed existing ignore rules"
cp .gitignore "$WORK/ignore.after"
bash "$REPO_DIR/custom/bootstrap.sh" --update >/dev/null
cmp -s .gitignore "$WORK/ignore.after" || fail "the delegation ignore migration is not idempotent"

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
# Model a verifier that writes after the session's first scope audit.
text = text.replace('gate() {', '''gate() {
  if [[ -f .agentic/delegate/gate-write ]]; then
    case "$(cat .agentic/delegate/gate-write)" in
      outside) echo x >lib/gate-extra.sh ;;
      tests) echo 'exit 0' >tests/test_greet.sh ;;
      commit) git add -A; git commit -qm 'unexpected verifier commit' ;;
    esac
  fi''', 1)
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
format: 2
targets: [lib/greet.sh]
target_lines: 1
contract_items: 1
visible_tests: 1
test_targets: [tests/test_greet.sh]
new_dependencies: false
bucket: small
---
## Task

`greet NAME` prints `hello NAME`.
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
  shift 2
  bash .agentic/delegate-run.sh run "$PACKET" --model "$model" "$@" >"$WORK/run.out" 2>&1 || got=$?
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

# --- 0a. init drafts a profile and never writes one -------------------------------
draft="$WORK/draft.toml"
runner init --profile "$WORK/none.toml" --key-env STUB_TOKEN "http://127.0.0.1:$PORT/v1" >"$draft" 2>&1 ||
  { cat "$draft" >&2; fail "init failed"; }
[[ ! -e "$WORK/none.toml" ]] || fail "init wrote a profile"
for want in '[[endpoint]]' "base_url = \"http://127.0.0.1:$PORT/v1\"" 'credential_env = "STUB_TOKEN"' \
  'model_id = "stub-model"' 'quant = "CONFIRM"' '[[project]]' 'policy = "off"'; do
  grep -qF "$want" "$draft" || { cat "$draft" >&2; fail "init draft lacks: $want"; }
done
if grep -q smoke-secret-value "$draft"; then fail "init printed the key"; fi
status_out="$(runner status --profile "$draft" 2>&1)"
[[ "$status_out" == *"stub-model (stub-model, setup "*"): unqualified"* ]] ||
  { echo "$status_out" >&2; fail "the runner could not read init's draft"; }
again="$(runner init --profile "$PROFILE" --key-env STUB_TOKEN "http://127.0.0.1:$PORT/v1" 2>&1)"
[[ "$again" == *"is already in the profile"* && "$again" != *'name = "stub"'* ]] ||
  { echo "$again" >&2; fail "init repeated an endpoint already in the profile"; }
runner init "ftp://nope" >/dev/null 2>&1 && fail "init accepted a non-http URL"
runner init --key-env 'sk-123 abc' "http://127.0.0.1:$PORT/v1" >/dev/null 2>&1 && fail "init accepted a key in --key-env"

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
grep -q "summary: green — 'stub-coder' on lib/greet.sh (small)" "$WORK/run.out" || fail "the run summary was not printed"
grep -q "gate steps passed: lint format-check typecheck test" "$WORK/run.out" || fail "the summary did not list passing steps"
[[ "$(last_result | jq '.wall_seconds | type')" == '"number"' ]] || fail "wall time was not recorded"
[[ "$(cat "$QUEUE/requests/01.auth")" == "Bearer smoke-secret-value" ]] || fail "credential not sent"
jq -e '.temperature == 0.2 and .model == "stub-model" and .stream == false' "$QUEUE/requests/01.json" >/dev/null ||
  fail "request settings from the profile were not applied"
jq -e '.messages[0].content | contains("targets:") | not' "$QUEUE/requests/01.json" >/dev/null ||
  fail "packet front matter was sent to the model"
for want in '## The file as it exists now' 'greet() { echo "TODO"; }' '## The failing tests' \
  'tests/test_greet.sh' "expected 'hello bob'" '## Output contract' 'complete final contents of `lib/greet.sh`'; do
  jq -e --arg w "$want" '.messages[0].content | contains($w)' "$QUEUE/requests/01.json" >/dev/null ||
    fail "the runner did not add to the packet: $want"
done
run_dir=".agentic/delegate/results/$(last_result | jq -r .run)"
cmp -s <(jq -j '.messages[0].content' "$QUEUE/requests/01.json") "$run_dir/prompt.md" ||
  fail "prompt.md is not the message the model received"
cmp -s "$run_dir/candidate" lib/greet.sh || fail "the published candidate was not kept in the result"
if grep -rq smoke-secret-value .agentic/delegate; then fail "credential value leaked into delegation state"; fi
git diff --cached --quiet || fail "runner staged changes"

# --- 1b. bounded progress for a delayed one-file call ----------------------------
reset_case
respond 01 "$GOOD"
started="$(date +%s)"
DELEGATE_PROGRESS_INTERVAL=15 expect_run 0 stub-coder --progress summary
elapsed="$(($(date +%s) - started))"
((elapsed < 10)) || fail "stopping a heartbeat delayed a fast response (${elapsed}s)"

reset_case
respond 01 "$GOOD"
printf '2\n' >"$QUEUE/01.delay"
DELEGATE_PROGRESS_INTERVAL=1 expect_run 0 stub-coder --progress summary
grep -q 'progress: run .*logs: .agentic/delegate/results/' "$WORK/run.out" ||
  fail "summary mode did not print the run and result path before the call"
grep -q 'progress: generating .*attempt 1/3.*1s elapsed' "$WORK/run.out" ||
  fail "a delayed one-file call emitted no heartbeat"
grep -q 'progress: extracting candidate' "$WORK/run.out" || fail "one-file progress omitted extraction"
grep -q 'progress: verifying — format' "$WORK/run.out" || fail "one-file progress omitted verification stages"
greet_is "$GOOD" || fail "progress changed one-file publication"
[[ "$(last_result | jq -r .outcome)" == green ]] || fail "progress changed the one-file ledger outcome"
if grep -q smoke-secret-value "$WORK/run.out"; then fail "progress printed the endpoint credential"; fi

reset_case
respond 01 "$GOOD"
printf '2\n' >"$QUEUE/01.delay"
DELEGATE_PROGRESS_INTERVAL=1 expect_run 0 stub-coder --progress quiet
if grep -q 'progress:' "$WORK/run.out"; then fail "quiet mode emitted progress lines"; fi
greet_is "$GOOD" || fail "quiet progress changed one-file publication"

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

# --- 7b. bucket: a small label on medium counts is refused; a larger label stays --
reset_case
SAVED_PACKET="$PACKET"
PACKET=.agentic/delegate/packets/0001-lib-greet-sh-bucket.md
sed 's/^contract_items: 1$/contract_items: 12/' "$SAVED_PACKET" >"$PACKET"
expect_run 2 stub-coder
[[ -z "$(ls "$QUEUE/requests")" ]] || fail "a model was called for a mislabelled bucket"
grep -q "make it 'medium'" "$WORK/run.out" || fail "the bucket refusal did not name the corrected bucket"
sed -e 's/^bucket: small$/bucket: medium/' "$SAVED_PACKET" >"$PACKET"
respond 01 "$GOOD"
expect_run 0 stub-coder
[[ "$(last_result | jq -r .bucket)" == medium ]] || fail "a declared medium bucket was lowered to small"
reset_case
awk '/^bucket:/ { next } { print } /^target_lines:/ { print "expected_lines: 200" }' "$SAVED_PACKET" >"$PACKET"
respond 01 "$GOOD"
expect_run 0 stub-coder
[[ "$(last_result | jq -r .bucket)" == medium ]] || fail "expected_lines did not size the bucket"
PACKET="$SAVED_PACKET"
rm -f .agentic/delegate/packets/0001-lib-greet-sh-bucket.md

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
printf '%s\n' "$GOOD" '# review added this' >lib/greet.sh
runner record-review "$run_id" pass >"$WORK/review.out" 2>&1 || fail "record-review pass failed"
grep -q 'review kept 1 of 1 published lines in lib/greet.sh, removed 0, added 1' "$WORK/review.out" ||
  { cat "$WORK/review.out" >&2; fail "record-review did not measure review's changes"; }
jq -s -e --arg r "$run_id" 'map(select(.type == "review" and .run == $r)) | last | .review_changes.added_lines == 1' \
  .agentic/delegate/ledger.jsonl >/dev/null || fail "review changes were not recorded in the ledger"
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

# activate / deactivate edit only this checkout's [[project]] entry.
models_before="$(grep -c '^\[\[model\]\]' "$PROFILE")"
runner deactivate >"$WORK/act.out" 2>&1 || { cat "$WORK/act.out" >&2; fail "deactivate failed"; }
grep -q '^policy = "off"$' "$PROFILE" && grep -q '^activation_approved = false$' "$PROFILE" ||
  fail "deactivate did not set policy off and approval false"
runner policy >/dev/null 2>&1 && fail "policy still auto after deactivate"
grep -q 'before: policy = auto' "$WORK/act.out" || fail "deactivate did not print the before state"
runner activate >"$WORK/act.out" 2>&1 || { cat "$WORK/act.out" >&2; fail "activate failed"; }
runner policy >/dev/null 2>&1 || fail "policy not auto after activate"
[[ "$(grep -c '^activation_approved' "$PROFILE")" == 1 ]] || fail "activate duplicated activation_approved"
[[ "$(grep -c '^\[\[model\]\]' "$PROFILE")" == "$models_before" ]] || fail "activate changed the model entries"

# Exercise both stat dialects, including failed commands that emit stdout.
mkdir -p "$WORK/stat-bin"
cat >"$WORK/stat-bin/stat" <<'SH'
#!/usr/bin/env bash
case "$STAT_DIALECT:$1" in
  gnu:-c | bsd:-f) echo 600 ;;
  *) echo 'failed stat output must not reach chmod'; exit 1 ;;
esac
SH
chmod +x "$WORK/stat-bin/stat"
chmod 600 "$PROFILE"
for dialect in bsd gnu; do
  STAT_DIALECT="$dialect" PATH="$WORK/stat-bin:$PATH" runner deactivate >/dev/null 2>&1 || fail "$dialect stat deactivate failed"
  STAT_DIALECT="$dialect" PATH="$WORK/stat-bin:$PATH" runner activate >/dev/null 2>&1 || fail "$dialect stat activate failed"
done
[[ "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$PROFILE")" == 0o600 ]] ||
  fail "policy update changed profile permissions"
sed 's/^candidates = .*/candidates = ["stub-coder-b"]/' "$PROFILE" >"$WORK/unqualified.toml"
runner activate --profile "$WORK/unqualified.toml" >"$WORK/act.out" 2>&1 && fail "activate accepted a project with no qualified candidate"
grep -q 'no candidate' "$WORK/act.out" || fail "activate refusal did not name the reason"

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

# --- 13. handoff: a whole phase to a stub agent harness in a worktree -------------
reset_case
git config user.name smoke
git config user.email smoke@example.invalid
mkdir -p docs/specs
cat >docs/specs/0002-greet.md <<'MD'
# 0002 — Greet

**Status:** shipping

## Phase handoff

## Approved implementation plan

## Files to touch

- `lib/greet.sh` — print the greeting.
MD
git add -A >/dev/null && git commit -qm "spec 0002"
[[ -z "$(git status --porcelain)" ]] || fail "handoff setup left the tree dirty: $(git status --porcelain)"
HARNESS="$WORK/stub-harness"
# A stub Pi that speaks the RPC protocol: it answers get_state, prompt, steer,
# clear_queue, and abort by id, streams events, and does each mode's work in
# its working directory (the handoff worktree). Pi runs it under env -i, so
# the smoke directory is baked in.
printf '#!/usr/bin/env bash\nWORK=%q\n' "$WORK" >"$HARNESS"
cat >>"$HARNESS" <<'SH'
[[ "${1:-}" == --version ]] && { echo "stub-harness 1.0"; exit 0; }
env >"$WORK/harness-env"
printf '%s\n' "$@" >"$WORK/harness-args"
mode="$(cat "$WORK/harness-mode")"
session_dir="" session="" provider="" model="" resumed=0
while (($#)); do
  case "$1" in
    --session-dir) session_dir="$2"; shift 2 ;;
    --session) session="$2"; resumed=1; shift 2 ;;
    --provider) provider="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$session" ]] || session="$session_dir/stub-session.jsonl"
printf '%s\n' '{"type":"session","id":"stub-session"}' >>"$session"
[[ "$resumed" == 1 ]] && echo resumed >>"$WORK/harness-resumes"
[[ "$mode" == wrong-model ]] && model=other-model
spec=docs/specs/0002-greet.md
working=0 steered=0 ticks=0
emit() { printf '%s\n' "$1"; }
reply() {
  emit "$(jq -c -n --arg id "$1" --arg c "$2" --argjson d "${3:-null}" \
    '{id: $id, type: "response", command: $c, success: true} + (if $d == null then {} else {data: $d} end)')"
}
greet() { printf '%s\n' 'greet() { echo "hello $1"; }' >lib/greet.sh; }
settle() { emit "{\"type\":\"agent_settled\",\"aborted\":${1:-false}}"; working=0; }
complete() {
  case "$mode" in
    outside) greet; echo x >lib/extra.sh ;;
    tests) greet; echo 'exit 0' >tests/test_greet.sh ;;
    committed-tests) echo 'exit 0' >tests/test_greet.sh; git add tests/test_greet.sh; git commit -qm 'unexpected test commit'; greet ;;
    committed-outside) echo x >lib/committed-extra.sh; git add lib/committed-extra.sh; git commit -qm 'unexpected outside commit' ;;
    branch) git checkout -q -b unexpected-handoff-branch ;;
    gate-*) greet; mkdir -p .agentic/delegate; printf '%s\n' "${mode#gate-}" >.agentic/delegate/gate-write ;;
    red) printf '%s\n' 'greet() { echo "bye $1"; }' >lib/greet.sh ;;
    *) [[ -e .pi/npm/seed-marker ]] && : >"$WORK/harness-seeded"; greet ;;
  esac
  printf '%s\n' '### After handoff' 'Implemented greet.' >>"$spec"
  emit '{"type":"tool_execution_start","toolCallId":"w1","toolName":"write","args":{"path":"lib/greet.sh"}}'
  emit '{"type":"tool_execution_end","toolCallId":"w1","toolName":"write","result":{},"isError":false,"durationMs":3}'
  settle
}
progress_stream() {
  for _ in $(seq 1 50); do
    grep -qF 'progress: agent started' "$WORK/handoff.out" && break
    sleep 0.1
  done
  grep -qF 'progress: agent started' "$WORK/handoff.out" || exit 8
  printf '%s\n' \
    '{"type":"turn_start"}' \
    '{"type":"tool_execution_start","toolCallId":"read-1","toolName":"read","args":{"path":"lib/greet.sh"}}' \
    '{"type":"tool_execution_end","toolCallId":"read-1","toolName":"read","result":{},"isError":false,"durationMs":7}' \
    '{"type":"tool_execution_start","toolCallId":"write-1","toolName":"write","args":{"path":"lib/\u001b[31munsafe.sh"}}'
  printf '%s' '{"type":"tool_execution_start","toolCallId":"split-1",'
  sleep 0.3
  printf '%s\n' '"toolName":"edit","args":{"path":"lib/split.sh"}}'
  printf '%s\n' \
    '{"type":"tool_execution_start","toolCallId":"bash-1","toolName":"bash","args":{"command":"TOKEN=bare-token PASSWORD=bare-password API_KEY=bare-api STUB_TOKEN=smoke-secret-value printf éééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééé END-OF-LONG-COMMAND"}}' \
    '{"type":"tool_execution_end","toolCallId":"bash-1","toolName":"bash","result":{},"isError":true,"durationMs":12}' \
    '{"type":"auto_retry_start","attempt":1,"maxAttempts":3,"delayMs":2000,"errorMessage":"secret detail"}' \
    '{"type":"auto_retry_end","success":true,"attempt":2}' \
    '{"type":"compaction_start","reason":"threshold"}' \
    '{"type":"compaction_end","reason":"threshold","result":{"summary":"private summary"},"aborted":false,"willRetry":false}' \
    '{"type":"message_end","message":{"role":"assistant","content":"private assistant text","stopReason":"stop"}}' \
    '{"type":"future_event","private":"do not render"}' \
    'not-json'
  printf '%s\n' 'pi diagnostic' >&2
}
start() {
  emit '{"type":"agent_start"}'
  working=1
  case "$mode" in
    crash) exit 7 ;;
    progress) progress_stream; complete ;;
    dialog) emit '{"type":"extension_ui_request","id":"dlg-1","method":"confirm","title":"Allow?","message":"Allow this tool?"}' ;;
    hang) ;;
    hang-tool)
      # Like a wedged Pi: a tool command in its own process group, TERM
      # ignored, abort never answered, and stdin EOF ignored.
      trap '' TERM
      perl -e 'setpgrp(0, 0); exec "sleep", "300"' &
      echo "$!" >"$WORK/tool.pid"
      emit '{"type":"tool_execution_start","toolCallId":"t1","toolName":"bash","args":{"command":"sleep 300"}}'
      ;;
    busy) ;;
    checkpoint | retry-loop) ((resumed)) && complete ;;
    *) complete ;;
  esac
}
tick() {
  ((working)) || return 0
  ticks=$((ticks + 1))
  case "$mode" in
    busy)
      emit '{"type":"tool_execution_update","toolCallId":"b1","toolName":"bash","partialResult":{}}'
      ((ticks >= 6)) && complete
      ;;
    checkpoint) emit '{"type":"tool_execution_update","toolCallId":"c1","toolName":"bash","partialResult":{}}' ;;
    retry-loop) emit '{"type":"auto_retry_start","attempt":1,"maxAttempts":3,"delayMs":1000,"errorMessage":"overloaded"}' ;;
  esac
  if ((steered && working)) && [[ "$mode" == checkpoint || "$mode" == retry-loop ]]; then
    printf '%s\n' '### Paused handoff' 'Paused at a checkpoint; greet is not written yet.' >>"$spec"
    settle
  fi
}
while :; do
  line=""
  if IFS= read -r -t 1 line; then
    id="$(jq -r '.id // ""' <<<"$line" 2>/dev/null)"
    case "$(jq -r '.type // ""' <<<"$line" 2>/dev/null)" in
      get_state)
        reply "$id" get_state "$(jq -c -n --arg p "$provider" --arg m "$model" --arg f "$session" \
          '{model: {provider: $p, id: $m}, sessionFile: $f, sessionId: "stub-session", isStreaming: false}')"
        ;;
      prompt) reply "$id" prompt '{"disposition":"started"}'; start ;;
      steer) reply "$id" steer '{"disposition":"queued"}'; steered=1; echo steer >>"$WORK/harness-steers" ;;
      clear_queue) reply "$id" clear_queue '{"steering":[],"followUp":[]}' ;;
      abort) [[ "$mode" == hang-tool ]] || { settle true; reply "$id" abort; } ;;
      extension_ui_response)
        printf '%s\n' "$line" >>"$WORK/harness-ui"
        [[ "$mode" == dialog ]] && complete
        ;;
    esac
  else
    rc=$?
    if ((rc <= 128)); then
      [[ "$mode" == hang-tool ]] || exit 0
      while :; do sleep 1; done
    fi
  fi
  tick
done
SH
chmod +x "$HARNESS"
# handoff <exit> <mode> [args] : one attached (--foreground) handoff run.
handoff() {
  local want="$1" mode="$2" got=0
  shift 2
  echo "$mode" >"$WORK/harness-mode"
  DELEGATE_HANDOFF_HARNESS="$HARNESS" DELEGATE_HANDOFF_DIR="$WORK/handoffs" HANDOFF_SMOKE_SECRET=leak \
    bash .agentic/delegate-run.sh handoff docs/specs/0002-greet.md --allow-commit --foreground \
      --model "${HANDOFF_MODEL:-stub-coder}" "$@" >"$WORK/handoff.out" 2>&1 || got=$?
  [[ "$got" == "$want" ]] || { cat "$WORK/handoff.out" >&2; fail "handoff $mode: expected exit $want, got $got"; }
}
# hrunner <args> : the runner with the stub harness and smoke handoff directory.
hrunner() { DELEGATE_HANDOFF_HARNESS="$HARNESS" DELEGATE_HANDOFF_DIR="$WORK/handoffs" bash .agentic/delegate-run.sh "$@"; }
handoff_run_id() { sed -n 's/^.*(branch handoff\/\(handoff-[A-Za-z0-9._-]*\)).*$/\1/p' "$1" | head -n 1; }
state_of() { jq -r "$2" ".agentic/delegate/results/$1/state.json"; }
run_records() { jq -c --arg r "$1" 'select((.type // "run") == "run" and .run == $r)' .agentic/delegate/ledger.jsonl | wc -l | tr -d ' '; }
drop_worktrees() { runner handoff-clean --all >/dev/null 2>&1; return 0; }

# The runner cannot infer commit authority from the selected delegation mode.
got=0
hrunner handoff docs/specs/0002-greet.md --model stub-coder >"$WORK/handoff.out" 2>&1 || got=$?
[[ "$got" == 2 ]] && grep -q -- '--allow-commit' "$WORK/handoff.out" || fail "handoff did not require explicit commit acknowledgement"
[[ "$(git worktree list | wc -l | tr -d ' ')" == 1 ]] || fail "refused handoff created a worktree"

# A Pi JSONL stream is recorded in full but rendered as bounded, redacted
# transitions. Malformed and unknown future records remain raw and do not fail
# the handoff.
handoff 0 progress --progress summary
for want in 'progress: agent started' 'progress: tool start: read — lib/greet.sh' \
  'progress: tool end: read — passed (7ms)' 'progress: tool start: edit — lib/split.sh' \
  'progress: tool start: bash' \
  'progress: tool end: bash — failed (12ms)' 'progress: retry 1/3 scheduled' \
  'progress: retry 2 succeeded' 'progress: compaction started (threshold)' \
  'progress: compaction ended (threshold)' 'progress: agent settled'; do
  grep -qF "$want" "$WORK/handoff.out" || { cat "$WORK/handoff.out" >&2; fail "handoff summary lacks: $want"; }
done
if grep -Eq 'bare-token|bare-password|bare-api|smoke-secret-value|END-OF-LONG-COMMAND|private summary|private assistant text|secret detail|do not render' "$WORK/handoff.out"; then
  fail "handoff summary exposed a secret, oversized field, or private event data"
fi
if LC_ALL=C grep -q $'\033' "$WORK/handoff.out"; then fail "handoff summary retained terminal control characters"; fi
python3 - "$WORK/handoff.out" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_bytes().decode("utf-8")
line = next(line for line in text.splitlines() if "progress: tool start: bash — " in line)
detail = line.split(" — ", 1)[1]
if len(detail.encode("utf-8")) > 160:
    raise SystemExit(f"progress detail exceeded 160 bytes: {len(detail.encode('utf-8'))}")
PY
run_id="$(last_result | jq -r .run)"
run_dir=".agentic/delegate/results/$run_id"
grep -qF 'not-json' "$run_dir/segments/0001/events.jsonl" || fail "raw handoff events were not retained"
grep -qF 'pi diagnostic' "$run_dir/segments/0001/harness.log" || fail "Pi stderr was not retained separately"
[[ "$(last_result | jq -r .outcome)" == green ]] || fail "progress changed the handoff ledger outcome"
[[ "$(state_of "$run_id" .state)" == green && "$(state_of "$run_id" '.segments | length')" == 1 ]] ||
  fail "a green handoff did not record its final state and one segment"
runner handoff-clean "$run_id" >/dev/null 2>&1 || fail "could not clean the progress handoff"

handoff 0 good --progress quiet
if grep -q 'progress:' "$WORK/handoff.out"; then fail "quiet handoff emitted progress lines"; fi
run_id="$(last_result | jq -r .run)"
runner handoff-clean "$run_id" >/dev/null 2>&1 || fail "could not clean the quiet handoff"

mkdir -p .pi/npm && : >.pi/npm/seed-marker
rm -f "$WORK/harness-seeded"
handoff 0 good
[[ -e "$WORK/harness-seeded" ]] || fail "the handoff worktree did not receive the checkout's Pi packages"
branch="$(git branch --list 'handoff/*' --format='%(refname:short)' | head -n 1)"
[[ -n "$branch" ]] || fail "a verified handoff left no handoff branch"
[[ "$(git show "$branch:lib/greet.sh")" == 'greet() { echo "hello $1"; }' ]] || fail "the handoff branch does not hold the session's work"
greet_is "$(cat "$WORK/greet.baseline")" || fail "a handoff changed the main working tree"
[[ "$(last_result | jq -r .bucket)" == phase:implement ]] || fail "handoff was not recorded under its phase bucket"
grep -q '^stub$' "$WORK/harness-args" && grep -q '^stub-model$' "$WORK/harness-args" || fail "the harness was not given the profile provider/model"
grep -q '^--approve$' "$WORK/harness-args" && grep -q '^rpc$' "$WORK/harness-args" || fail "the harness was not run with --approve in RPC mode"
if grep -q HANDOFF_SMOKE_SECRET "$WORK/harness-env"; then fail "the session inherited an unlisted environment variable"; fi
run_id="$(last_result | jq -r .run)"
agent_dir="$(sed -n 's/^PI_CODING_AGENT_DIR=//p' "$WORK/harness-env")"
[[ "$agent_dir" == "$WORK/project/.agentic/delegate/results/$run_id/pi-agent" ]] || fail "handoff did not isolate Pi configuration"
grep -qxF "npm_config_cache=$WORK/project/.agentic/delegate/results/$run_id/npm-cache" "$WORK/harness-env" ||
  fail "the session's npm cache is not inside the run directory"
jq -e --arg url "http://127.0.0.1:$PORT/v1" \
  '.providers.stub | .baseUrl == $url and .api == "openai-completions" and .apiKey == "$STUB_TOKEN" and .models[0].id == "stub-model" and .models[0].samplingParams.temperature == 0.2' \
  "$agent_dir/models.json" >/dev/null || fail "Pi provider does not match the selected profile model"
! grep -q "$STUB_TOKEN" "$agent_dir/models.json" || fail "Pi provider file contains the credential value"
runner record-review "$run_id" pass >/dev/null 2>&1 || fail "record-review did not accept a handoff run"
runner handoff-clean | grep -q "${run_id}" || fail "handoff-clean did not list the kept worktree"
runner handoff-clean "$run_id" >/dev/null 2>&1 || fail "handoff-clean could not remove one run"
[[ -z "$(git branch --list 'handoff/*')" && "$(git worktree list | wc -l | tr -d ' ')" == 1 ]] ||
  fail "handoff-clean left a worktree or branch behind"

handoff 4 outside
grep -q 'lib/extra.sh' "$WORK/handoff.out" || fail "an out-of-plan change was not named"
drop_worktrees
handoff 4 tests
grep -q 'tests/test_greet.sh' "$WORK/handoff.out" || fail "a test-file change in the implement phase was not named"
drop_worktrees
for mode in committed-tests committed-outside gate-outside gate-tests gate-commit; do
  handoff 4 "$mode"
  drop_worktrees
done
# A branch switch is rejected too; remove only this fixture's extra branch.
handoff 4 branch
wt="$(git worktree list --porcelain | sed -n '\|^worktree .*handoffs/|s/^worktree //p' | head -n 1)"
git -C "$wt" checkout -q "handoff/$(last_result | jq -r .run)"
git branch -D unexpected-handoff-branch >/dev/null
drop_worktrees

# Handoff scoring uses the same fingerprint during selection, status, and
# review. A failed model is skipped, phase reset restores it, and a harness
# version change starts a fresh phase record without revoking HTTP plumbing.
handoff 0 good
run_id="$(last_result | jq -r .run)"
runner record-review "$run_id" model-defect >/dev/null 2>&1
DELEGATE_HANDOFF_HARNESS="$HARNESS" runner status >"$WORK/phase-status" 2>&1
grep -q 'phase:implement:.*DEMOTED' "$WORK/phase-status" || fail "status lost the handoff demotion"
drop_worktrees
echo good >"$WORK/harness-mode"
hrunner handoff docs/specs/0002-greet.md --allow-commit --foreground >"$WORK/handoff.out" 2>&1 || { cat "$WORK/handoff.out" >&2; fail "selected handoff failed"; }
[[ "$(selected)" == 'explore stub-coder-b' ]] || fail "selection reused a phase-demoted model"
drop_worktrees
runner reset stub-coder phase:implement >/dev/null 2>&1 || fail "phase reset failed"
DELEGATE_HANDOFF_HARNESS="$HARNESS" runner status >"$WORK/phase-status" 2>&1
grep -q 'phase:implement: 0/0 passed' "$WORK/phase-status" || fail "phase reset did not clear the record"
runner reset stub-coder phase:test-first+implement >/dev/null 2>&1 || fail "combined phase reset failed"
handoff 0 good
runner record-review "$(last_result | jq -r .run)" model-defect >/dev/null 2>&1
drop_worktrees
sed 's/stub-harness 1.0/stub-harness 2.0/' "$HARNESS" >"$WORK/harness-new"
cat "$WORK/harness-new" >"$HARNESS"
hrunner handoff docs/specs/0002-greet.md --allow-commit --foreground >"$WORK/handoff.out" 2>&1 || { cat "$WORK/handoff.out" >&2; fail "new harness handoff failed"; }
[[ "$(selected)" == 'explore stub-coder' ]] || fail "a new harness did not start a fresh phase record"
drop_worktrees
handoff 10 red
[[ "$(last_result | jq -r .outcome)" == needs_frontier ]] || fail "a red gate after the session was not needs_frontier"
drop_worktrees
handoff 3 crash --progress summary
[[ "$(last_result | jq -r .outcome)" == infrastructure ]] || fail "progress changed the crash ledger outcome"
drop_worktrees
# An unknown model id does not fail Pi's startup; the runner compares the
# model Pi resolved with the profile before prompting.
handoff 3 wrong-model
grep -q "resolved model 'stub/other-model'" "$WORK/handoff.out" || fail "a model mismatch was not reported"
drop_worktrees

# --- 13b. supervision: lease, checkpoint, pause, resume -------------------------
export DELEGATE_PROGRESS_INTERVAL=1 DELEGATE_HANDOFF_ABORT_SECONDS=3 DELEGATE_HANDOFF_GRACE_SECONDS=3

# Steady activity renews a short lease; the run completes without a pause.
DELEGATE_HANDOFF_LEASE_SECONDS=2 handoff 0 busy --progress summary
[[ ! -s "$WORK/harness-steers" ]] || fail "an active session was asked to checkpoint"
drop_worktrees

# A dialog is answered "cancelled" instead of blocking the session.
rm -f "$WORK/harness-ui"
handoff 0 dialog --progress summary
jq -e 'select(.id == "dlg-1") | .cancelled == true' "$WORK/harness-ui" >/dev/null || fail "an extension dialog was not cancelled"
grep -q 'cancelled an extension confirm dialog' "$WORK/handoff.out" || fail "the dialog cancel was not reported"
drop_worktrees

# Retries alone do not renew the lease: one recovery grace, then a checkpoint.
rm -f "$WORK/harness-steers"
DELEGATE_HANDOFF_LEASE_SECONDS=2 DELEGATE_HANDOFF_RECOVERY_SECONDS=2 handoff 11 retry-loop --progress summary
grep -q 'lease extended 2s: retry or compaction recovery' "$WORK/handoff.out" || fail "recovery did not get one grace"
grep -q 'requesting a checkpoint: no meaningful activity' "$WORK/handoff.out" || fail "a retry storm renewed the lease"
[[ -s "$WORK/harness-steers" ]] || fail "the checkpoint was not sent as a steer"
drop_worktrees

# A silent session ignores the checkpoint; abort forces the pause. The old
# hard-limit variable now sets the ceiling, with a warning.
DELEGATE_HANDOFF_TIMEOUT=2 handoff 11 hang --progress summary
grep -q 'DELEGATE_HANDOFF_TIMEOUT is deprecated' "$WORK/handoff.out" || fail "the legacy timeout gave no deprecation warning"
grep -q 'the pause was forced' "$WORK/handoff.out" || fail "a forced pause was described as clean"
run_id="$(handoff_run_id "$WORK/handoff.out")"
[[ "$(state_of "$run_id" .state)" == paused && "$(state_of "$run_id" .forced)" == true ]] || fail "a forced pause was not recorded"
[[ "$(run_records "$run_id")" == 0 ]] || fail "a pause was written to the ledger as an outcome"
[[ -z "$(git -C "$WORK/handoffs/$run_id" log --oneline "$(git rev-parse HEAD)..HEAD")" ]] || fail "a pause created a commit"
drop_worktrees

# A wedged session: abort unanswered, TERM and EOF ignored, a tool in its own
# process group. Signals end it, and the tool group is killed too.
DELEGATE_HANDOFF_LEASE_SECONDS=2 handoff 11 hang-tool
sleep 0.5
if kill -0 "$(cat "$WORK/tool.pid")" 2>/dev/null; then
  kill -KILL "$(cat "$WORK/tool.pid")"
  fail "a forced pause left a tool process group running"
fi
drop_worktrees

# Graceful pause at the absolute ceiling, then resume in the same worktree
# and session to a single green outcome.
rm -f "$WORK/harness-resumes"
DELEGATE_HANDOFF_MAX_TOTAL_SECONDS=2 handoff 11 checkpoint --progress summary
grep -q 'requesting a checkpoint: absolute ceiling' "$WORK/handoff.out" || fail "the ceiling did not request a checkpoint"
grep -q 'settled at a checkpoint' "$WORK/handoff.out" || fail "a graceful pause was not reported as one"
run_id="$(handoff_run_id "$WORK/handoff.out")"
wt="$WORK/handoffs/$run_id"
grep -q '^### Paused handoff' "$wt/docs/specs/0002-greet.md" || fail "the paused session wrote no pause note"
got=0; hrunner handoff-status "$run_id" >"$WORK/status.out" 2>&1 || got=$?
[[ "$got" == 11 ]] && grep -q '^state: paused' "$WORK/status.out" || { cat "$WORK/status.out" >&2; fail "status did not report the pause"; }
# Refusals leave the run paused: no commit authority, a spent ceiling, a
# changed spec, and a changed harness.
got=0; hrunner handoff-resume "$run_id" --foreground >"$WORK/resume.out" 2>&1 || got=$?
[[ "$got" == 2 ]] || fail "resume did not require --allow-commit"
got=0; hrunner handoff-resume "$run_id" --allow-commit --foreground >"$WORK/resume.out" 2>&1 || got=$?
[[ "$got" == 2 ]] && grep -q 'ceiling' "$WORK/resume.out" || { cat "$WORK/resume.out" >&2; fail "a spent ceiling did not refuse resume"; }
echo '<!-- edited -->' >>docs/specs/0002-greet.md
got=0; hrunner handoff-resume "$run_id" --allow-commit --max-total 600 --foreground >"$WORK/resume.out" 2>&1 || got=$?
[[ "$got" == 2 ]] && grep -q 'spec .* changed' "$WORK/resume.out" || { cat "$WORK/resume.out" >&2; fail "a changed spec did not refuse resume"; }
git checkout -q -- docs/specs/0002-greet.md
cp "$HARNESS" "$WORK/harness-saved"
sed 's/stub-harness 2.0/stub-harness 3.0/' "$WORK/harness-saved" >"$HARNESS"
got=0; hrunner handoff-resume "$run_id" --allow-commit --max-total 600 --foreground >"$WORK/resume.out" 2>&1 || got=$?
[[ "$got" == 2 ]] && grep -q 'fingerprint' "$WORK/resume.out" || { cat "$WORK/resume.out" >&2; fail "a changed harness did not refuse resume"; }
cat "$WORK/harness-saved" >"$HARNESS"
[[ "$(state_of "$run_id" .state)" == paused ]] || fail "a refused resume changed the paused state"
got=0; hrunner handoff-resume "$run_id" --allow-commit --max-total 600 --foreground >"$WORK/resume.out" 2>&1 || got=$?
[[ "$got" == 0 ]] || { cat "$WORK/resume.out" >&2; fail "resume did not finish green (exit $got)"; }
[[ -s "$WORK/harness-resumes" ]] && grep -q '^--session$' "$WORK/harness-args" || fail "resume did not reopen the saved session"
[[ "$(state_of "$run_id" '.segments | length')" == 2 && -s ".agentic/delegate/results/$run_id/segments/0002/events.jsonl" ]] ||
  fail "resume did not record a second segment"
[[ "$(run_records "$run_id")" == 1 && "$(last_result | jq -r '.attempts | length')" == 2 ]] ||
  fail "a paused and resumed handoff did not produce one ledger outcome with both segments"
[[ "$(git show "handoff/$run_id:lib/greet.sh")" == 'greet() { echo "hello $1"; }' ]] || fail "the resumed work was not committed"
runner record-review "$run_id" pass >/dev/null 2>&1 || fail "record-review did not accept the resumed run id"
drop_worktrees

# Detached by default: launch returns at once; status waits token-free.
echo good >"$WORK/harness-mode"
got=0; hrunner handoff docs/specs/0002-greet.md --allow-commit --model stub-coder >"$WORK/launch.out" 2>&1 || got=$?
[[ "$got" == 0 ]] && grep -q 'launched handoff-' "$WORK/launch.out" || { cat "$WORK/launch.out" >&2; fail "detached launch failed"; }
run_id="$(tail -n 1 "$WORK/launch.out")"
got=0; hrunner handoff-status "$run_id" --wait 120 >"$WORK/status.out" 2>&1 || got=$?
[[ "$got" == 0 ]] && grep -q '^state: green' "$WORK/status.out" || { cat "$WORK/status.out" >&2; fail "status --wait did not report the detached green run"; }
drop_worktrees
# A detached refusal is still synchronous.
echo dirty >>lib/greet.sh
got=0; hrunner handoff docs/specs/0002-greet.md --allow-commit --model stub-coder >"$WORK/launch.out" 2>&1 || got=$?
[[ "$got" == 2 ]] && grep -q 'not clean' "$WORK/launch.out" || { cat "$WORK/launch.out" >&2; fail "a detached refusal was not reported synchronously"; }
reset_case

# Operator stop: a live detached run checkpoints and pauses on request.
echo checkpoint >"$WORK/harness-mode"
hrunner handoff docs/specs/0002-greet.md --allow-commit --model stub-coder >"$WORK/launch.out" 2>&1 || fail "stop-test launch failed"
run_id="$(tail -n 1 "$WORK/launch.out")"
for _ in $(seq 1 100); do [[ "$(state_of "$run_id" .state)" == running ]] && [[ -n "$(state_of "$run_id" '.live.pi_pid // empty')" ]] && break; sleep 0.2; done
got=0; hrunner handoff-status "$run_id" --wait 1 >"$WORK/status.out" 2>&1 || got=$?
[[ "$got" == 12 ]] && grep -q '^live segment 0001' "$WORK/status.out" || { cat "$WORK/status.out" >&2; fail "status did not report a live run"; }
hrunner handoff-stop "$run_id" >/dev/null 2>&1 || fail "handoff-stop failed"
got=0; hrunner handoff-status "$run_id" --wait 60 >"$WORK/status.out" 2>&1 || got=$?
[[ "$got" == 11 ]] && grep -q 'operator stop' "$WORK/status.out" || { cat "$WORK/status.out" >&2; fail "an operator stop did not pause the run"; }
drop_worktrees

# Orphaned: the runner dies (SIGKILL). Pi sees EOF and exits, the lock is
# left behind; status reports it, and resume takes the stale lock over.
hrunner handoff docs/specs/0002-greet.md --allow-commit --model stub-coder >"$WORK/launch.out" 2>&1 || fail "orphan-test launch failed"
run_id="$(tail -n 1 "$WORK/launch.out")"
for _ in $(seq 1 100); do [[ -n "$(state_of "$run_id" '.live.pi_pid // empty')" ]] && break; sleep 0.2; done
kill -KILL "$(state_of "$run_id" .runner_pid)"
for _ in $(seq 1 50); do [[ -e ".agentic/delegate/results/$run_id/segments/0001/exit.status" ]] && break; sleep 0.2; done
got=0; hrunner handoff-status "$run_id" >"$WORK/status.out" 2>&1 || got=$?
[[ "$got" == 11 ]] && grep -q '^state: orphaned' "$WORK/status.out" || { cat "$WORK/status.out" >&2; fail "status did not report the orphaned run"; }
[[ -d .agentic/delegate/lock ]] || fail "the orphan test expected a stale lock"
got=0; hrunner handoff-resume "$run_id" --allow-commit --foreground >"$WORK/resume.out" 2>&1 || got=$?
[[ "$got" == 0 ]] && grep -q 'taking over a stale lock' "$WORK/resume.out" || { cat "$WORK/resume.out" >&2; fail "an orphaned run did not resume green"; }
drop_worktrees
unset DELEGATE_PROGRESS_INTERVAL DELEGATE_HANDOFF_ABORT_SECONDS DELEGATE_HANDOFF_GRACE_SECONDS

# --- 13c. the same through real Pi RPC (loopback stub, no real model) -----------
# tool_call <NN> <tool> <args-json> : a queued streamed tool call.
tool_call() {
  jq -n --arg n "$2" --argjson a "$3" \
    '{choices: [{index: 0, finish_reason: "tool_calls", message: {role: "assistant", content: null,
      tool_calls: [{index: 0, id: "call_\($n)", type: "function", function: {name: $n, arguments: ($a | tojson)}}]}}]}' \
    >"$QUEUE/$1.json"
}
if command -v pi >/dev/null 2>&1; then
  # Pi resolves the isolated provider and sends the selected model and
  # credential to the loopback stub. Print mode reads piped stdin, so each
  # direct call gets /dev/null.
  reset_case
  respond 01 OK
  (cd "$WORK" && PI_CODING_AGENT_DIR="$agent_dir" pi --offline --no-extensions --no-mcp --no-skills \
    --no-context-files --no-prompt-templates --no-session --no-approve \
    --provider stub --model stub-model -p 'Reply OK without tools.' </dev/null) >"$WORK/pi-provider.out" 2>&1 ||
    { cat "$WORK/pi-provider.out" >&2; fail "Pi could not use the generated provider"; }
  jq -e '.model == "stub-model" and .temperature == 0.2' "$QUEUE/requests/01.json" >/dev/null || fail "Pi used the wrong model/settings"
  [[ "$(cat "$QUEUE/requests/01.auth")" == "Bearer $STUB_TOKEN" ]] || fail "Pi did not resolve the credential variable"
  # A real Pi start in this --full project installs the packages named in
  # .pi/settings.json (network required). The tree must stay clean, or every
  # handoff's scope audit would stop on Pi's own files.
  rm -rf .pi/npm
  reset_case
  respond 01 OK
  PI_CODING_AGENT_DIR="$agent_dir" npm_config_cache="$WORK/npm-cache" pi --approve --no-session \
    --provider stub --model stub-model -p 'Reply OK without tools.' </dev/null >"$WORK/pi-project.out" 2>&1 ||
    { cat "$WORK/pi-project.out" >&2; fail "Pi could not start in the --full project"; }
  [[ -z "$(git status --porcelain)" ]] || fail "a real Pi start left the project dirty: $(git status --porcelain)"

  # A green phase through real Pi RPC: one write, one final answer.
  reset_case
  tool_call 01 write "$(jq -c -n '{path: "lib/greet.sh", content: "greet() { echo \"hello $1\"; }\n"}')"
  respond 02 'Implemented greet.'
  got=0
  DELEGATE_HANDOFF_DIR="$WORK/handoffs" runner handoff docs/specs/0002-greet.md --allow-commit --foreground \
    --model stub-coder >"$WORK/pi-handoff.out" 2>&1 || got=$?
  [[ "$got" == 0 ]] || { cat "$WORK/pi-handoff.out" >&2; fail "a real-Pi handoff did not verify green (exit $got)"; }
  run_id="$(last_result | jq -r .run)"
  [[ "$(git show "handoff/$run_id:lib/greet.sh")" == 'greet() { echo "hello $1"; }' ]] || fail "real Pi's write was not committed"
  drop_worktrees

  # Pause at the ceiling during a tool call: the steer reaches the next model
  # request; Pi settles; resume reopens the session with its history.
  reset_case
  tool_call 01 bash '{"command":"sleep 4"}'
  respond 02 'Paused; nothing written yet.'
  tool_call 03 write "$(jq -c -n '{path: "lib/greet.sh", content: "greet() { echo \"hello $1\"; }\n"}')"
  respond 04 'Implemented greet.'
  got=0
  DELEGATE_HANDOFF_DIR="$WORK/handoffs" DELEGATE_HANDOFF_MAX_TOTAL_SECONDS=2 runner handoff docs/specs/0002-greet.md \
    --allow-commit --foreground --model stub-coder >"$WORK/pi-handoff.out" 2>&1 || got=$?
  [[ "$got" == 11 ]] && grep -q 'settled at a checkpoint' "$WORK/pi-handoff.out" ||
    { cat "$WORK/pi-handoff.out" >&2; fail "real Pi did not pause gracefully at the ceiling (exit $got)"; }
  grep -q 'Checkpoint requested by the handoff supervisor' "$QUEUE/requests/02.json" || fail "the checkpoint steer did not reach the next model request"
  run_id="$(handoff_run_id "$WORK/pi-handoff.out")"
  got=0
  DELEGATE_HANDOFF_DIR="$WORK/handoffs" runner handoff-resume "$run_id" --allow-commit --max-total 600 --foreground \
    >"$WORK/pi-resume.out" 2>&1 || got=$?
  [[ "$got" == 0 ]] || { cat "$WORK/pi-resume.out" >&2; fail "real Pi did not resume to green (exit $got)"; }
  jq -e '[.messages[] | .content | tostring] | (any(test("isolated worktree")) and any(test("resuming a paused local handoff")))' \
    "$QUEUE/requests/03.json" >/dev/null || fail "the resumed request lost the session history"
  [[ "$(run_records "$run_id")" == 1 ]] || fail "real-Pi pause and resume did not produce one ledger outcome"
  drop_worktrees
elif [[ -n "${CI:-}" ]]; then
  fail "pi is not installed; CI must run the real-Pi handoff checks"
fi
[[ -z "$(git branch --list 'handoff/*')" && "$(git worktree list | wc -l | tr -d ' ')" == 1 ]] ||
  fail "handoff-clean --all left worktrees or branches behind"
echo dirty >>lib/greet.sh
handoff 2 good
grep -q 'not clean' "$WORK/handoff.out" || fail "a dirty tree was not refused"
reset_case

# --- 12. lock and ledger --------------------------------------------------------
[[ ! -e .agentic/delegate/lock ]] || fail "lock was left behind"
[[ "$(wc -l <.agentic/delegate/ledger.jsonl | tr -d ' ')" -ge 9 ]] || fail "not every run reached the ledger"
jq -e . .agentic/delegate/ledger.jsonl >/dev/null || fail "ledger has malformed records"
[[ -z "$(git status --porcelain --ignored=no -- .agentic/delegate)" ]] || fail "delegation state is not ignored"

echo "smoke-test OK: delegate runner"
