#!/usr/bin/env bash
# Smoke-test the local delegate runner (.agentic/delegate-run.sh) against a
# stub OpenAI-compatible server and a stub Pi harness. Bootstraps the custom
# flavor with --full, fills its runner with a small shell toolchain, and
# drives: init (a draft profile, never written, readable by the runner,
# skipping what exists); qualification (pass, wrong edit, fence, truncation,
# inline reasoning, unreachable endpoint, HTTP error, missing credential, a
# slow first response, a setup change revoking it); discovery, policy, and
# activation; the removed `run` subcommand and old per-file ledger
# entries; and handoffs (scope and test-file audits, phase scoring, review,
# demotion, reset, selection, supervision, pause and resume, detached
# status with --interval and --since, and the same through real Pi when it
# is installed). CI never calls a real model.
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

got=0
bash .agentic/delegate-run.sh handoff placeholder --progress noisy >"$WORK/progress-option.out" 2>&1 || got=$?
[[ "$got" == 2 ]] && grep -q 'unknown progress mode' "$WORK/progress-option.out" ||
  fail "handoff accepted an unknown progress mode"
help="$(bash .agentic/delegate-run.sh --help)"
[[ "$help" == *'qualify <model>'* && "$help" == *'handoff <spec> --allow-commit'* && "$help" == *'Progress is `summary`'* ]] ||
  fail "runner help omitted the qualify, handoff, or progress interface"
[[ "$help" != *'run <packet>'* ]] || fail "runner help still documents the removed run subcommand"
# Single-file delegation was removed: `run` is an unknown subcommand.
got=0
bash .agentic/delegate-run.sh run .agentic/delegate/packets/0001.md --model stub-coder >"$WORK/run.out" 2>&1 || got=$?
[[ "$got" == 2 ]] && grep -q 'unknown subcommand: run' "$WORK/run.out" ||
  { cat "$WORK/run.out" >&2; fail "the removed run subcommand was not refused as unknown"; }

# An existing project owns .gitignore. Updating adds only the new runtime
# entries, preserving custom content and remaining idempotent.
git check-ignore -q .pi/npm/.gitignore || fail "a fresh project does not ignore Pi's package directory"
sed '/^\.agentic\/delegate\/$/d; /^\.pi\/npm\/$/d' .gitignore >"$WORK/ignore.before"
printf '\n# Project-specific rule\nlocal-output/\n' >>"$WORK/ignore.before"
cp "$WORK/ignore.before" .gitignore
bash "$REPO_DIR/custom/bootstrap.sh" --update >/dev/null
git check-ignore -q .agentic/delegate/results/probe.json || fail "--update did not ignore delegation state"
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

git check-ignore -q .agentic/delegate/results/probe.json || fail ".agentic/delegate/ is not gitignored in a fresh project"

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

last_result() { jq -c 'select((.type // "run") == "run")' .agentic/delegate/ledger.jsonl | tail -n 1; }
greet_is() { [[ "$(cat lib/greet.sh)" == "$1" ]]; }
qualified_line() { runner status 2>/dev/null | grep "^$1 (" || true; }
runner() { bash .agentic/delegate-run.sh "$@"; }

# The plumbing file and its expected edit, regenerated from the runner itself.
# Assert the transport contract, not merely the behavior of the stub replies.
assert_raw_system() {
  jq -e '.messages[0].role == "system" and
    (.messages[0].content | contains("raw-file transformation endpoint") and
     contains("first character") and contains("Do not emit Markdown fences"))' "$1" >/dev/null ||
    fail "direct-file request lacks the strict system contract: $1"
}
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
[[ "$(qualified_line stub-coder)" == *": unqualified" ]] || fail "a model was qualified before qualify ran"

