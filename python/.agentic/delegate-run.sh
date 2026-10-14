#!/usr/bin/env bash
# Local delegate runner — sends one /delegate packet to a local model,
# verifies the returned file in a scratch copy of the workspace, and
# publishes it only when it passes. The model gets text and returns text;
# it has no repository access and no tools.
#
# A candidate passes when the packet's focused tests pass and every gate
# step (lint, format-check, typecheck, test) that was green before the run
# is still green. Steps already red before the run — usually other plan
# files that have not landed — are reported as unverified ("partial"), not
# held against the candidate; the full gate must go green once they land.
#
# Usage: .agentic/delegate-run.sh run <packet> --model <name> [--profile <path>]
#
#   run        Send <packet> to the named model from the machine profile.
#              Up to three calls; each attempt starts from the same clean
#              scratch snapshot. Retries carry the previous candidate and
#              bounded failure output.
#
# This version is the manual slice of docs/local-delegate-runner.md in the
# agentic-scaffold repository: the human names the model, so there is no
# admission check, discovery, or selection yet. Every run is labelled
# "manual" in its result and ledger record, and manual runs never count as
# calibration evidence.
#
# Profile: ${AGENTIC_DELEGATE_PROFILE:-${XDG_CONFIG_HOME:-~/.config}/agentic/local-models.toml}
# (outside the repository; it names private endpoints). Example:
#
#   [[endpoint]]
#   name = "lan-gateway"
#   base_url = "http://<host>:<port>/v1"
#   credential_env = "LOCAL_MODEL_TOKEN"   # optional; variable NAME, never the value
#
#   [[model]]
#   name = "coder-a"
#   endpoint = "lan-gateway"
#   model_id = "<id the server reports>"
#   quant = "Q8_K"
#   runtime = "llama.cpp b5xxx"
#   context = 131072
#   timeout_seconds = 900                  # optional; whole-call limit
#   request = '{"temperature": 0.6}'       # optional; JSON merged into each request
#
# Packet: the file /delegate writes under .agentic/delegate/packets/, with
# a front-matter header naming `targets: [<path>]` and
# `test_targets: [<path> ...]`. The header is not sent to the model.
#
# Exit status:
#   0   green candidate published to the working tree (uncommitted)
#   10  needs_frontier: three attempts spent; implement with the frontier model
#   2   refused: usage, profile, packet, or workspace preconditions
#   3   infrastructure failure: endpoint, transport, or verifier
#   4   integrity stop: unexpected writes, or the workspace changed mid-run
#
# Requires: bash, git, curl, jq (1.6+), tar, and sha256sum or shasum.

set -uo pipefail

HARNESS_VERSION="delegate-run-v1-manual"
MAX_ATTEMPTS=3
DIAG_LINES=120
DIAG_BYTES=12000

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 3
DELEGATE_DIR="$ROOT/.agentic/delegate"
TOOLCHAIN=.agentic/toolchain.sh

say() { printf 'delegate-run: %s\n' "$*" >&2; }

