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
# Usage: .agentic/delegate-run.sh <subcommand> [args] [--profile <path>]
#
#   qualify <model>          Plumbing check: one known-answer packet sized
#                            like a medium task, graded exactly. A model must
#                            pass before `run` will use it; any change to its
#                            setup (model, quant, runtime, request settings,
#                            endpoint, runner version) needs a new pass.
#   run <packet> [--model <name>]
#                            Send <packet> to the named model, or without
#                            --model to the model selected from this
#                            project's [[project]] candidates. Up to three
#                            calls; each attempt starts from the same clean
#                            scratch snapshot. Retries carry the previous
#                            candidate and bounded failure output.
#   record-review <run> pass|model-defect|packet-defect
#                            Record /review's final verdict on a published
#                            candidate. Until then a green run is pending.
#   policy                   Prints `auto` and exits 0 only when this
#                            checkout's [[project]] entry has policy = "auto",
#                            activation_approved = true, and at least one
#                            qualified candidate; otherwise prints `off: <why>`
#                            and exits 1. The orchestrator checks this before
#                            handing implementation to a local model.
#   discover                 What each endpoint's /models lists, matched to
#                            profile models and their qualification.
#   status                   Each profile model's qualification and its
#                            record per bucket in this project.
#   reset <model> <bucket>   Clear a demotion; starts a fresh record.
#
# Scoring (docs/local-delegate-runner.md in agentic-scaffold): a success is
# a published candidate that passed review; a failure is needs_frontier or
# a model-defect review. A model is demoted for a bucket after a
# model-defect review, or when it has at least 5 scored runs and the upper
# bound of the 95% Wilson interval over its last 20 is below 50%. Demotion
# warns but does not block a manual run. Selection explores candidates with
# fewer than 5 scored runs in list order, then ranks by the interval's lower
# bound; unqualified, demoted, and unreachable candidates are skipped.
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
#   0   run: green candidate published (uncommitted); qualify: passed
#   10  needs_frontier: three attempts spent, a model call timed out after
#       connecting (scored against the model; no retry), or nothing was
#       selectable; implement with the frontier model
#   2   refused: usage, profile, packet, or workspace preconditions
#   5   qualify: the model failed the plumbing check
#   3   infrastructure failure: endpoint, transport, or verifier
#   4   integrity stop: unexpected writes, or the workspace changed mid-run
#
# Requires: bash, git, curl, jq (1.6+), tar, and sha256sum or shasum.

set -uo pipefail

HARNESS_VERSION="delegate-run-v1"
MAX_ATTEMPTS=3
# Scoring and bucket parameters are unsourced starting points
# (docs/local-delegate-runner.md -> "Unsourced starting points"); tune them
# from the ledger, and bump HARNESS_VERSION when the retry rules change.
EXPLORE_MIN=5
WINDOW=20
DEMOTE_MIN=5
DEMOTE_BELOW=0.5
Z=1.96
SMALL_LINES=150
SMALL_CONTRACTS=8
MEDIUM_LINES=300
MEDIUM_CONTRACTS=15
DIAG_LINES=120
DIAG_BYTES=12000

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 3
DELEGATE_DIR="$ROOT/.agentic/delegate"
TOOLCHAIN=.agentic/toolchain.sh

say() { printf 'delegate-run: %s\n' "$*" >&2; }