EXPECTED="$(plumbing plumbing_expected)"
qualify_with 5 stub-coder "$(plumbing plumbing_file)"
grep -q 'differs from the expected edit' "$WORK/qualify.out" || fail "an unedited plumbing reply passed"
qualify_with 5 stub-coder $'```python\n'"$EXPECTED"$'\n```'
grep -q 'code fence' "$WORK/qualify.out" || fail "a fenced plumbing reply passed"
qualify_with 5 stub-coder $'Here is the file:\n'"$EXPECTED"
grep -q 'differs from the expected edit' "$WORK/qualify.out" || fail "a preamble passed"
qualify_with 5 stub-coder $'<think>unfinished reasoning\n'"$EXPECTED"
grep -q 'empty' "$WORK/qualify.out" || fail "leaked reasoning passed"
qualify_with 5 stub-coder "$EXPECTED" length
grep -q 'cut off' "$WORK/qualify.out" || fail "truncated qualification passed"
qualify_with 5 stub-coder $'<think>\nrename one def\n</think>\n'"$EXPECTED"$'\n\n' length
grep -q 'cut off' "$WORK/qualify.out" || fail "truncated reasoning passed"
qualify_with 0 stub-coder "$EXPECTED"
grep -q "qualified: 'stub-coder'" "$WORK/qualify.out" || fail "qualify did not report a pass"
for request in "$QUEUE/requests/01.json" "$QUEUE/requests/02.json"; do
  assert_raw_system "$request"
  jq -e '[.messages[].role] == ["system", "user"]' "$request" >/dev/null || fail "qualification message order changed"
done
jq -e '.messages[1].content | contains("metric_17") and (contains("```python") | not)' "$QUEUE/requests/02.json" >/dev/null ||
  fail "the qualification source was omitted or fenced"
python3 - "$QUEUE/requests/02.json" "$(plumbing plumbing_file)" <<'PY'
import json
import re
import sys

packet = json.load(open(sys.argv[1]))["messages"][1]["content"].encode()
match = re.search(rb"Source file plumbing.py: the next ([0-9]+) bytes are its literal contents. Read exactly that many bytes.\n", packet)
assert match, "qualification has no byte-counted source"
start = match.end()
assert packet[start:start + int(match[1])] == sys.argv[2].encode() + b"\n", "qualification source bytes changed"
PY
[[ "$(jq -s 'map(select(.result == "pass")) | length' "$WORK/local-models-qualified.jsonl")" == 1 ]] ||
  fail "the qualification record was not written beside the profile"
if grep -q smoke-secret-value "$WORK/local-models-qualified.jsonl"; then fail "credential leaked into qualification"; fi
status_out="$(runner status 2>&1)"
[[ "$status_out" == *"stub-coder (stub-model, setup "*"): qualified"* ]] ||
  { echo "$status_out" >&2; fail "status does not show stub-coder qualified"; }

# The prior harness qualification must go stale without any profile change.
if command -v sha256sum >/dev/null; then hash=(sha256sum); else hash=(shasum -a 256); fi
old_fp="$(printf '%s\n' delegate-run-v1 "http://127.0.0.1:$PORT/v1" stub-model Q8_0 'stub 1' '{"temperature":0.2}' | "${hash[@]}" | cut -c1-16)"
new_fp="$(jq -r 'select(.model == "stub-coder" and .result == "pass") | .fingerprint' "$WORK/local-models-qualified.jsonl" | tail -n 1)"
[[ "$old_fp" != "$new_fp" ]] || fail "raw-file protocol did not bump the harness fingerprint"
[[ "$(jq -r 'select(.model == "stub-coder" and .result == "pass") | .harness' "$WORK/local-models-qualified.jsonl" | tail -n 1)" == delegate-run-v2 ]] ||
  fail "qualification did not record the new harness version"
cp "$WORK/local-models-qualified.jsonl" "$WORK/qualification.new"
jq -c --arg old "$old_fp" 'if .model == "stub-coder" and .result == "pass" then .fingerprint = $old else . end' "$WORK/qualification.new" >"$WORK/local-models-qualified.jsonl"
# The old pass alone cannot qualify the model. Restore the new pass afterward.
[[ "$(qualified_line stub-coder)" == *": unqualified" ]] || fail "old harness qualification remained valid"
cp "$WORK/qualification.new" "$WORK/local-models-qualified.jsonl"