usage() {
  sed -n '2,55p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ---- exit paths --------------------------------------------------------------
# Every non-usage exit after the lock is taken goes through finish(), which
# writes the result file and the ledger record before exiting.

refuse() { say "refused: $*"; OUTCOME=refused; REASON="$*"; finish 2; }
infra() { say "infrastructure failure: $*"; OUTCOME=infrastructure; REASON="$*"; finish 3; }
integrity() { say "integrity stop: $*"; OUTCOME=integrity; REASON="$*"; finish 4; }

# ---- small helpers -------------------------------------------------------------

if command -v sha256sum >/dev/null 2>&1; then
  SHA=(sha256sum)
else
  SHA=(shasum -a 256)
fi

sha_file() { "${SHA[@]}" <"$1" | cut -d' ' -f1; }

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Bounded tail of a log, for retry feedback and escalation diagnostics.
bounded_tail() { tail -n "$DIAG_LINES" "$1" | tail -c "$DIAG_BYTES"; }

# Run a verifier command in the scratch tree without the endpoint credential.
verify_cmd() {
  if [[ -n "${CRED_ENV:-}" ]]; then
    (cd "$TREE" && env -u "$CRED_ENV" "$@")
  else
    (cd "$TREE" && "$@")
  fi
}

# ---- profile (restricted TOML: [[table]] arrays of key = value) -----------------

# Prints one line per key: table<TAB>index<TAB>key<TAB>value. Strings are
# unquoted; arrays and anything else are passed through raw.
profile_entries() {
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function value(v,   out, i, c) {
      v = trim(v)
      if (substr(v, 1, 1) == "\"") {
        out = ""
        for (i = 2; i <= length(v); i++) {
          c = substr(v, i, 1)
          if (c == "\\") { i++; out = out substr(v, i, 1); continue }
          if (c == "\"") return out
          out = out c
        }
        return out
      }
      if (substr(v, 1, 1) == "\047") {
        v = substr(v, 2)
        return substr(v, 1, index(v, "\047") - 1)
      }
      sub(/[ \t]+#.*$/, "", v)
      return v
    }
    /^[ \t]*(#|$)/ { next }
    /^[ \t]*\[\[[A-Za-z_]+\]\]/ {
      t = $0; sub(/^[ \t]*\[\[/, "", t); sub(/\]\].*$/, "", t)
      n[t]++; cur = t; next
    }
    /^[ \t]*\[/ { cur = ""; next }
    cur != "" && index($0, "=") {
      k = trim(substr($0, 1, index($0, "=") - 1))
      printf "%s\t%d\t%s\t%s\n", cur, n[cur], k, value(substr($0, index($0, "=") + 1))
    }
  ' "$1"
}

# profile_get <table> <name> <key>: the key of the entry whose name matches.
profile_get() {
  awk -F'\t' -v t="$1" -v name="$2" -v key="$3" '
    $1 == t && $3 == "name" && $4 == name { hit[$2] = 1 }
    $1 == t { rows[NR] = $0; idx[NR] = $2; keys[NR] = $3; vals[NR] = $4 }
    END {
      for (i = 1; i <= NR; i++) if ((idx[i] in hit) && keys[i] == key) { print vals[i]; exit }
    }
  ' "$PROFILE_TSV"
}

# ---- packet header (restricted front matter: key: value | key: [a, b]) ---------

# Prints key<TAB>item, one line per list item or scalar.
packet_header() {
  awk '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, ":") {
      k = substr($0, 1, index($0, ":") - 1)
      v = substr($0, index($0, ":") + 1)
      sub(/[ \t]+#.*$/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (v ~ /^\[.*\]$/) {
        v = substr(v, 2, length(v) - 2)
        n = split(v, items, ",")
        for (i = 1; i <= n; i++) {
          item = items[i]; gsub(/^[ \t"\047]+|[ \t"\047]+$/, "", item)
          if (item != "") printf "%s\t%s\n", k, item
        }
      } else {
        gsub(/^["\047]|["\047]$/, "", v)
        printf "%s\t%s\n", k, v
      }
    }
  ' "$1"
}

packet_body() {
  awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { fm = 0; next } !fm' "$1"
}

# ---- workspace listing and manifests ------------------------------------------

# NUL-separated tracked plus unignored untracked files, minus delegation state
# and credential-shaped files that must never be copied.
list_files() {
  git -C "$1" ls-files -z -c -o --exclude-standard | tr '\0' '\n' |
    awk '!/^\.agentic\/delegate\//' |
    awk '!/(^|\/)(id_rsa[^\/]*|id_ed25519[^\/]*|[^\/]*\.pem|[^\/]*\.key)$/' |
    awk '!/(^|\/)\.env(\..*)?$/ || /\.example$/' |
    LC_ALL=C sort -u | tr '\n' '\0'
}

# manifest <dir> <nul-list> : sorted "path<TAB>kind<TAB>detail" lines.
manifest() {
  local dir="$1" list="$2" f
  (
    cd "$dir" || exit 1
    while IFS= read -r -d '' f; do
      if [[ -L "$f" ]]; then
        printf '%s\tlink\t%s\n' "$f" "$(readlink "$f")"
      elif [[ -f "$f" ]]; then
        if [[ -x "$f" ]]; then
          printf '%s\tfile-x\t%s\n' "$f" "$(sha_file "$f")"
        else
          printf '%s\tfile\t%s\n' "$f" "$(sha_file "$f")"
        fi
      elif [[ ! -e "$f" ]]; then
        printf '%s\tmissing\t-\n' "$f"
      fi
    done <"$list"
  ) | LC_ALL=C sort
}

# Paths whose manifest lines differ between two manifests.
changed_paths() {
  LC_ALL=C comm -3 "$1" "$2" | sed 's/^\t//' | cut -f1 | LC_ALL=C sort -u
}

# Refuse a path whose existing components are symlinks (escape from the tree).
no_symlink_path() {
  local base="$1" rel="$2" acc=""
  local IFS=/
  local part
  for part in $rel; do
    acc="${acc:+$acc/}$part"
    [[ -L "$base/$acc" ]] && return 1
  done
  return 0
}

# ---- gate steps -----------------------------------------------------------------

GATE_STEPS="lint format-check typecheck test"

# run_steps <label> : runs each gate step in the scratch tree, writing
# "<step> <status>" lines to $STATE/<label>.steps and one log per step.
run_steps() {
  local label="$1" step status
  : >"$STATE/$label.steps"
  for step in $GATE_STEPS; do
    status=0
    verify_cmd bash "$TOOLCHAIN" "$step" >"$STATE/$label.$step.log" 2>&1 || status=$?
    printf '%s %s\n' "$step" "$status" >>"$STATE/$label.steps"
  done
}

step_status() { awk -v s="$2" '$1 == s { print $2 }' "$STATE/$1.steps"; }

# ---- model call ---------------------------------------------------------------

# call_model <attempt> : writes $STATE/attempt-N.response.json, returns 0 on a
# usable HTTP response; infrastructure failures exit through infra().
call_model() {
  local n="$1"
  local req="$STATE/attempt-$n.request.json" resp="$STATE/attempt-$n.response.json"
  local extra="${REQUEST_JSON:-}"
  [[ -n "$extra" ]] || extra='{}'

  if [[ "$n" == 1 ]]; then
    jq -n --arg model "$MODEL_ID" --rawfile packet "$STATE/packet-body.md" --argjson extra "$extra" \
      '{model: $model, stream: false, messages: [{role: "user", content: $packet}]} + $extra' >"$req"
  else
    jq -n --arg model "$MODEL_ID" --rawfile packet "$STATE/packet-body.md" \
      --rawfile previous "$STATE/previous-candidate" --rawfile feedback "$STATE/feedback.md" \
      --argjson extra "$extra" \
      '{model: $model, stream: false, messages: [
         {role: "user", content: $packet},
         {role: "assistant", content: $previous},
         {role: "user", content: $feedback}]} + $extra' >"$req"
  fi || infra "could not build the request (is 'request' in the profile valid JSON?)"

  local code curl_status=0
  if [[ -n "${CRED_ENV:-}" ]]; then
    # The header comes through a file descriptor so the credential never
    # appears in a process argument list.
    code="$(curl -sS --connect-timeout 10 --max-time "$TIMEOUT" \
      -H 'Content-Type: application/json' \
      -H @<(printf 'Authorization: Bearer %s\n' "${!CRED_ENV}") \
      --data-binary @"$req" -o "$resp" -w '%{http_code}' \
      "$BASE_URL/chat/completions" 2>"$STATE/attempt-$n.curl.err")" || curl_status=$?
  else
    code="$(curl -sS --connect-timeout 10 --max-time "$TIMEOUT" \
      -H 'Content-Type: application/json' \
      --data-binary @"$req" -o "$resp" -w '%{http_code}' \
      "$BASE_URL/chat/completions" 2>"$STATE/attempt-$n.curl.err")" || curl_status=$?
  fi
  if [[ "$curl_status" != 0 ]]; then
    infra "endpoint '$ENDPOINT_NAME' unreachable or timed out (curl exit $curl_status: $(head -c 300 "$STATE/attempt-$n.curl.err"))"
  fi
  if [[ "$code" != 2* ]]; then
    infra "endpoint '$ENDPOINT_NAME' returned HTTP $code: $(head -c 300 "$resp" 2>/dev/null)"
  fi
  jq -e 'type == "object"' "$resp" >/dev/null 2>&1 ||
    infra "endpoint '$ENDPOINT_NAME' returned malformed JSON"
}

# extract_candidate <attempt> : writes $STATE/candidate; on a format problem
# prints the reason and returns 1 (the attempt is spent, with feedback).
extract_candidate() {
  local n="$1"
  local resp="$STATE/attempt-$n.response.json" cand="$STATE/candidate" finish first
  finish="$(jq -r '.choices[0].finish_reason // "missing"' "$resp")"
  jq -j '.choices[0].message.content // "" | if type == "string" then . else "" end' "$resp" >"$cand"

  if [[ "$finish" == length ]]; then
    echo "The response was cut off (finish_reason=length). Return the complete file; it must fit in one response."
    return 1
  fi
  if [[ "$finish" != stop ]]; then
    echo "The response did not finish normally (finish_reason=$finish)."
    return 1
  fi

  # Reasoning that the server left inline is transport, not the candidate.
  first="$(grep -m1 -v '^[[:space:]]*$' "$cand" || true)"
  if [[ "$first" == "<think>"* ]]; then
    awk 'f { print; next } /<\/think>/ { f = 1; sub(/.*<\/think>/, ""); if (length($0)) print }' \
      "$cand" | awk 'NF || p { p = 1; print }' >"$cand.tmp" && mv "$cand.tmp" "$cand"
    first="$(grep -m1 -v '^[[:space:]]*$' "$cand" || true)"
  fi

  if [[ ! -s "$cand" || -z "$first" ]]; then
    echo "The response was empty. Return the complete contents of the file."
    return 1
  fi
  if [[ "$first" == '```'* ]]; then
    echo "The response was wrapped in a markdown code fence. Return the file contents only, with no fence."
    return 1
  fi
  # Files end with a newline; formatters would flag the omission otherwise.
  if [[ "$(tail -c1 "$cand" | wc -l | tr -d ' ')" == 0 ]]; then
    printf '\n' >>"$cand"
  fi
  return 0
}

# ---- result and ledger ----------------------------------------------------------

ATTEMPTS_JSON='[]'
GATE_LEVEL=""
UNVERIFIED=""
OUTCOME=""
REASON=""
LOCKED=0
STATE=""
WORK=""

record_attempt() {
  ATTEMPTS_JSON="$(jq -c --argjson n "$1" --arg outcome "$2" --arg detail "$3" --argjson seconds "$4" \
    '. + [{attempt: $n, outcome: $outcome, detail: $detail, seconds: $seconds}]' <<<"$ATTEMPTS_JSON")"
}

finish() {
  local status="$1" result_dir
  if [[ -n "${RUN_ID:-}" ]]; then
    result_dir="$DELEGATE_DIR/results/$RUN_ID"
    mkdir -p "$result_dir"
    [[ -n "$STATE" && -f "$STATE/last-diagnostics.txt" ]] &&
      cp "$STATE/last-diagnostics.txt" "$result_dir/last-diagnostics.txt"
    jq -n \
      --arg ts "$(now_utc)" --arg run "$RUN_ID" --arg packet "${PACKET_REL:-}" \
      --arg packet_sha "${PACKET_SHA:-}" --arg outcome "$OUTCOME" --arg reason "$REASON" \
      --arg harness "$HARNESS_VERSION" --arg model "${MODEL_NAME:-}" --arg model_id "${MODEL_ID:-}" \
      --arg quant "${QUANT:-}" --arg runtime "${RUNTIME:-}" --arg endpoint "${ENDPOINT_NAME:-}" \
      --arg request "${REQUEST_JSON:-}" --arg target "${TARGET:-}" --arg bucket "${BUCKET:-}" \
      --arg snapshot "${SNAPSHOT_SHA:-}" --argjson attempts "$ATTEMPTS_JSON" \
      --arg gate "${GATE_LEVEL:-}" --arg unverified "${UNVERIFIED:-}" \
      '{ts: $ts, run: $run, mode: "manual", admission: "none", packet: $packet,
        packet_sha256: $packet_sha, target: $target, bucket: $bucket,
        snapshot_sha256: $snapshot, harness: $harness,
        model: {name: $model, model_id: $model_id, quant: $quant, runtime: $runtime,
                endpoint: $endpoint, request: $request},
        attempts: $attempts, outcome: $outcome, reason: $reason,
        gate: $gate, unverified_steps: ($unverified | split(" ") | map(select(. != ""))),
        review: null}' \
      >"$result_dir/result.json"
    jq -c . "$result_dir/result.json" >>"$DELEGATE_DIR/ledger.jsonl"
    say "result: ${result_dir#"$ROOT"/}/result.json"
  fi
  exit "$status"
}