usage() {
  sed -n '2,83p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
# Each verifier command gets DELEGATE_STEP_TIMEOUT seconds (default 900) so a
# candidate that hangs a test cannot hang the run. The command runs in its
# own process group, which is killed whole on timeout; exit status is 124.
STEP_TIMEOUT="${DELEGATE_STEP_TIMEOUT:-900}"

bounded() {
  if command -v perl >/dev/null 2>&1; then
    perl -e '
      my $limit = shift;
      my $pid = fork() // die "fork: $!";
      if ($pid == 0) { setpgrp(0, 0); exec { $ARGV[0] } @ARGV or exit 127; }
      local $SIG{ALRM} = sub {
        kill "TERM", -$pid; sleep 2; kill "KILL", -$pid; waitpid($pid, 0);
        print STDERR "delegate-run: timed out after ${limit}s: @ARGV\n";
        exit 124;
      };
      alarm $limit;
      waitpid($pid, 0);
      exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
    ' "$STEP_TIMEOUT" "$@"
  else
    "$@"
  fi
}

verify_cmd() {
  if [[ -n "${CRED_ENV:-}" ]]; then
    (cd "$TREE" && bounded env -u "$CRED_ENV" "$@")
  else
    (cd "$TREE" && bounded "$@")
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

# ---- profile, setup fingerprint, qualification --------------------------------

default_profile() {
  printf '%s' "${AGENTIC_DELEGATE_PROFILE:-${XDG_CONFIG_HOME:-$HOME/.config}/agentic/local-models.toml}"
}

# load_profile <path> : parses the profile into $STATE/profile.tsv and sets
# QUAL_FILE, the machine-wide qualification record kept beside it.
load_profile() {
  [[ -f "$1" ]] || refuse "profile not found: $1"
  PROFILE_TSV="$STATE/profile.tsv"
  profile_entries "$1" >"$PROFILE_TSV"
  QUAL_FILE="$(dirname "$1")/local-models-qualified.jsonl"
}

profile_models() { awk -F'\t' '$1 == "model" && $3 == "name" { print $4 }' "$PROFILE_TSV"; }

# load_model <name> : the model's settings and the fingerprint of its setup.
load_model() {
  MODEL_NAME="$1"
  MODEL_ID="$(profile_get model "$MODEL_NAME" model_id)"
  [[ -n "$MODEL_ID" ]] || refuse "no [[model]] named '$MODEL_NAME' with a model_id in the profile"
  ENDPOINT_NAME="$(profile_get model "$MODEL_NAME" endpoint)"
  QUANT="$(profile_get model "$MODEL_NAME" quant)"
  RUNTIME="$(profile_get model "$MODEL_NAME" runtime)"
  REQUEST_JSON="$(profile_get model "$MODEL_NAME" request)"
  TIMEOUT="$(profile_get model "$MODEL_NAME" timeout_seconds)"
  TIMEOUT="${TIMEOUT:-900}"
  [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || refuse "timeout_seconds must be a whole number of seconds"
  local request_norm='{}'
  if [[ -n "$REQUEST_JSON" ]]; then
    request_norm="$(jq -S -c . <<<"$REQUEST_JSON" 2>/dev/null)" && jq -e 'type == "object"' <<<"$REQUEST_JSON" >/dev/null 2>&1 ||
      refuse "model '$MODEL_NAME': request must be a JSON object in a literal string, e.g. request = '{\"temperature\": 0.6}'"
  fi
  [[ -n "$ENDPOINT_NAME" ]] || refuse "model '$MODEL_NAME' names no endpoint"
  BASE_URL="$(profile_get endpoint "$ENDPOINT_NAME" base_url)"
  BASE_URL="${BASE_URL%/}"
  [[ "$BASE_URL" =~ ^https?://[^[:space:]]+$ ]] || refuse "endpoint '$ENDPOINT_NAME' needs an http(s) base_url"
  CRED_ENV="$(profile_get endpoint "$ENDPOINT_NAME" credential_env)"
  # Any change to what the model receives or how it is served is a new setup.
  FINGERPRINT="$(printf '%s\n' "$HARNESS_VERSION" "$BASE_URL" "$MODEL_ID" "$QUANT" "$RUNTIME" "$request_norm" |
    "${SHA[@]}" | cut -c1-16)"
}

check_credential() {
  [[ -n "${CRED_ENV:-}" ]] || return 0
  [[ "$CRED_ENV" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || refuse "credential_env must be an environment variable name"
  [[ -n "${!CRED_ENV:-}" ]] || refuse "credential_env '$CRED_ENV' is not set in this environment"
}

# qualification_state <model> <fingerprint> : qualified | unqualified, from
# the latest qualify result for exactly this setup.
qualification_state() {
  local result=""
  [[ -f "$QUAL_FILE" ]] &&
    result="$(jq -r -s --arg m "$1" --arg f "$2" \
      'map(select(.model == $m and .fingerprint == $f)) | last | .result // ""' "$QUAL_FILE" 2>/dev/null)"
  if [[ "$result" == pass ]]; then echo qualified; else echo unqualified; fi
}

# ---- scoring ------------------------------------------------------------------

# score <model> <fingerprint> <bucket> : prints
#   scored passed pending defects low high demoted median-seconds
# over this project's ledger, since the last reset for that model and bucket.
score() {
  local counts="0	0	0	0	0"
  if [[ -f "$DELEGATE_DIR/ledger.jsonl" ]]; then
    counts="$(jq -r -s --arg m "$1" --arg f "$2" --arg b "$3" --argjson w "$WINDOW" '
      . as $all
      | ([$all | to_entries[] | select(.value.type == "reset" and .value.model == $m
          and .value.bucket == $b) | .key] | max // -1) as $since
      | (reduce ($all[] | select(.type == "review")) as $r ({}; .[$r.run] = $r.verdict)) as $rev
      | [$all | to_entries[] | select(.key > $since) | .value
          | select((.type // "run") == "run" and .model.name == $m and .fingerprint == $f
              and .bucket == $b and .qualified == true)
          | if .outcome == "needs_frontier" then "fail"
            elif .outcome == "green" then
              ($rev[.run] // "pending")
              | if . == "pass" then "pass" elif . == "model-defect" then "defect"
                elif . == "pending" then "pending" else "unscored" end
            else "unscored" end] as $o
      | ([$o[] | select(. == "pass" or . == "fail" or . == "defect")] | .[-$w:]) as $win
      | [$all | to_entries[] | select(.key > $since) | .value
          | select((.type // "run") == "run" and .model.name == $m and .fingerprint == $f
              and .bucket == $b and .qualified == true and (.outcome == "green" or .outcome == "needs_frontier"))
          | ([.attempts[]?.seconds] | add // 0)] as $secs
      | ($secs | .[-$w:] | sort) as $ss
      | [($win | length), ([$win[] | select(. == "pass")] | length),
         ([$o[] | select(. == "pending")] | length), ([$o[] | select(. == "defect")] | length),
         (if ($ss | length) == 0 then 0 else $ss[(($ss | length) / 2 | floor)] end)]
      | @tsv' "$DELEGATE_DIR/ledger.jsonl")" || counts="0	0	0	0	0"
  fi
  awk -F'\t' -v z="$Z" -v min="$DEMOTE_MIN" -v below="$DEMOTE_BELOW" '{
    n = $1; s = $2; lo = 0; hi = 1
    if (n > 0) {
      p = s / n; d = 1 + z * z / n
      c = (p + z * z / (2 * n)) / d
      h = z * sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
      lo = c - h; hi = c + h
      if (lo < 0) lo = 0
      if (hi > 1) hi = 1
    }
    demoted = ($4 > 0 || (n >= min && hi < below)) ? "demoted" : "ok"
    printf "%d %d %d %d %.2f %.2f %s %d\n", n, s, $3, $4, lo, hi, demoted, $5
  }' <<<"$counts"
}

# describe_score <model> <fingerprint> <bucket> : one human-readable line.
describe_score() {
  local n s pending defects lo hi demoted _median
  read -r n s pending defects lo hi demoted _median <<<"$(score "$@")"
  local line="$3: $s/$n passed"
  ((n > 0)) && line="$line (95% range $(awk -v x="$lo" 'BEGIN { printf "%d", x * 100 }')–$(awk -v x="$hi" 'BEGIN { printf "%d", x * 100 }')%)"
  ((pending > 0)) && line="$line, $pending awaiting review"
  ((defects > 0)) && line="$line, $defects review defect(s)"
  [[ "$demoted" == demoted ]] && line="$line — DEMOTED (reset with: delegate-run.sh reset $1 $3)"
  printf '%s\n' "$line"
}

# bucket_for <lines> <contract-items> : small | medium | too-large
bucket_for() {
  local lines="$1" contracts="${2:-0}"
  if ((lines <= SMALL_LINES && contracts <= SMALL_CONTRACTS)); then
    echo small
  elif ((lines <= MEDIUM_LINES && contracts <= MEDIUM_CONTRACTS)); then
    echo medium
  else
    echo too-large
  fi
}

# ---- project entry, selection, discovery ------------------------------------

# project_get <key> : the key of the [[project]] entry whose root is this
# checkout (compared as physical paths).
project_get() {
  local here idx root
  here="$(cd "$ROOT" && pwd -P)"
  while IFS=$'\t' read -r idx root; do
    [[ -d "$root" ]] || continue
    if [[ "$(cd "$root" && pwd -P)" == "$here" ]]; then
      awk -F'\t' -v i="$idx" -v k="$1" '$1 == "project" && $2 == i && $3 == k { print $4; exit }' "$PROFILE_TSV"
      return 0
    fi
  done <<<"$(awk -F'\t' '$1 == "project" && $3 == "root" { print $2 "\t" $4 }' "$PROFILE_TSV")"
}

# toml_list "[\"a\", \"b\"]" : one item per line.
toml_list() { tr -d '[]"'"'"' ' <<<"$1" | tr ',' '\n' | awk 'NF'; }

# reachable : the current model's endpoint answers at all within 5 seconds.
reachable() {
  if [[ -n "${CRED_ENV:-}" ]]; then
    [[ -n "${!CRED_ENV:-}" ]] || return 1
    curl -sS -o /dev/null --connect-timeout 5 --max-time 5 \
      -H @<(printf 'Authorization: Bearer %s\n' "${!CRED_ENV}") "$BASE_URL/models" 2>/dev/null
  else
    curl -sS -o /dev/null --connect-timeout 5 --max-time 5 "$BASE_URL/models" 2>/dev/null
  fi
}

# select_model : explore candidates with fewer than EXPLORE_MIN scored runs in
# list order, then rank by the interval lower bound, median time, list order.
select_model() {
  local raw name row rows=""
  raw="$(project_get candidates)"
  [[ -n "$raw" ]] || refuse "no --model and no [[project]] entry with candidates for $ROOT in the profile"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    # Evaluate each candidate in a subshell so a misconfigured one is skipped
    # with its reason instead of ending the run.
    row="$(
      refuse() { printf '%s\tbad\t-\t0\t0\t0\t0\t0\t1\tok\t0\t0\t%s\n' "$name" "$*"; exit 0; }
      load_model "$name"
      state="$(qualification_state "$name" "$FINGERPRINT")"
      read -r n s pend def lo hi dem med <<<"$(score "$name" "$FINGERPRINT" "$BUCKET")"
      up=0
      [[ "$state" == qualified && "$dem" == ok ]] && reachable && up=1
      why=""
      [[ "$state" == qualified ]] || why="unqualified"
      [[ "$dem" == ok ]] || why="${why:+$why, }demoted"
      [[ "$state" == qualified && "$dem" == ok && "$up" == 0 ]] && why="unreachable"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$state" "$FINGERPRINT" "$n" "$s" "$pend" "$def" "$lo" "$hi" "$dem" "$med" "$up" "$why"
    )"
    rows="${rows}${row}"$'\n'
  done <<<"$(toml_list "$raw")"
  printf '%s' "$rows" >"$STATE/candidates.tsv"

  # columns: 1 name 2 state 3 fp 4 n 5 s 6 pend 7 def 8 lo 9 hi 10 dem 11 med 12 up 13 why
  local phase="" chosen="" runner_up="" ranked
  chosen="$(awk -F'\t' -v min="$EXPLORE_MIN" '$12 == 1 && $4 < min { print $1; exit }' "$STATE/candidates.tsv")"
  # Ranked order: lower bound high to low, then median time, then list order.
  ranked="$(awk -F'\t' '$12 == 1 { printf "%s\t%s\t%d\t%s\n", $8, $11, NR, $1 }' "$STATE/candidates.tsv" |
    sort -t$'\t' -k1,1gr -k2,2n -k3,3n | cut -f4)"
  if [[ -n "$chosen" ]]; then
    phase=explore
    runner_up="$(grep -v -x -F "$chosen" <<<"$ranked" | head -n 1 || true)"
  elif [[ -n "$ranked" ]]; then
    phase=rank
    chosen="$(head -n 1 <<<"$ranked")"
    runner_up="$(sed -n 2p <<<"$ranked")"
  else
    OUTCOME=needs_frontier
    REASON="no selectable candidate for $BUCKET tasks: $(awk -F'\t' '{ printf "%s%s (%s)", sep, $1, $13; sep = ", " }' "$STATE/candidates.tsv")"
    say "needs_frontier: $REASON"
    SELECTION_JSON="$(selection_json none "" "")"
    finish 10
  fi
  SELECTION_JSON="$(selection_json "$phase" "$chosen" "$runner_up")"
  load_model "$chosen"
  check_credential
  QUALIFIED=qualified
  local line
  line="$(awk -F'\t' -v c="$chosen" '$1 == c { printf "%d scored runs, %d passed, lower bound %.2f", $4, $5, $8 }' "$STATE/candidates.tsv")"
  if [[ "$phase" == explore ]]; then
    say "selected '$chosen' to explore ($line; fewer than $EXPLORE_MIN scored)${runner_up:+; next: '$runner_up'}"
  else
    say "selected '$chosen' by record ($line)${runner_up:+; runner-up: '$runner_up'}"
  fi
}

selection_json() {
  jq -c -n --arg phase "$1" --arg chosen "$2" --arg runner_up "$3" --rawfile rows "$STATE/candidates.tsv" '
    {phase: $phase, chosen: $chosen, runner_up: $runner_up,
     considered: [$rows | split("\n")[] | select(length > 0) | split("\t")
       | {model: .[0], state: .[1], scored: (.[3] | tonumber), passed: (.[4] | tonumber),
          low: (.[7] | tonumber), high: (.[8] | tonumber), demoted: (.[9] == "demoted"),
          median_seconds: (.[10] | tonumber), selectable: (.[11] == "1"), why: .[12]}]}'
}

# ---- model call ---------------------------------------------------------------

request_extra() {
  if [[ -n "${REQUEST_JSON:-}" ]]; then printf '%s' "$REQUEST_JSON"; else printf '{}'; fi
}

# request_first <out> <content-file> : one user message plus pinned settings.
request_first() {
  jq -n --arg model "$MODEL_ID" --rawfile content "$2" --argjson extra "$(request_extra)" \
    '{model: $model, stream: false, messages: [{role: "user", content: $content}]} + $extra' >"$1" ||
    infra "could not build the request (is 'request' in the profile valid JSON?)"
}

# request_retry <out> : the packet, the previous candidate, and the feedback.
request_retry() {
  jq -n --arg model "$MODEL_ID" --rawfile packet "$STATE/packet-body.md" \
    --rawfile previous "$STATE/previous-candidate" --rawfile feedback "$STATE/feedback.md" \
    --argjson extra "$(request_extra)" \
    '{model: $model, stream: false, messages: [
       {role: "user", content: $packet},
       {role: "assistant", content: $previous},
       {role: "user", content: $feedback}]} + $extra' >"$1" ||
    infra "could not build the request (is 'request' in the profile valid JSON?)"
}

# call_model <label> <request-file> : writes $STATE/<label>.response.json and
# sets CALL_SECONDS. Returns 2 when the server accepted the connection but the
# model did not answer within timeout_seconds (thinking counts): that is the
# model's setup being too slow, which the caller scores. Every other transport
# failure exits through infra() and is not scored.
call_model() {
  local label="$1" req="$2"
  local resp="$STATE/$label.response.json" err="$STATE/$label.curl.err"
  local out curl_status=0 code
  if [[ -n "${CRED_ENV:-}" ]]; then
    # The header comes through a file descriptor so the credential never
    # appears in a process argument list.
    out="$(curl -sS --connect-timeout 10 --max-time "$TIMEOUT" \
      -H 'Content-Type: application/json' \
      -H @<(printf 'Authorization: Bearer %s\n' "${!CRED_ENV}") \
      --data-binary @"$req" -o "$resp" -w '%{http_code} %{time_total} %{time_connect}' \
      "$BASE_URL/chat/completions" 2>"$err")" || curl_status=$?
  else
    out="$(curl -sS --connect-timeout 10 --max-time "$TIMEOUT" \
      -H 'Content-Type: application/json' \
      --data-binary @"$req" -o "$resp" -w '%{http_code} %{time_total} %{time_connect}' \
      "$BASE_URL/chat/completions" 2>"$err")" || curl_status=$?
  fi
  local connect
  read -r code CALL_SECONDS connect <<<"$out"
  if [[ "$curl_status" == 28 ]] && awk -v c="${connect:-0}" 'BEGIN { exit !(c > 0) }'; then
    CALL_SECONDS="$TIMEOUT"
    return 2
  fi
  if [[ "$curl_status" != 0 ]]; then
    infra "endpoint '$ENDPOINT_NAME' unreachable (curl exit $curl_status: $(head -c 300 "$err"))"
  fi
  if [[ "$code" != 2* ]]; then
    infra "endpoint '$ENDPOINT_NAME' returned HTTP $code: $(head -c 300 "$resp" 2>/dev/null)"
  fi
  jq -e 'type == "object"' "$resp" >/dev/null 2>&1 ||
    infra "endpoint '$ENDPOINT_NAME' returned malformed JSON"
}

# extract_candidate <label> : writes $STATE/candidate; on a format problem
# prints the reason and returns 1 (the attempt is spent, with feedback).
extract_candidate() {
  local resp="$STATE/$1.response.json" cand="$STATE/candidate" finish first
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
      --arg fingerprint "${FINGERPRINT:-}" --argjson qualified "$([[ "${QUALIFIED:-}" == qualified ]] && echo true || echo false)" \
      --arg mode "${MODE:-manual}" --argjson selection "${SELECTION_JSON:-null}" \
      '{type: "run", ts: $ts, run: $run, mode: $mode, selection: $selection, fingerprint: $fingerprint,
        qualified: $qualified, packet: $packet,
        packet_sha256: $packet_sha, target: $target, bucket: $bucket,
        snapshot_sha256: $snapshot, harness: $harness,
        model: {name: $model, model_id: $model_id, quant: $quant, runtime: $runtime,
                endpoint: $endpoint, request: $request},
        attempts: $attempts, outcome: $outcome, reason: $reason,
        gate: $gate, unverified_steps: ($unverified | split(" ") | map(select(. != ""))),
        review: null}' \
      >"$result_dir/result.json"
    jq -c . "$result_dir/result.json" >>"$DELEGATE_DIR/ledger.jsonl"
    say "result: ${result_dir#"$ROOT"/}/result.json (run id: $RUN_ID)"
    if [[ "$OUTCOME" == green || "$OUTCOME" == needs_frontier ]]; then
      say "record for '$MODEL_NAME', $(describe_score "$MODEL_NAME" "$FINGERPRINT" "$BUCKET")"
    fi
    if [[ "$OUTCOME" == green ]]; then
      say "after /review: delegate-run.sh record-review $RUN_ID pass|model-defect|packet-defect"
    fi
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
  local packet="" profile
  profile="$(default_profile)"
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
  [[ -n "$packet" ]] || { say "usage: delegate-run.sh run <packet> [--model <name>]"; exit 2; }
  MODE=manual
  [[ -n "$MODEL_NAME" ]] || MODE=selected

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
  RUN_ID="$(basename "$packet_abs" .md)-$(date -u +%Y%m%dT%H%M%SZ)-$$"

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/delegate-run.XXXXXX")" || infra "could not create scratch directory"
  STATE="$WORK/state"
  TREE="$WORK/tree"
  mkdir -p "$STATE" "$TREE"

  # -- profile
  load_profile "$profile"

  # -- packet
  packet_header "$packet_abs" >"$STATE/header.tsv"
  packet_body "$packet_abs" >"$STATE/packet-body.md"
  local targets tests
  targets="$(awk -F'\t' '$1 == "targets" { print $2 }' "$STATE/header.tsv")"
  tests="$(awk -F'\t' '$1 == "test_targets" { print $2 }' "$STATE/header.tsv")"
  local declared_bucket contracts
  declared_bucket="$(awk -F'\t' '$1 == "bucket" { print $2; exit }' "$STATE/header.tsv")"
  contracts="$(awk -F'\t' '$1 == "contract_items" { print $2; exit }' "$STATE/header.tsv")"
  [[ "$contracts" =~ ^[0-9]+$ ]] || contracts=0
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
  no_symlink_path "$ROOT" "$TARGET" || integrity "target path '$TARGET' passes through a symlink"

  # The bucket comes from the file, not the label, so a mislabelled packet
  # cannot land in a smaller bucket.
  local lines=0
  [[ -f "$ROOT/$TARGET" ]] && lines="$(wc -l <"$ROOT/$TARGET" | tr -d ' ')"
  BUCKET="$(bucket_for "$lines" "$contracts")"
  [[ "$BUCKET" != too-large ]] ||
    refuse "target is $lines lines with $contracts contract items: larger than the medium bucket (<=$MEDIUM_LINES lines, <=$MEDIUM_CONTRACTS items)"
  [[ -z "$declared_bucket" || "$declared_bucket" == "$BUCKET" ]] ||
    say "note: packet says bucket '$declared_bucket'; the file makes it '$BUCKET'"

  # -- model: the one the human named, or the runner's selection
  if [[ -n "$MODEL_NAME" ]]; then
    MODE=manual
    load_model "$MODEL_NAME"
    check_credential
    QUALIFIED="$(qualification_state "$MODEL_NAME" "$FINGERPRINT")"
    [[ "$QUALIFIED" == qualified ]] ||
      refuse "model '$MODEL_NAME' is $QUALIFIED for its current setup; run: delegate-run.sh qualify $MODEL_NAME"
    [[ "$(score "$MODEL_NAME" "$FINGERPRINT" "$BUCKET" | cut -d' ' -f7)" != demoted ]] ||
      say "warning: '$MODEL_NAME' is demoted for $BUCKET tasks; this manual run is still scored"
  else
    MODE=selected
    select_model
  fi

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
    if [[ "$n" == 1 ]]; then
      request_first "$STATE/attempt-$n.request.json" "$STATE/packet-body.md"
    else
      request_retry "$STATE/attempt-$n.request.json"
    fi
    if ! call_model "attempt-$n" "$STATE/attempt-$n.request.json"; then
      # A retry would most likely time out again, so the run ends here and is
      # scored as a failure for this model.
      elapsed=$(($(date +%s) - started))
      reason="the model did not answer within timeout_seconds=$TIMEOUT (connected; thinking counts toward the limit)"
      printf '%s\n' "$reason" >"$STATE/last-diagnostics.txt"
      record_attempt "$n" timeout "$reason" "$elapsed"
      OUTCOME=needs_frontier
      REASON="$reason; raise timeout_seconds for '$MODEL_NAME' or cap its reasoning in request"
      say "needs_frontier: $REASON"
      say "packet: $PACKET_REL"
      finish 10
    fi
    if ! reason="$(extract_candidate "attempt-$n")"; then
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

# ---- qualify ------------------------------------------------------------------

# The plumbing file: about 270 lines, near the top of the medium bucket, so a
# setup that truncates, runs out of context, or times out on a real file
# fails here. The edit asked for is trivial, so grading can be exact.
PLUMBING_COUNT=30
PLUMBING_RENAME=17
PLUMBING_CONSTANT=23

plumbing_file() {
  local i
  printf '"""Plumbing fixture for delegate-run qualify. Generated; do not edit."""\n\n'
  for ((i = 1; i <= PLUMBING_COUNT; i++)); do printf 'SCALE_%02d = %d\n' "$i" "$i"; done
  for ((i = 1; i <= PLUMBING_COUNT; i++)); do
    printf '\n\ndef metric_%02d(values):\n    """Return the scaled total for metric %d."""\n' "$i" "$i"
    printf '    total = 0\n    for value in values:\n        total += value * SCALE_%02d\n    return total\n' "$i"
  done
}

plumbing_expected() {
  plumbing_file | sed \
    -e "s/^def metric_${PLUMBING_RENAME}(values):\$/def weighted_metric_${PLUMBING_RENAME}(values):/" \
    -e "s/^SCALE_${PLUMBING_CONSTANT} = ${PLUMBING_CONSTANT}\$/SCALE_${PLUMBING_CONSTANT} = ${PLUMBING_CONSTANT}0/"
}

plumbing_packet() {
  cat <<EOF
# Task

Return \`plumbing.py\` with exactly two changes and nothing else changed:

1. Rename the function \`metric_${PLUMBING_RENAME}\` to \`weighted_metric_${PLUMBING_RENAME}\`. Change only its \`def\` line.
2. Change the constant line \`SCALE_${PLUMBING_CONSTANT} = ${PLUMBING_CONSTANT}\` to \`SCALE_${PLUMBING_CONSTANT} = ${PLUMBING_CONSTANT}0\`.

Keep every other line exactly as it is, including blank lines and docstrings.

# The file as it exists now

\`\`\`python
EOF
  plumbing_file
  cat <<'EOF'
```

# Output contract

> Return the complete final contents of `plumbing.py`, and nothing else. No
> diff, no patch, no commentary, no markdown fence around the file, no
> explanation of your changes.
EOF
}

# Whitespace-insensitive at line ends and file edges only.
# Blank lines print only when a non-blank line follows, which drops them at
# both ends of the file.
normalize() {
  tr -d '\r' <"$1" | sed 's/[[:space:]]*$//' |
    awk 'NF { for (; k > 0; k--) print ""; print; seen = 1; next } seen { k++ }'
}

record_qualification() {
  mkdir -p "$(dirname "$QUAL_FILE")"
  jq -c -n --arg ts "$(now_utc)" --arg model "$MODEL_NAME" --arg fingerprint "$FINGERPRINT" \
    --arg result "$1" --arg reason "$2" --arg first "${3:-}" --arg plumbing "${4:-}" \
    --argjson timeout "$TIMEOUT" --arg harness "$HARNESS_VERSION" --arg model_id "$MODEL_ID" \
    --arg quant "$QUANT" --arg runtime "$RUNTIME" --arg endpoint "$ENDPOINT_NAME" \
    '{ts: $ts, model: $model, fingerprint: $fingerprint, result: $result, reason: $reason,
      first_response_seconds: $first, plumbing_seconds: $plumbing, timeout_seconds: $timeout,
      harness: $harness, model_id: $model_id, quant: $quant, runtime: $runtime, endpoint: $endpoint}' \
    >>"$QUAL_FILE"
}

cmd_qualify() {
  local name="" profile
  profile="$(default_profile)"
  while (($#)); do
    case "$1" in
      --profile) profile="${2:-}"; shift 2 ;;
      -*) say "unknown option: $1"; exit 2 ;;
      *) name="$1"; shift ;;
    esac
  done
  [[ -n "$name" ]] || { say "usage: delegate-run.sh qualify <model>"; exit 2; }
  require_deps curl jq awk
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/delegate-qualify.XXXXXX")" || exit 3
  STATE="$WORK/state"
  mkdir -p "$STATE"
  trap cleanup EXIT
  load_profile "$profile"
  load_model "$name"
  check_credential

  # Is the model listed? A warning only: not every server lists every model.
  local listing="$STATE/models.json" listed=0
  if [[ -n "${CRED_ENV:-}" ]]; then
    curl -sS --connect-timeout 10 --max-time 30 -o "$listing" \
      -H @<(printf 'Authorization: Bearer %s\n' "${!CRED_ENV}") \
      "$BASE_URL/models" 2>/dev/null && listed=1
  else
    curl -sS --connect-timeout 10 --max-time 30 -o "$listing" "$BASE_URL/models" 2>/dev/null && listed=1
  fi
  if [[ "$listed" == 1 ]] && jq -e '.data | type == "array"' "$listing" >/dev/null 2>&1; then
    jq -e --arg id "$MODEL_ID" 'any(.data[]; .id == $id)' "$listing" >/dev/null ||
      say "warning: '$ENDPOINT_NAME' does not list model_id '$MODEL_ID' in /models"
  fi

  say "qualifying '$MODEL_NAME' (setup $FINGERPRINT): first response, then a $(plumbing_file | wc -l | tr -d ' ')-line plumbing file"
  printf 'Reply with the single word OK.\n' >"$STATE/warmup.md"
  request_first "$STATE/warmup.request.json" "$STATE/warmup.md"
  if ! call_model warmup "$STATE/warmup.request.json"; then
    record_qualification fail "first response timed out after ${TIMEOUT}s (includes any model load)" "$TIMEOUT" ""
    say "not qualified: no first response within timeout_seconds=$TIMEOUT; raise it if the model needs longer to load"
    exit 5
  fi
  local first="$CALL_SECONDS"

  plumbing_packet >"$STATE/plumbing.md"
  request_first "$STATE/plumbing.request.json" "$STATE/plumbing.md"
  if ! call_model plumbing "$STATE/plumbing.request.json"; then
    record_qualification fail "plumbing file timed out after ${TIMEOUT}s" "$first" "$TIMEOUT"
    say "not qualified: the plumbing file did not come back within timeout_seconds=$TIMEOUT; raise it or cap the model's reasoning"
    exit 5
  fi
  local gen="$CALL_SECONDS" reason
  if ! reason="$(extract_candidate plumbing)"; then
    record_qualification fail "$reason" "$first" "$gen"
    say "not qualified: $reason"
    exit 5
  fi
  plumbing_expected >"$STATE/expected.py"
  normalize "$STATE/expected.py" >"$STATE/expected.norm"
  normalize "$STATE/candidate" >"$STATE/candidate.norm"
  if ! cmp -s "$STATE/expected.norm" "$STATE/candidate.norm"; then
    local where
    where="$(diff "$STATE/expected.norm" "$STATE/candidate.norm" | head -n 6 | tr '\n' ' ')"
    record_qualification fail "returned file differs from the expected edit: $where" "$first" "$gen"
    say "not qualified: the returned file differs from the expected edit"
    say "  first differences: $where"
    exit 5
  fi
  record_qualification pass "" "$first" "$gen"
  say "qualified: '$MODEL_NAME' — first response ${first}s (includes any model load), plumbing ${gen}s, timeout ${TIMEOUT}s"
  if awk -v a="$first" -v b="$gen" -v t="$TIMEOUT" 'BEGIN { exit !(a + b > 0.6 * t) }'; then
    say "warning: a cold load plus a medium file took over 60% of timeout_seconds; raise it for this model"
  fi
}

# ---- record-review, status, reset -------------------------------------------------

cmd_record_review() {
  local run="${1:-}" verdict="${2:-}"
  [[ -n "$run" && -n "$verdict" ]] || { say "usage: delegate-run.sh record-review <run> pass|model-defect|packet-defect"; exit 2; }
  case "$verdict" in pass | model-defect | packet-defect) ;; *) say "unknown verdict: $verdict"; exit 2 ;; esac
  require_deps jq awk
  local ledger="$DELEGATE_DIR/ledger.jsonl" rec
  [[ -f "$ledger" ]] || { say "no ledger at $ledger"; exit 2; }
  rec="$(jq -c -s --arg r "$run" 'map(select((.type // "run") == "run" and .run == $r)) | last // empty' "$ledger")"
  [[ -n "$rec" ]] || { say "no run '$run' in the ledger"; exit 2; }
  [[ "$(jq -r .outcome <<<"$rec")" == green ]] || { say "run '$run' did not publish a candidate; nothing to review"; exit 2; }
  jq -c -n --arg ts "$(now_utc)" --arg run "$run" --arg verdict "$verdict" \
    '{type: "review", ts: $ts, run: $run, verdict: $verdict}' >>"$ledger"
  local model fingerprint bucket
  model="$(jq -r .model.name <<<"$rec")"
  fingerprint="$(jq -r .fingerprint <<<"$rec")"
  bucket="$(jq -r .bucket <<<"$rec")"
  say "recorded $verdict for $run"
  say "record for '$model', $(describe_score "$model" "$fingerprint" "$bucket")"
}

cmd_status() {
  local profile name state bucket
  profile="$(default_profile)"
  [[ "${1:-}" == --profile ]] && profile="${2:-}"
  require_deps jq awk
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/delegate-status.XXXXXX")" || exit 3
  STATE="$WORK/state"
  mkdir -p "$STATE"
  trap cleanup EXIT
  load_profile "$profile"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    load_model "$name"
    state="$(qualification_state "$name" "$FINGERPRINT")"
    printf '%s (%s, setup %s): %s\n' "$name" "$MODEL_ID" "$FINGERPRINT" "$state"
    for bucket in small medium; do
      printf '  %s\n' "$(describe_score "$name" "$FINGERPRINT" "$bucket")"
    done
  done <<<"$(profile_models)"
}

cmd_discover() {
  local profile endpoint id name listing found candidates
  profile="$(default_profile)"
  [[ "${1:-}" == --profile ]] && profile="${2:-}"
  require_deps curl jq awk
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/delegate-discover.XXXXXX")" || exit 3
  STATE="$WORK/state"
  mkdir -p "$STATE"
  trap cleanup EXIT
  load_profile "$profile"
  candidates="$(toml_list "$(project_get candidates)")"
  while IFS= read -r endpoint; do
    [[ -n "$endpoint" ]] || continue
    BASE_URL="$(profile_get endpoint "$endpoint" base_url)"
    BASE_URL="${BASE_URL%/}"
    CRED_ENV="$(profile_get endpoint "$endpoint" credential_env)"
    listing="$STATE/$endpoint.json"
    found=0
    if [[ -n "$CRED_ENV" && -n "${!CRED_ENV:-}" ]]; then
      curl -sS --connect-timeout 5 --max-time 15 -o "$listing" \
        -H @<(printf 'Authorization: Bearer %s\n' "${!CRED_ENV}") "$BASE_URL/models" 2>/dev/null && found=1
    elif [[ -z "$CRED_ENV" ]]; then
      curl -sS --connect-timeout 5 --max-time 15 -o "$listing" "$BASE_URL/models" 2>/dev/null && found=1
    fi
    if [[ "$found" != 1 ]] || ! jq -e '.data | type == "array"' "$listing" >/dev/null 2>&1; then
      printf '%s: unreachable or no model listing%s\n' "$endpoint" "${CRED_ENV:+ (credential_env $CRED_ENV)}"
      continue
    fi
    printf '%s:\n' "$endpoint"
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      local matched=0
      while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        [[ "$(profile_get model "$name" endpoint)" == "$endpoint" &&
          "$(profile_get model "$name" model_id)" == "$id" ]] || continue
        matched=1
        (
          refuse() { printf '  %s -> %s: misconfigured (%s)\n' "$id" "$name" "$*"; exit 0; }
          load_model "$name"
          printf '  %s -> %s: %s%s\n' "$id" "$name" "$(qualification_state "$name" "$FINGERPRINT")" \
            "$(grep -q -x -F "$name" <<<"$candidates" && echo ", project candidate")"
        )
      done <<<"$(profile_models)"
      [[ "$matched" == 1 ]] || printf '  %s: available, not in the profile\n' "$id"
    done <<<"$(jq -r '.data[].id' "$listing")"
    while IFS= read -r name; do
      [[ -n "$name" && "$(profile_get model "$name" endpoint)" == "$endpoint" ]] || continue
      id="$(profile_get model "$name" model_id)"
      jq -e --arg id "$id" 'any(.data[]; .id == $id)' "$listing" >/dev/null ||
        printf '  %s -> %s: configured but not listed by the server\n' "$id" "$name"
    done <<<"$(profile_models)"
  done <<<"$(awk -F'\t' '$1 == "endpoint" && $3 == "name" { print $4 }' "$PROFILE_TSV")"
}

cmd_policy() {
  local profile policy approved name qualified=""
  profile="$(default_profile)"
  [[ "${1:-}" == --profile ]] && profile="${2:-}"
  require_deps jq awk
  [[ -f "$profile" ]] || { echo "off: no profile at $profile"; exit 1; }
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/delegate-policy.XXXXXX")" || exit 3
  STATE="$WORK/state"
  mkdir -p "$STATE"
  trap cleanup EXIT
  load_profile "$profile"
  policy="$(project_get policy)"
  approved="$(project_get activation_approved)"
  [[ -n "$policy" ]] || { echo "off: no [[project]] entry for this checkout"; exit 1; }
  [[ "$policy" == auto ]] || { echo "off: policy is '$policy'"; exit 1; }
  [[ "$approved" == true ]] || { echo "off: activation_approved is not true"; exit 1; }
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if (
      refuse() { exit 1; }
      load_model "$name"
      [[ "$(qualification_state "$name" "$FINGERPRINT")" == qualified ]]
    ); then
      qualified="${qualified:+$qualified, }$name"
    fi
  done <<<"$(toml_list "$(project_get candidates)")"
  [[ -n "$qualified" ]] || { echo "off: no candidate is qualified for its current setup"; exit 1; }
  echo "auto (qualified candidates: $qualified)"
}

cmd_reset() {
  local model="${1:-}" bucket="${2:-}"
  [[ -n "$model" && -n "$bucket" ]] || { say "usage: delegate-run.sh reset <model> <bucket>"; exit 2; }
  case "$bucket" in small | medium) ;; *) say "unknown bucket: $bucket"; exit 2 ;; esac
  require_deps jq
  mkdir -p "$DELEGATE_DIR"
  jq -c -n --arg ts "$(now_utc)" --arg model "$model" --arg bucket "$bucket" \
    '{type: "reset", ts: $ts, model: $model, bucket: $bucket}' >>"$DELEGATE_DIR/ledger.jsonl"
  say "reset '$model' for $bucket tasks; its record starts fresh"
}

require_deps() {
  local dep
  for dep in "$@"; do
    command -v "$dep" >/dev/null 2>&1 || { say "missing dependency: $dep"; exit 2; }
  done
}

case "${1:-}" in
  qualify) shift; cmd_qualify "$@" ;;
  run) shift; cmd_run "$@" ;;
  record-review) shift; cmd_record_review "$@" ;;
  discover) shift; cmd_discover "$@" ;;
  policy) shift; cmd_policy "$@" ;;
  status) shift; cmd_status "$@" ;;
  reset) shift; cmd_reset "$@" ;;
  -h | --help | "") usage; [[ -n "${1:-}" ]] ;;
  *) say "unknown subcommand: $1 (run with --help)"; exit 2 ;;
esac