# A setup change (here, the request settings) needs a new qualification.
sed -i.bak 's/"temperature": 0.2/"temperature": 0.3/' "$PROFILE"
[[ "$(qualified_line stub-coder)" == *": unqualified" ]] || fail "a changed setup kept its qualification"
mv "$PROFILE.bak" "$PROFILE"
[[ "$(qualified_line stub-coder)" == *": qualified" ]] || fail "restoring the setup did not restore its qualification"

# --- 1. qualify: credential, unreachable endpoint, HTTP error, slow first reply ---
reset_case
got=0
STUB_TOKEN="" runner qualify stub-coder >"$WORK/qualify.out" 2>&1 || got=$?
[[ "$got" == 2 ]] && grep -q "STUB_TOKEN" "$WORK/qualify.out" || fail "a missing credential variable was not named"
[[ -z "$(ls "$QUEUE/requests")" ]] || fail "a model was called without its credential"
got=0
runner qualify dead-coder >"$WORK/qualify.out" 2>&1 || got=$?
[[ "$got" == 3 ]] || { cat "$WORK/qualify.out" >&2; fail "unreachable endpoint: expected exit 3, got $got"; }
grep -q unreachable "$WORK/qualify.out" || fail "unreachable endpoint was not named"
[[ "$(jq -s 'map(select(.model == "dead-coder")) | length' "$WORK/local-models-qualified.jsonl")" == 0 ]] ||
  fail "an unreachable endpoint was recorded as a qualification result"
reset_case
respond 01 '{}'
echo 500 >"$QUEUE/01.status"
got=0
runner qualify stub-coder >"$WORK/qualify.out" 2>&1 || got=$?
[[ "$got" == 3 ]] && grep -q 'HTTP 500' "$WORK/qualify.out" || { cat "$WORK/qualify.out" >&2; fail "an HTTP error was not an infrastructure failure"; }
[[ "$(qualified_line stub-coder)" == *": qualified" ]] || fail "an infrastructure failure revoked a qualification"
if grep -rqs smoke-secret-value .agentic/delegate "$WORK/local-models-qualified.jsonl"; then fail "credential value leaked into delegation state"; fi

qualify_with 0 slow-coder "$EXPECTED"
reset_case
respond 01 "OK"
echo 4 >"$QUEUE/01.delay"
got=0
runner qualify slow-coder >"$WORK/qualify.out" 2>&1 || got=$?
[[ "$got" == 5 ]] || { cat "$WORK/qualify.out" >&2; fail "a slow first response: expected qualify exit 5, got $got"; }
status_out="$(runner status 2>&1)"
[[ "$status_out" == *"slow-coder (stub-model, setup "*"): unqualified"* ]] ||
  { echo "$status_out" >&2; fail "a timed-out qualify left the model qualified"; }

# --- 2. a ledger with entries from the removed per-file mode ----------------------
# Old per-file runs, their reviews, and resets stay in the ledger as
# history. Status ignores them, and record-review refuses them.
mkdir -p .agentic/delegate
jq -c -n '{type: "run", ts: "2026-10-14T00:00:00Z", run: "0001-lib-greet-sh-20261014T000000Z-1", mode: "manual",
  selection: null, fingerprint: "0000000000000000", qualified: true, packet: ".agentic/delegate/packets/0001-lib-greet-sh.md",
  packet_sha256: "x", target: "lib/greet.sh", bucket: "small", snapshot_sha256: "x", harness: "delegate-run-v2",
  model: {name: "stub-coder", model_id: "stub-model", quant: "Q8_0", runtime: "stub 1", endpoint: "stub", request: ""},
  attempts: [{attempt: 1, outcome: "green", detail: "", seconds: 3}], outcome: "green", reason: "", gate: "partial",
  unverified_steps: ["test"], wall_seconds: 9, review: null}' >>.agentic/delegate/ledger.jsonl
printf '%s\n' '{"type":"review","ts":"2026-10-14T00:01:00Z","run":"0001-lib-greet-sh-20261014T000000Z-1","verdict":"pass","review_changes":{"published_lines":1,"kept_lines":1,"removed_lines":0,"added_lines":0}}' \
  '{"type":"reset","ts":"2026-10-14T00:02:00Z","model":"stub-coder","bucket":"medium"}' >>.agentic/delegate/ledger.jsonl