cleanup() {
  [[ -n "$WORK" && "${DELEGATE_KEEP_SCRATCH:-0}" != 1 ]] && rm -rf "$WORK"
  [[ "$LOCKED" == 1 ]] && rmdir "$DELEGATE_DIR/lock" 2>/dev/null
  return 0
}

# ---- run ----------------------------------------------------------------------

cmd_run() {
  local packet="" profile="${AGENTIC_DELEGATE_PROFILE:-${XDG_CONFIG_HOME:-$HOME/.config}/agentic/local-models.toml}"
  MODEL_NAME=""
  while (($#)); do
    case "$1" in
      --model) MODEL_NAME="${2:-}"; shift 2 ;;
      --profile) profile="${2:-}"; shift 2 ;;
      -h | --help) usage; exit 0 ;;
      -*) say "unknown option: $1"; exit 2 ;;
      *) [[ -z "$packet" ]] || { say "one packet per run"; exit 2; }; packet="$1"; shift ;;
    esac
  done
  [[ -n "$packet" ]] || { say "usage: delegate-run.sh run <packet> --model <name>"; exit 2; }
  [[ -n "$MODEL_NAME" ]] || {
    say "--model is required: this version runs only a model the human names (no admission or selection yet)"
    exit 2
  }

  local dep
  for dep in git curl jq tar awk; do
    command -v "$dep" >/dev/null 2>&1 || { say "missing dependency: $dep"; exit 2; }
  done
  git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { say "not a git work tree: $ROOT"; exit 2; }

  mkdir -p "$DELEGATE_DIR/results"
  if ! mkdir "$DELEGATE_DIR/lock" 2>/dev/null; then
    say "another run holds $DELEGATE_DIR/lock; remove it if no run is active"
    exit 2
  fi
  LOCKED=1
  trap cleanup EXIT

  [[ -f "$packet" ]] || { say "packet not found: $packet"; exit 2; }
  local packet_abs
  packet_abs="$(cd "$(dirname "$packet")" && pwd)/$(basename "$packet")"
  PACKET_REL="${packet_abs#"$ROOT"/}"
  PACKET_SHA="$(sha_file "$packet_abs")"
  RUN_ID="$(basename "$packet_abs" .md)-$(date -u +%Y%m%dT%H%M%SZ)"

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/delegate-run.XXXXXX")" || infra "could not create scratch directory"
  STATE="$WORK/state"
  TREE="$WORK/tree"
  mkdir -p "$STATE" "$TREE"

  # -- profile
  [[ -f "$profile" ]] || refuse "profile not found: $profile"
  PROFILE_TSV="$STATE/profile.tsv"
  profile_entries "$profile" >"$PROFILE_TSV"
  MODEL_ID="$(profile_get model "$MODEL_NAME" model_id)"
  [[ -n "$MODEL_ID" ]] || refuse "no [[model]] named '$MODEL_NAME' with a model_id in $profile"
  ENDPOINT_NAME="$(profile_get model "$MODEL_NAME" endpoint)"
  QUANT="$(profile_get model "$MODEL_NAME" quant)"
  RUNTIME="$(profile_get model "$MODEL_NAME" runtime)"
  REQUEST_JSON="$(profile_get model "$MODEL_NAME" request)"
  TIMEOUT="$(profile_get model "$MODEL_NAME" timeout_seconds)"
  TIMEOUT="${TIMEOUT:-900}"
  [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || refuse "timeout_seconds must be a whole number of seconds"
  [[ -z "$REQUEST_JSON" ]] || jq -e 'type == "object"' <<<"$REQUEST_JSON" >/dev/null 2>&1 ||
    refuse "model '$MODEL_NAME': request must be a JSON object in a literal string, e.g. request = '{\"temperature\": 0.6}'"
  [[ -n "$ENDPOINT_NAME" ]] || refuse "model '$MODEL_NAME' names no endpoint"
  BASE_URL="$(profile_get endpoint "$ENDPOINT_NAME" base_url)"
  BASE_URL="${BASE_URL%/}"
  [[ "$BASE_URL" =~ ^https?://[^[:space:]]+$ ]] || refuse "endpoint '$ENDPOINT_NAME' needs an http(s) base_url"
  CRED_ENV="$(profile_get endpoint "$ENDPOINT_NAME" credential_env)"
  if [[ -n "$CRED_ENV" ]]; then
    [[ "$CRED_ENV" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || refuse "credential_env must be an environment variable name"
    [[ -n "${!CRED_ENV:-}" ]] || refuse "credential_env '$CRED_ENV' is not set in this environment"
  fi

  # -- packet
  packet_header "$packet_abs" >"$STATE/header.tsv"
  packet_body "$packet_abs" >"$STATE/packet-body.md"
  local targets tests
  targets="$(awk -F'\t' '$1 == "targets" { print $2 }' "$STATE/header.tsv")"
  tests="$(awk -F'\t' '$1 == "test_targets" { print $2 }' "$STATE/header.tsv")"
  BUCKET="$(awk -F'\t' '$1 == "bucket" { print $2; exit }' "$STATE/header.tsv")"
  [[ -n "$targets" ]] || refuse "packet has no front-matter 'targets' (re-run /delegate to regenerate it)"
  [[ "$(printf '%s\n' "$targets" | wc -l | tr -d ' ')" == 1 ]] ||
    refuse "multi-file (coupled) packets are not supported yet; delegate one file per packet"
  [[ -n "$tests" ]] || refuse "packet has no front-matter 'test_targets'"
  [[ -s "$STATE/packet-body.md" ]] || refuse "packet body is empty"
  TARGET="$targets"
  case "$TARGET" in
    /* | *..* | .agentic/* | .git/* | .github/* | .claude/* | .codex/* | .pi/* | .agents/*)
      refuse "target '$TARGET' is outside the delegable source tree" ;;
  esac
  local t
  while IFS= read -r t; do
    [[ "$t" == "$TARGET" ]] && refuse "target '$TARGET' is also a test target"
    case "$t" in /* | *..*) refuse "unsafe test target '$t'" ;; esac
  done <<<"$tests"

  # -- snapshot the workspace (tracked + unignored untracked, minus delegation state)
  list_files "$ROOT" >"$STATE/files.nul"
  manifest "$ROOT" "$STATE/files.nul" >"$STATE/workspace.manifest"
  SNAPSHOT_SHA="$(sha_file "$STATE/workspace.manifest")"
  (cd "$ROOT" && tar -cf - --null -T "$STATE/files.nul") | (cd "$TREE" && tar -xf -) ||
    infra "could not copy the workspace snapshot"
  git -C "$TREE" init -q || infra "could not initialize scratch listing"

  no_symlink_path "$TREE" "$TARGET" || integrity "target path '$TARGET' passes through a symlink"
  [[ -f "$TREE/$TOOLCHAIN" ]] || refuse "no $TOOLCHAIN in the workspace"
  bash -n "$TREE/$TOOLCHAIN" || infra "$TOOLCHAIN does not parse"

  local ready=0
  verify_cmd bash "$TOOLCHAIN" ready >"$STATE/ready.log" 2>&1 || ready=$?
  case "$ready" in
    0) ;;
    3) refuse "the gate is deliberately unconfigured ($TOOLCHAIN ready exited 3); a model cannot be verified" ;;
    *) infra "the gate is broken ($TOOLCHAIN ready exited $ready): $(bounded_tail "$STATE/ready.log")" ;;
  esac

  local src_dirs inside=0 d
  src_dirs="$(verify_cmd bash "$TOOLCHAIN" source-dirs 2>/dev/null)"
  for d in $src_dirs; do
    [[ "$TARGET" == "${d%/}/"* ]] && inside=1
  done
  [[ "$inside" == 1 ]] || refuse "target '$TARGET' is not under the gate's source dirs ($src_dirs)"

  say "provisioning scratch copy"
  verify_cmd bash "$TOOLCHAIN" install >"$STATE/install.log" 2>&1 ||
    infra "toolchain install failed in scratch: $(bounded_tail "$STATE/install.log")"
  # Match the edit hook, which formats after every frontier edit.
  verify_cmd bash "$TOOLCHAIN" format >"$STATE/format.log" 2>&1 ||
    infra "toolchain format failed on the baseline: $(bounded_tail "$STATE/format.log")"
  list_files "$TREE" >"$STATE/scratch-files.nul"
  manifest "$TREE" "$STATE/scratch-files.nul" >"$STATE/baseline.manifest"

  # -- the intended red baseline
  local test_args=() status=0
  while IFS= read -r t; do test_args+=("$t"); done <<<"$tests"
  verify_cmd bash "$TOOLCHAIN" test "${test_args[@]}" >"$STATE/baseline-test.log" 2>&1 || status=$?
  [[ "$status" != 0 ]] || refuse "the target's tests already pass; there is nothing to delegate"
  # Steps red before the run (other plan files not landed yet) cannot be
  # held against the candidate; steps green before the run must stay green.
  run_steps baseline

  local baseline_exists=0
  if [[ -f "$TREE/$TARGET" ]]; then
    baseline_exists=1
    cp -p "$TREE/$TARGET" "$STATE/target.baseline"
  fi

  # -- attempts
  local n started elapsed reason green=0
  for ((n = 1; n <= MAX_ATTEMPTS; n++)); do
    started="$(date +%s)"
    if [[ "$baseline_exists" == 1 ]]; then
      cat "$STATE/target.baseline" >"$TREE/$TARGET"
    else
      rm -f "$TREE/$TARGET"
    fi

    say "attempt $n/$MAX_ATTEMPTS: calling '$MODEL_NAME'"
    call_model "$n"
    if ! reason="$(extract_candidate "$n")"; then
      elapsed=$(($(date +%s) - started))
      printf '%s\n' "$reason" >"$STATE/last-diagnostics.txt"
      record_attempt "$n" format "$reason" "$elapsed"
      cp "$STATE/candidate" "$STATE/previous-candidate"
      printf 'Your file was rejected before verification.\n\n%s\n\nReturn the complete final contents of `%s`, and nothing else. No diff, no patch, no commentary, no markdown fence around the file.\n' \
        "$reason" "$TARGET" >"$STATE/feedback.md"
      say "attempt $n rejected: $reason"
      continue
    fi

    mkdir -p "$(dirname "$TREE/$TARGET")"
    no_symlink_path "$TREE" "$TARGET" || integrity "target path '$TARGET' became a symlink"
    if [[ "$baseline_exists" == 1 ]]; then
      cat "$STATE/candidate" >"$TREE/$TARGET"
    else
      cp "$STATE/candidate" "$TREE/$TARGET"
    fi
    cp "$STATE/candidate" "$STATE/previous-candidate"

    status=0
    verify_cmd bash "$TOOLCHAIN" format >"$STATE/attempt-$n.format.log" 2>&1 || status=$?
    local focused=0 regressed="" still_red="" step
    if [[ "$status" == 0 ]]; then
      verify_cmd bash "$TOOLCHAIN" test "${test_args[@]}" >"$STATE/attempt-$n.focused.log" 2>&1 || focused=$?
      run_steps "attempt-$n"
      for step in $GATE_STEPS; do
        if [[ "$(step_status "attempt-$n" "$step")" != 0 ]]; then
          if [[ "$(step_status baseline "$step")" == 0 ]]; then
            regressed="${regressed:+$regressed }$step"
          else
            still_red="${still_red:+$still_red }$step"
          fi
        fi
      done
    fi

    # Post-execution audit: only the target may differ from the baseline.
    list_files "$TREE" >"$STATE/after-files.nul"
    manifest "$TREE" "$STATE/after-files.nul" >"$STATE/after.manifest"
    local unexpected
    unexpected="$(changed_paths "$STATE/baseline.manifest" "$STATE/after.manifest" | grep -v -x -F "$TARGET" || true)"
    elapsed=$(($(date +%s) - started))
    if [[ -n "$unexpected" ]]; then
      record_attempt "$n" integrity "unexpected changes: $(printf '%s' "$unexpected" | tr '\n' ' ')" "$elapsed"
      integrity "the candidate's gate run changed files other than the target: $(printf '%s' "$unexpected" | tr '\n' ' ')"
    fi

    local why=""
    if [[ "$status" != 0 ]]; then
      why="the formatter failed on the file"
      bounded_tail "$STATE/attempt-$n.format.log" >"$STATE/last-diagnostics.txt"
    elif [[ "$focused" != 0 ]]; then
      why="the target's tests failed"
      bounded_tail "$STATE/attempt-$n.focused.log" >"$STATE/last-diagnostics.txt"
    elif [[ -n "$regressed" ]]; then
      why="gate steps that passed before the change now fail: $regressed"
      : >"$STATE/last-diagnostics.txt"
      for step in $regressed; do
        printf '== %s ==\n' "$step" >>"$STATE/last-diagnostics.txt"
        bounded_tail "$STATE/attempt-$n.$step.log" >>"$STATE/last-diagnostics.txt"
      done
    fi

    if [[ -z "$why" ]]; then
      UNVERIFIED="$still_red"
      GATE_LEVEL=full
      [[ -n "$still_red" ]] && GATE_LEVEL=partial
      record_attempt "$n" green "${still_red:+red before the run and still red: $still_red}" "$elapsed"
      green=1
      break
    fi
    record_attempt "$n" red "$why" "$elapsed"
    {
      printf 'Your file did not pass verification: %s.\n\n' "$why"
      printf 'Verification output (last lines):\n\n'
      cat "$STATE/last-diagnostics.txt"
      printf '\nReturn the complete final contents of `%s`, and nothing else. No diff, no patch, no commentary, no markdown fence around the file.\n' "$TARGET"
    } >"$STATE/feedback.md"
    say "attempt $n red: $why"
  done

  if [[ "$green" != 1 ]]; then
    OUTCOME=needs_frontier
    REASON="$MAX_ATTEMPTS attempts spent without passing verification"
    say "needs_frontier: $REASON. Implement $TARGET with the frontier model."
    say "packet: $PACKET_REL"
    finish 10
  fi

  # -- publish, only if the workspace has not moved under the run
  list_files "$ROOT" >"$STATE/files-now.nul"
  manifest "$ROOT" "$STATE/files-now.nul" >"$STATE/workspace-now.manifest"
  if ! cmp -s "$STATE/workspace.manifest" "$STATE/workspace-now.manifest"; then
    local kept="$DELEGATE_DIR/results/$RUN_ID/candidate"
    mkdir -p "$(dirname "$kept")"
    cp "$TREE/$TARGET" "$kept"
    integrity "the workspace changed during the run ($(changed_paths "$STATE/workspace.manifest" "$STATE/workspace-now.manifest" | tr '\n' ' ')); green candidate kept at ${kept#"$ROOT"/}, re-run against the current tree"
  fi
  no_symlink_path "$ROOT" "$TARGET" || integrity "workspace target path '$TARGET' passes through a symlink"
  mkdir -p "$(dirname "$ROOT/$TARGET")"
  local tmp="$ROOT/$TARGET.delegate-run.$$"
  cp "$TREE/$TARGET" "$tmp" || infra "could not stage the candidate in the workspace"
  [[ -x "$ROOT/$TARGET" ]] && chmod +x "$tmp"
  mv -f "$tmp" "$ROOT/$TARGET" || infra "could not publish the candidate"

  OUTCOME=green
  REASON=""
  say "green: published $TARGET (uncommitted) after attempt $n."
  if [[ "$GATE_LEVEL" == partial ]]; then
    say "partial gate: '$UNVERIFIED' were red before the run and still are (other plan files not landed?)."
    say "  Those steps did not verify this file; the full gate must go green once the plan's files land."
  fi
  say "Next: /review-check, then /review over the complete change set."
  finish 0
}

case "${1:-}" in
  run) shift; cmd_run "$@" ;;
  -h | --help | "") usage; [[ -n "${1:-}" ]] ;;
  *) say "unknown subcommand: $1 (run with --help)"; exit 2 ;;
esac