got=0
runner status >"$WORK/status.out" 2>&1 || got=$?
[[ "$got" == 0 && "$(qualified_line stub-coder)" == *": qualified" ]] ||
  { cat "$WORK/status.out" >&2; fail "an old per-file ledger entry broke status"; }
if grep -qE '^  (small|medium):' "$WORK/status.out"; then fail "status still reports per-file buckets"; fi
got=0
runner record-review 0001-lib-greet-sh-20261014T000000Z-1 pass >"$WORK/review.out" 2>&1 || got=$?
[[ "$got" == 2 ]] && grep -q 'no longer scored' "$WORK/review.out" || { cat "$WORK/review.out" >&2; fail "record-review accepted a per-file run"; }
runner record-review nope pass >/dev/null 2>&1 && fail "record-review accepted an unknown run"
runner reset stub-coder small >/dev/null 2>&1 && fail "reset accepted a removed per-file bucket"

# --- 3. discover, policy, activation ----------------------------------------------------
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

selected() { last_result | jq -r '"\(.selection.phase) \(.selection.chosen)"'; }

qualify_with 0 stub-coder-b "$EXPECTED"
assert_raw_system "$QUEUE/requests/02.json"
jq -e '[.messages[].role] == ["system", "user"] and (has("temperature") | not)' "$QUEUE/requests/02.json" >/dev/null ||
  fail "a profile without request settings broke qualification"

# --- 4. handoff: a whole phase to a stub agent harness in a worktree -------------
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
    busy | slow) ;;
    early-tests | early-outside)
      # Breaks scope with its first tool call, then keeps working for two
      # minutes; the in-flight check must abort it long before that.
      if [[ "$mode" == early-tests ]]; then echo 'exit 0' >tests/test_greet.sh; else echo x >lib/extra.sh; fi
      emit '{"type":"tool_execution_start","toolCallId":"e1","toolName":"write","args":{"path":"early"}}'
      emit '{"type":"tool_execution_end","toolCallId":"e1","toolName":"write","result":{},"isError":false,"durationMs":2}'
      ;;
    compaction)
      emit '{"type":"compaction_start","reason":"threshold"}'
      emit '{"type":"compaction_end","reason":"threshold","result":{"summary":"rules lost"},"aborted":false,"willRetry":false}'
      ;;
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
    slow)
      # One tool call a second, with content that status must never show.
      emit '{"type":"tool_execution_start","toolCallId":"s1","toolName":"bash","args":{"command":"echo RAW-COMMAND-MARKER"}}'
      emit '{"type":"message_update","assistantMessageEvent":{"delta":"RAW-CONTENT-SENTINEL"}}'
      emit '{"type":"tool_execution_end","toolCallId":"s1","toolName":"bash","result":{"content":"RAW-CONTENT-SENTINEL"},"isError":false,"durationMs":5}'
      emit '{"type":"turn_end","message":{"role":"assistant","content":"RAW-CONTENT-SENTINEL"}}'
      ((ticks >= 20)) && complete
      ;;
    early-tests | early-outside)
      emit '{"type":"tool_execution_update","toolCallId":"e2","toolName":"bash","partialResult":{}}'
      ((ticks >= 120)) && complete
      ;;
    compaction)
      # In-scope writes mid-session (plan file, spec note, specs index) must
      # not trip the in-flight check.
      if ((ticks == 1)); then
        greet
        printf '%s\n' '### Working note' >>"$spec"
        echo '# Specs' >docs/specs/README.md
        emit '{"type":"tool_execution_end","toolCallId":"m1","toolName":"write","result":{},"isError":false,"durationMs":2}'
      fi
      ((ticks >= 4)) && complete
      ;;
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
      steer)
        reply "$id" steer '{"disposition":"queued"}'
        steered=1
        echo steer >>"$WORK/harness-steers"
        jq -c .message <<<"$line" >>"$WORK/harness-steer-messages"
        ;;
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
DELEGATE_HANDOFF_HARNESS="$HARNESS" runner status >"$WORK/phase-status" 2>&1
grep -q '^  phase:implement: 0/0 passed, [0-9]* awaiting review' "$WORK/phase-status" ||
  { cat "$WORK/phase-status" >&2; fail "verified handoffs were not pending review"; }
grep -q "record-review $run_id" "$WORK/handoff.out" || fail "the handoff did not print its record-review command"
runner record-review "$run_id" pass >/dev/null 2>&1 || fail "record-review did not accept a handoff run"
DELEGATE_HANDOFF_HARNESS="$HARNESS" runner status >"$WORK/phase-status" 2>&1
grep -q '^  phase:implement: 1/1 passed' "$WORK/phase-status" || { cat "$WORK/phase-status" >&2; fail "a review pass was not scored"; }
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

# A spec or plan defect is not scored against the model; packet-defect is
# accepted as its older name.
handoff 0 good
run_id="$(last_result | jq -r .run)"
runner record-review "$run_id" packet-defect >/dev/null 2>&1 || fail "record-review refused the packet-defect alias"
jq -s -e --arg r "$run_id" 'map(select(.type == "review" and .run == $r)) | last | .verdict == "spec-defect"' \
  .agentic/delegate/ledger.jsonl >/dev/null || fail "packet-defect was not recorded as spec-defect"
DELEGATE_HANDOFF_HARNESS="$HARNESS" runner status >"$WORK/phase-status" 2>&1
grep -q '^  phase:implement: 1/1 passed' "$WORK/phase-status" || { cat "$WORK/phase-status" >&2; fail "a spec-defect review was scored against the model"; }
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
# Nothing selectable: needs_frontier before any worktree or model call.
sed 's/^candidates = .*/candidates = ["dead-coder"]/' "$PROFILE" >"$WORK/dead-only.toml"
reset_case
got=0
hrunner handoff docs/specs/0002-greet.md --allow-commit --foreground --profile "$WORK/dead-only.toml" >"$WORK/handoff.out" 2>&1 || got=$?
[[ "$got" == 10 ]] && grep -q 'no selectable candidate' "$WORK/handoff.out" ||
  { cat "$WORK/handoff.out" >&2; fail "an empty selection did not end needs_frontier with its reason"; }
[[ -z "$(ls "$QUEUE/requests")" && "$(git worktree list | wc -l | tr -d ' ')" == 1 ]] ||
  fail "a model was called or a worktree created with nothing selectable"
handoff 3 crash --progress summary
[[ "$(last_result | jq -r .outcome)" == infrastructure ]] || fail "progress changed the crash ledger outcome"
drop_worktrees
# An unknown model id does not fail Pi's startup; the runner compares the
# model Pi resolved with the profile before prompting.
handoff 3 wrong-model
grep -q "resolved model 'stub/other-model'" "$WORK/handoff.out" || fail "a model mismatch was not reported"
drop_worktrees

# --- 4b. supervision: lease, checkpoint, pause, resume -------------------------
export DELEGATE_PROGRESS_INTERVAL=1 DELEGATE_HANDOFF_ABORT_SECONDS=3 DELEGATE_HANDOFF_GRACE_SECONDS=3

# Steady activity renews a short lease; the run completes without a pause.
rm -f "$WORK/harness-steers"
DELEGATE_HANDOFF_LEASE_SECONDS=2 handoff 0 busy --progress summary
[[ ! -s "$WORK/harness-steers" ]] || fail "an active session was asked to checkpoint"
drop_worktrees

# In-flight scope stop: a session that changes a test file, or a file outside
# the plan, is aborted after that tool call instead of when it settles (two
# minutes later here). The audit still decides: integrity, worktree kept, no
# gate, no commit.
for mode in early-tests early-outside; do
  want=tests/test_greet.sh
  [[ "$mode" == early-outside ]] && want=lib/extra.sh
  started="$(date +%s)"
  handoff 4 "$mode" --progress summary
  (($(date +%s) - started < 30)) || fail "$mode: the scope violation was not stopped early"
  grep -q "early scope stop: .*$want" "$WORK/handoff.out" || { cat "$WORK/handoff.out" >&2; fail "$mode: the early stop did not name $want"; }
  run_id="$(handoff_run_id "$WORK/handoff.out")"
  [[ "$(state_of "$run_id" .state)" == integrity && "$(state_of "$run_id" .exit_status)" == 4 ]] ||
    fail "$mode: the early stop did not end as an integrity outcome"
  [[ "$(state_of "$run_id" '.early_scope_stop.reason // ""')" == *"$want"* ]] || fail "$mode: state.json did not record the early scope stop"
  [[ -d "$WORK/handoffs/$run_id" ]] || fail "$mode: the worktree was not kept"
  [[ -z "$(git -C "$WORK/handoffs/$run_id" log --oneline "$(git rev-parse HEAD)..HEAD")" ]] || fail "$mode: an early stop created a commit"
  [[ ! -e ".agentic/delegate/results/$run_id/gate.log" ]] || fail "$mode: an early stop ran the gate"
  drop_worktrees
done

# After a compaction the runner restates the scope rules once, as a steer;
# the run otherwise proceeds to green.
rm -f "$WORK/harness-steer-messages"
handoff 0 compaction --progress summary
[[ "$(wc -l <"$WORK/harness-steer-messages" | tr -d ' ')" == 1 ]] || fail "a compaction did not produce exactly one guardrail steer"
for want in 'reminder after context compaction' 'lib/greet.sh' 'do not edit, add, or delete any test file' \
  'Do not commit, push, or change branches' 'record the conflict under'; do
  grep -qF "$want" "$WORK/harness-steer-messages" || fail "the guardrail steer lacks: $want"
done
grep -q 'guardrails restated after compaction' "$WORK/handoff.out" || fail "the guardrail steer was not reported"
if grep -q 'early scope stop' "$WORK/handoff.out"; then fail "in-scope writes tripped the in-flight check"; fi
run_id="$(last_result | jq -r .run)"
[[ "$(state_of "$run_id" '.segments[0].guardrail_steers')" == 1 ]] || fail "the guardrail steer was not recorded"
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
# A cursor from the first segment summarizes across the resume.
got=0; hrunner handoff-status "$run_id" --since 0001:0 >"$WORK/status.out" 2>&1 || got=$?
[[ "$got" == 0 ]] && grep -q '^since 0001:0: 1 tool calls (write 1); .*segments started 1$' "$WORK/status.out" &&
  grep -q '^cursor: 0002:[0-9]*$' "$WORK/status.out" || { cat "$WORK/status.out" >&2; fail "--since did not span the resumed segment"; }
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

# Following a slow session: without --interval nothing is printed while
# waiting; with it, bounded liveness lines appear before the call returns.
# Each call prints a cursor, and --since counts only the events after it.
# No raw message, result, or (in the new output) command text reaches status.
echo slow >"$WORK/harness-mode"
hrunner handoff docs/specs/0002-greet.md --allow-commit --model stub-coder >"$WORK/launch.out" 2>&1 || fail "slow launch failed"
grep -q -- '--wait 540 --interval 60' "$WORK/launch.out" || fail "the launch did not suggest --interval"
run_id="$(tail -n 1 "$WORK/launch.out")"
for _ in $(seq 1 100); do [[ -n "$(state_of "$run_id" '.live.pi_pid // empty')" ]] && break; sleep 0.2; done
got=0; hrunner handoff-status "$run_id" --wait 2 >"$WORK/status1.out" 2>&1 || got=$?
[[ "$got" == 12 ]] || { cat "$WORK/status1.out" >&2; fail "slow run: expected status exit 12, got $got"; }
if grep -q '^\[+' "$WORK/status1.out"; then fail "status printed interim lines without --interval"; fi
cursor1="$(sed -n 's/^cursor: //p' "$WORK/status1.out")"
[[ "$cursor1" =~ ^0001:[0-9]+$ ]] || { cat "$WORK/status1.out" >&2; fail "status printed no cursor"; }
got=0; hrunner handoff-status "$run_id" --wait 4 --interval 1 --since "$cursor1" >"$WORK/status2.out" 2>&1 || got=$?
[[ "$got" == 12 ]] || { cat "$WORK/status2.out" >&2; fail "slow run with --interval: expected exit 12, got $got"; }
[[ "$(grep -c '^\[+' "$WORK/status2.out" || true)" -ge 2 ]] || { cat "$WORK/status2.out" >&2; fail "--interval printed fewer than two interim lines"; }
grep '^\[+' "$WORK/status2.out" | grep -q 'running: runner alive, pi alive; last activity [0-9]*s ago.*since previous: [0-9]* tool calls' ||
  { cat "$WORK/status2.out" >&2; fail "an interim line lacks liveness or counts"; }
grep '^\[+' "$WORK/status2.out" | awk 'length($0) > 200 { bad = 1 } END { exit bad }' || fail "an interim line exceeded 200 characters"
grep -q "^since $cursor1: " "$WORK/status2.out" || fail "--since printed no summary"
cursor2="$(sed -n 's/^cursor: //p' "$WORK/status2.out")"
got=0; hrunner handoff-status "$run_id" --wait 120 --interval 1 --since "$cursor2" >"$WORK/status3.out" 2>&1 || got=$?
[[ "$got" == 0 ]] && grep -q '^state: green' "$WORK/status3.out" || { cat "$WORK/status3.out" >&2; fail "the slow run did not finish green"; }
events=".agentic/delegate/results/$run_id/segments/0001/events.jsonl"
total="$(grep -c '"type":"tool_execution_end"' "$events" || true)"
before="$(head -c "${cursor2#*:}" "$events" | grep -c '"type":"tool_execution_end"' || true)"
((before > 0 && total > before)) || fail "the cursor did not split the slow run's events ($before of $total)"
grep -q "^since $cursor2: $((total - before)) tool calls" "$WORK/status3.out" ||
  { cat "$WORK/status3.out" >&2; fail "--since did not count only the $((total - before)) newer tool calls"; }
if grep -q 'RAW-CONTENT-SENTINEL' "$WORK"/status[123].out; then fail "status exposed raw message or tool content"; fi
if grep -q 'RAW-COMMAND-MARKER' "$WORK"/status[23].out; then fail "interim or --since output exposed a tool command"; fi
# --interval is validated like --wait; a cursor that does not fit the run is
# a note, never a change to the exit status.
for bad in 0 -1 x; do
  got=0; hrunner handoff-status "$run_id" --wait 1 --interval "$bad" >"$WORK/status.out" 2>&1 || got=$?
  [[ "$got" == 2 ]] || fail "--interval $bad was not refused"
done
for bad in garbage 0009:5 0001:999999999; do
  got=0; hrunner handoff-status "$run_id" --since "$bad" >"$WORK/status.out" 2>&1 || got=$?
  [[ "$got" == 0 ]] && grep -q 'does not match this run' "$WORK/status.out" && grep -q '^cursor: 0001:' "$WORK/status.out" ||
    { cat "$WORK/status.out" >&2; fail "--since $bad was not handled as a note"; }
done
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

# --- 4c. the same through real Pi RPC (loopback stub, no real model) -----------
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
  jq -e '.model == "stub-model" and .temperature == 0.2 and
    ([.messages[].content | strings] | all(contains("raw-file transformation endpoint") | not))' \
    "$QUEUE/requests/01.json" >/dev/null || fail "Pi used the wrong model/settings or inherited the raw-file contract"
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
  jq -e '([.messages[].content | strings] | all(contains("raw-file transformation endpoint") | not))' \
    "$QUEUE/requests/01.json" >/dev/null || fail "Pi handoff inherited the raw-file contract"
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

# --- 5. lock and ledger --------------------------------------------------------
[[ ! -e .agentic/delegate/lock ]] || fail "lock was left behind"
[[ "$(wc -l <.agentic/delegate/ledger.jsonl | tr -d ' ')" -ge 9 ]] || fail "not every run reached the ledger"
jq -e . .agentic/delegate/ledger.jsonl >/dev/null || fail "ledger has malformed records"
[[ -z "$(git status --porcelain --ignored=no -- .agentic/delegate)" ]] || fail "delegation state is not ignored"

echo "smoke-test OK: delegate runner"
