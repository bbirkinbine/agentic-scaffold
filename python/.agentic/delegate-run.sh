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
#   run <packet> [--model <name>] [--progress quiet|summary]
#                            Send <packet> to the named model, or without
#                            --model to the model selected from this
#                            project's [[project]] candidates. Up to three
#                            calls; each attempt starts from the same clean
#                            scratch snapshot. Retries carry the previous
#                            candidate and bounded failure output.
#   record-review <run> pass|model-defect|packet-defect
#                            Record /review's final verdict on a published
#                            candidate. Until then a green run is pending.
#                            Also records how many of the published lines
#                            (kept in results/<run>/candidate) review kept.
#   policy                   Prints `auto` and exits 0 only when this
#                            checkout's [[project]] entry has policy = "auto",
#                            activation_approved = true, and at least one
#                            qualified candidate; otherwise prints `off: <why>`
#                            and exits 1. With a profile but a missing
#                            dependency, exits 2. The orchestrator checks this
#                            before handing implementation to a local model.
#   activate | deactivate    Set this checkout's [[project]] entry to
#                            policy = "auto" with activation_approved = true
#                            (or back to "off"). Run only on the human's
#                            explicit yes; activate refuses unless a
#                            candidate is qualified. Prints before/after.
#   init [--key-env VAR] <base-url> ...
#                            Print a draft profile from what each server's
#                            /models lists: endpoints, one [[model]] per
#                            model with the fields to confirm marked, and a
#                            [[project]] entry for this checkout (policy off).
#                            Prints only; save it yourself after review. With
#                            an existing profile, prints only what is missing.
#                            --key-env names the variable holding the next
#                            URL's key.
#   discover                 What each endpoint's /models lists, matched to
#                            profile models and their qualification.
#   status                   Each profile model's qualification and its
#                            record per bucket in this project.
#   reset <model> <bucket>   Clear a demotion (small, medium, phase:implement,
#                            phase:test-first+implement); starts a fresh record.
#   handoff <spec> --allow-commit [--phase implement|test-first+implement]
#                            [--model <name>] [--progress quiet|summary]
#                            Hand a whole phase of an approved spec to a
#                            local agent session (Pi) in a new git worktree:
#                            install, run the session headless on the
#                            model, then verify the full gate and that only
#                            the plan's files changed (and, for `implement`,
#                            no test file). --allow-commit acknowledges the
#                            human's explicit approval for the temporary
#                            handoff-branch commit. A verified run is committed
#                            on `handoff/<run>` for the orchestrator to review
#                            and merge; scored per
#                            phase like a run. See docs/local-phase-handoff.md.
#   handoff-clean [<run-id> | --all]
#                            List handoff worktrees, or remove one (or all)
#                            with its handoff/ branch after merging or
#                            abandoning it.
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
#   [[model]]                              # pi_thinking: optional for handoff;
#   name = "coder-a"                       # provider/model come from this profile
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
#   handoff: 0 verified and committed on handoff/<run>; 10 the session ended
#   with the gate red; 4 out-of-plan or test-file changes; 3 harness crash,
#   timeout, install, or worktree failure; 2 refused.
#
# Requires: bash, git, curl, jq (1.6+), tar, perl (the step watchdog), and
# sha256sum or shasum.
#
# Progress is `summary` when stderr is a terminal and `quiet` otherwise.
# DELEGATE_PROGRESS_INTERVAL changes the 15-second heartbeat interval; it is
# primarily useful for deterministic smoke tests.

set -uo pipefail

HARNESS_VERSION="delegate-run-v1"
MAX_ATTEMPTS=3
# Ranking and demotion use the Wilson score interval (E. B. Wilson, JASA 22,
# 1927; see docs/influences.md in agentic-scaffold). Scoring and bucket
# parameters are unsourced starting points
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
PROGRESS_MODE=quiet
PROGRESS_INTERVAL="${DELEGATE_PROGRESS_INTERVAL:-15}"
PROGRESS_PID=""
PROGRESS_DONE=""
PROGRESS_PID_FILE=""

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 3
DELEGATE_DIR="$ROOT/.agentic/delegate"
TOOLCHAIN=.agentic/toolchain.sh

say() { printf 'delegate-run: %s\n' "$*" >&2; }
progress() { [[ "$PROGRESS_MODE" == summary ]] && say "progress: $*"; return 0; }

configure_progress() {
  local requested="${1:-}"
  if [[ -n "$requested" ]]; then
    case "$requested" in quiet | summary) PROGRESS_MODE="$requested" ;; *) say "unknown progress mode: $requested (quiet or summary)"; exit 2 ;; esac
  elif [[ -t 2 ]]; then
    PROGRESS_MODE=summary
  else
    PROGRESS_MODE=quiet
  fi
  [[ "$PROGRESS_INTERVAL" =~ ^[1-9][0-9]*$ ]] || { say "DELEGATE_PROGRESS_INTERVAL must be a positive whole number"; exit 2; }
}

stop_progress_sidecar() {
  if [[ -n "$PROGRESS_PID" ]]; then
    kill "$PROGRESS_PID" 2>/dev/null || true
    wait "$PROGRESS_PID" 2>/dev/null || true
    PROGRESS_PID=""
  fi
  [[ -n "$PROGRESS_PID_FILE" ]] && rm -f "$PROGRESS_PID_FILE"
  PROGRESS_PID_FILE=""
}

start_heartbeat() {
  local label="$1" started
  [[ "$PROGRESS_MODE" == summary ]] || return 0
  stop_progress_sidecar
  started="$(date +%s)"
  # One signal-aware process owns the timer; stopping it never waits for a
  # child `sleep` to finish and therefore cannot inflate model-call timing.
  perl -e '
    $SIG{TERM} = sub { exit 0 };
    my ($interval, $label, $started) = @ARGV;
    while (1) {
      select undef, undef, undef, $interval;
      my $elapsed = time - $started;
      print STDERR "delegate-run: progress: $label — ${elapsed}s elapsed\n";
    }
  ' "$PROGRESS_INTERVAL" "$label" "$started" &
  PROGRESS_PID=$!
}

# Keep summaries bounded and remove credential-shaped assignments before they
# reach the terminal. Raw Pi events remain in the ignored result directory.
bounded_progress_field() {
  printf '%s' "$1" | perl -MEncode=encode -CS -e '
    local $/;
    $_ = <STDIN> // "";
    s/[\r\n\t]/ /g;
    s/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/?/g;
    s/\b([A-Za-z0-9_]*(?:TOKEN|SECRET|PASSWORD|API[_-]?KEY)[A-Za-z0-9_]*=)(?:"[^"]*"|\047[^\047]*\047|\S+)/${1}[REDACTED]/ig;
    s/(Authorization:\s*(?:Bearer\s+)?)(\S+)/${1}[REDACTED]/ig;
    if (length(encode("UTF-8", $_)) <= 160) { print; exit 0 }
    my $out = "";
    for my $char (split //) {
      last if length(encode("UTF-8", $out . $char)) > 157;
      $out .= $char;
    }
    print $out, "...";
  '
}

render_pi_event() {
  local line="$1" type tool detail failed duration attempt maximum reason
  type="$(jq -r '.type // empty' <<<"$line" 2>/dev/null)" || return 0
  case "$type" in
    agent_start) progress "agent started" ;;
    agent_settled) progress "agent settled" ;;
    turn_start) progress "turn started" ;;
    tool_execution_start)
      tool="$(jq -r '.toolName // "unknown"' <<<"$line")"
      case "$tool" in
        read | edit | write) detail="$(jq -r '.args.path // .args.file_path // .args.filePath // empty' <<<"$line")" ;;
        bash) detail="$(jq -r '.args.command // empty' <<<"$line")" ;;
        *) detail="" ;;
      esac
      tool="$(bounded_progress_field "$tool")"
      if [[ -n "$detail" ]]; then
        progress "tool start: $tool — $(bounded_progress_field "$detail")"
      else
        progress "tool start: $tool"
      fi
      ;;
    tool_execution_end)
      tool="$(jq -r '.toolName // "unknown"' <<<"$line")"
      failed="$(jq -r 'if .isError == true then "failed" else "passed" end' <<<"$line")"
      duration="$(jq -r 'if (.durationMs | type) == "number" then " (" + (.durationMs | tostring) + "ms)" else "" end' <<<"$line")"
      progress "tool end: $(bounded_progress_field "$tool") — $failed$duration"
      ;;
    auto_retry_start)
      attempt="$(jq -r 'if (.attempt | type) == "number" then (.attempt | tostring) else "?" end' <<<"$line")"
      maximum="$(jq -r 'if (.maxAttempts | type) == "number" then (.maxAttempts | tostring) else "?" end' <<<"$line")"
      progress "retry $attempt/$maximum scheduled"
      ;;
    auto_retry_end)
      attempt="$(jq -r 'if (.attempt | type) == "number" then (.attempt | tostring) else "?" end' <<<"$line")"
      failed="$(jq -r 'if .success == true then "succeeded" else "failed" end' <<<"$line")"
      progress "retry $attempt $failed"
      ;;
    compaction_start)
      reason="$(jq -r '.reason // "unknown"' <<<"$line")"
      progress "compaction started ($(bounded_progress_field "$reason"))"
      ;;
    compaction_end)
      reason="$(jq -r '.reason // "unknown"' <<<"$line")"
      progress "compaction ended ($(bounded_progress_field "$reason"))"
      ;;
    message_end)
      reason="$(jq -r '.message.stopReason // empty' <<<"$line")"
      [[ "$reason" == error || "$reason" == aborted ]] && progress "assistant message ended: $reason"
      ;;
  esac
  return 0
}

watch_pi_events() {
  local events="$1" done_file="$2" started="$3" line now next pending=""
  exec 9<"$events"
  next=$((started + PROGRESS_INTERVAL))
  while :; do
    line=""
    if IFS= read -r line <&9; then
      render_pi_event "$pending$line"
      pending=""
      continue
    fi
    # `read` advances a regular-file descriptor even when EOF arrives before
    # LF. Keep that fragment and prepend it when the writer completes the line.
    pending+="$line"
    if [[ -e "$done_file" ]]; then
      # The harness closed the file before creating this marker, but it may
      # have appended after our previous EOF read. Drain once more before exit.
      while :; do
        line=""
        if IFS= read -r line <&9; then
          render_pi_event "$pending$line"
          pending=""
        else
          pending+="$line"
          break
        fi
      done
      break
    fi
    now="$(date +%s)"
    if ((now >= next)); then
      progress "session running — $((now - started))s elapsed"
      next=$((now + PROGRESS_INTERVAL))
    fi
    sleep 0.2
  done
  exec 9<&-
}

start_pi_event_watcher() {
  local events="$1" started="$2" pid_file="$3"
  [[ "$PROGRESS_MODE" == summary ]] || return 0
  PROGRESS_DONE="$STATE/progress.done"
  PROGRESS_PID_FILE="$pid_file"
  rm -f "$PROGRESS_DONE" "$PROGRESS_PID_FILE"
  watch_pi_events "$events" "$PROGRESS_DONE" "$started" &
  PROGRESS_PID=$!
  printf '%s\n' "$PROGRESS_PID" >"$PROGRESS_PID_FILE"
}

finish_pi_event_watcher() {
  [[ -n "$PROGRESS_PID" ]] || return 0
  : >"$PROGRESS_DONE"
  wait "$PROGRESS_PID" 2>/dev/null || true
  PROGRESS_PID=""
  rm -f "$PROGRESS_PID_FILE"
  PROGRESS_PID_FILE=""
  PROGRESS_DONE=""
}

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
# Process groups its descendants created (Pi runs each tool command in one)
# are outside that group, so they are collected before TERM and again before
# KILL and killed too. Where `ps` is unavailable (Codex's macOS sandbox
# denies it), only the command's own group is signalled.
STEP_TIMEOUT="${DELEGATE_STEP_TIMEOUT:-900}"

# `run` refuses without perl rather than run a verifier with no time limit.
bounded() {
  perl -e '
      my $limit = shift;
      my $pid = fork() // die "fork: $!";
      if ($pid == 0) { setpgrp(0, 0); exec { $ARGV[0] } @ARGV or exit 127; }
      my $own = getpgrp(0);
      my $groups = sub {
        my (%kids, %pgid, %seen, %found);
        open my $ps, "-|", "ps -axo pid=,ppid=,pgid= 2>/dev/null" or return ();
        while (<$ps>) {
          my ($p, $pp, $g) = split;
          next unless defined $g;
          push @{ $kids{$pp} }, $p;
          $pgid{$p} = $g;
        }
        close $ps;
        my @queue = ($pid);
        while (@queue) {
          my $p = shift @queue;
          next if $seen{$p}++;
          my $g = $pgid{$p};
          $found{$g} = 1 if $p != $pid && $g && $g != $pid && $g != $own;
          push @queue, @{ $kids{$p} || [] };
        }
        return keys %found;
      };
      local $SIG{ALRM} = sub {
        my %stray = map { $_ => 1 } $groups->();
        kill "TERM", -$pid; sleep 2;
        $stray{$_} = 1 for $groups->();
        kill "KILL", -$_ for keys %stray;
        kill "KILL", -$pid; waitpid($pid, 0);
        print STDERR "delegate-run: timed out after ${limit}s: @ARGV\n";
        exit 124;
      };
      alarm $limit;
      waitpid($pid, 0);
      exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
  ' "$STEP_TIMEOUT" "$@"
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

# assemble_sections <tree> <failure-log> : the mechanical packet sections a
# format-2 packet leaves to the runner, so the frontier model never spends
# output tokens copying files: the target as it exists now, the full test
# files, the live failure output, and the fixed output contract.
assemble_sections() {
  local tree="$1" log="$2" t
  printf '\n## The file as it exists now\n\n'
  if [[ -f "$tree/$TARGET" ]]; then
    printf '`%s`:\n\n````\n' "$TARGET"
    cat "$tree/$TARGET"
    printf '````\n'
  else
    printf 'NEW FILE: `%s` does not exist yet.\n' "$TARGET"
  fi
  printf '\n## The failing tests\n\nThese must pass. They are the specification.\n'
  while IFS= read -r t; do
    [[ -f "$tree/$t" ]] || continue
    printf '\n`%s`:\n\n````\n' "$t"
    cat "$tree/$t"
    printf '````\n'
  done <<<"$TESTS"
  printf '\n## The exact failure output\n\n````\n'
  # Color codes are noise to the model.
  sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g' "$log" | tail -n "$DIAG_LINES" | tail -c "$DIAG_BYTES"
  printf '````\n'
  printf '\n## Output contract\n\n> Return the complete final contents of `%s`, and nothing else. No\n> diff, no patch, no commentary, no markdown fence around the file, no\n> explanation of your changes.\n' "$TARGET"
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

# Qualification covers HTTP plumbing; handoff scores also identify the Pi
# harness and the exact generated provider configuration, without any key.
handoff_fingerprint() {
  local config thinking
  config="$(handoff_model_config)" || return 1
  thinking="$(profile_get model "$MODEL_NAME" pi_thinking)"
  FINGERPRINT="$(printf '%s\n' "$FINGERPRINT" "$HANDOFF_HARNESS" "$HANDOFF_HARNESS_VERSION" "$thinking" "$config" |
    "${SHA[@]}" | cut -c1-16)"
}

handoff_model_config() {
  local context thinking alias
  context="$(profile_get model "$MODEL_NAME" context)"
  context="${context:-32768}"
  [[ "$context" =~ ^[1-9][0-9]*$ ]] || { say "model '$MODEL_NAME': context must be a positive integer"; return 1; }
  alias="$(profile_get model "$MODEL_NAME" pi_model)"
  [[ -z "$alias" || "$alias" == "$ENDPOINT_NAME/$MODEL_ID" ]] || {
    say "model '$MODEL_NAME': remove pi_model; handoff uses its endpoint and model_id directly"; return 1;
  }
  thinking="$(profile_get model "$MODEL_NAME" pi_thinking)"
  jq -S -c -n --arg provider "$ENDPOINT_NAME" --arg url "$BASE_URL" --arg id "$MODEL_ID" \
    --arg key "${CRED_ENV:+\$$CRED_ENV}" --arg thinking "$thinking" --argjson context "$context" \
    --argjson request "$(request_extra)" '
    {providers: {($provider): {baseUrl: $url, api: "openai-completions",
      apiKey: (if $key == "" then "agentic-local" else $key end),
      models: [{id: $id, input: ["text"], contextWindow: $context,
        reasoning: ($thinking != "" and $thinking != "off"),
        samplingParams: $request}]}}}'
}

load_handoff_harness() {
  HANDOFF_HARNESS="${DELEGATE_HANDOFF_HARNESS:-pi}"
  command -v "$HANDOFF_HARNESS" >/dev/null 2>&1 || return 1
  HANDOFF_HARNESS_VERSION="$("$HANDOFF_HARNESS" --version 2>/dev/null | head -n 1)"
  [[ -n "$HANDOFF_HARNESS_VERSION" ]]
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
      if [[ "$BUCKET" == phase:* ]]; then handoff_fingerprint || refuse "invalid handoff model configuration"; fi
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
  if [[ "$BUCKET" == phase:* ]]; then handoff_fingerprint || refuse "invalid handoff model configuration"; fi
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
  local resp="$STATE/$label.response.json" err="$STATE/$label.curl.err" meta="$STATE/$label.curl.meta"
  local out curl_status=0 code detail
  detail="${label#attempt-}"
  [[ "$label" == attempt-* ]] && detail="attempt $detail/$MAX_ATTEMPTS"
  start_heartbeat "generating — $detail"
  if [[ -n "${CRED_ENV:-}" ]]; then
    # The header comes through a file descriptor so the credential never
    # appears in a process argument list.
    curl -sS --connect-timeout 10 --max-time "$TIMEOUT" \
      -H 'Content-Type: application/json' \
      -H @<(printf 'Authorization: Bearer %s\n' "${!CRED_ENV}") \
      --data-binary @"$req" -o "$resp" -w '%{http_code} %{time_total} %{time_connect}' \
      "$BASE_URL/chat/completions" >"$meta" 2>"$err" || curl_status=$?
  else
    curl -sS --connect-timeout 10 --max-time "$TIMEOUT" \
      -H 'Content-Type: application/json' \
      --data-binary @"$req" -o "$resp" -w '%{http_code} %{time_total} %{time_connect}' \
      "$BASE_URL/chat/completions" >"$meta" 2>"$err" || curl_status=$?
  fi
  stop_progress_sidecar
  out="$(cat "$meta" 2>/dev/null)"
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
  progress "response received — ${CALL_SECONDS}s"
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
LAST_STEPS=""
RUN_STARTED="$(date +%s)"
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
    # The exact first message the model received, for review attribution.
    [[ -n "$STATE" && -s "$STATE/packet-body.md" ]] &&
      cp "$STATE/packet-body.md" "$result_dir/prompt.md"
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
      --argjson wall "$(($(date +%s) - RUN_STARTED))" \
      '{type: "run", ts: $ts, run: $run, mode: $mode, selection: $selection, fingerprint: $fingerprint,
        qualified: $qualified, packet: $packet,
        packet_sha256: $packet_sha, target: $target, bucket: $bucket,
        snapshot_sha256: $snapshot, harness: $harness,
        model: {name: $model, model_id: $model_id, quant: $quant, runtime: $runtime,
                endpoint: $endpoint, request: $request},
        attempts: $attempts, outcome: $outcome, reason: $reason,
        gate: $gate, unverified_steps: ($unverified | split(" ") | map(select(. != ""))),
        wall_seconds: $wall,
        review: null}' \
      >"$result_dir/result.json"
    jq -c . "$result_dir/result.json" >>"$DELEGATE_DIR/ledger.jsonl"
    print_summary "$result_dir/result.json"
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

# The end-of-run summary: model, wall time, each attempt, and which gate
# steps passed or could not verify this file.
print_summary() {
  [[ -n "${MODEL_NAME:-}" ]] || return 0
  say "summary: $OUTCOME — '$MODEL_NAME' on $TARGET ($BUCKET), $(jq -r .wall_seconds "$1")s wall"
  jq -r '.attempts[] | "  attempt \(.attempt): \(.outcome), \(.seconds)s\(if .detail != "" then " — " + .detail else "" end)"' "$1" >&2
  if [[ -n "$LAST_STEPS" && -f "$LAST_STEPS" ]]; then
    local passed red
    passed="$(awk '$2 == 0 { printf "%s%s", sep, $1; sep = " " }' "$LAST_STEPS")"
    red="$(awk '$2 != 0 { printf "%s%s", sep, $1; sep = " " }' "$LAST_STEPS")"
    say "  gate steps passed: ${passed:-none}; red: ${red:-none}${UNVERIFIED:+ (red before the run too, so unverified: $UNVERIFIED)}"
  fi
}

cleanup() {
  stop_progress_sidecar
  [[ -n "$WORK" && "${DELEGATE_KEEP_SCRATCH:-0}" != 1 ]] && rm -rf "$WORK"
  [[ "$LOCKED" == 1 ]] && rmdir "$DELEGATE_DIR/lock" 2>/dev/null
  return 0
}

# ---- run ----------------------------------------------------------------------

cmd_run() {
  local packet="" profile progress_mode=""
  profile="$(default_profile)"
  MODEL_NAME=""
  while (($#)); do
    case "$1" in
      --model)
        (($# >= 2)) && [[ -n "$2" ]] || { say "--model requires a value"; exit 2; }
        MODEL_NAME="$2"; shift 2 ;;
      --profile)
        (($# >= 2)) && [[ -n "$2" ]] || { say "--profile requires a value"; exit 2; }
        profile="$2"; shift 2 ;;
      --progress)
        (($# >= 2)) && [[ -n "$2" ]] || { say "--progress requires a value"; exit 2; }
        progress_mode="$2"; shift 2 ;;
      -h | --help) usage; exit 0 ;;
      -*) say "unknown option: $1"; exit 2 ;;
      *) [[ -z "$packet" ]] || { say "one packet per run"; exit 2; }; packet="$1"; shift ;;
    esac
  done
  [[ -n "$packet" ]] || { say "usage: delegate-run.sh run <packet> [--model <name>] [--progress quiet|summary]"; exit 2; }
  configure_progress "$progress_mode"
  MODE=manual
  [[ -n "$MODEL_NAME" ]] || MODE=selected

  local dep
  for dep in git curl jq tar awk perl; do
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
  # format: 2 -> the runner adds the file, tests, failure output, and output
  # contract; older packets carry them and are sent as written.
  PACKET_FORMAT="$(awk -F'\t' '$1 == "format" { print $2; exit }' "$STATE/header.tsv")"
  TESTS="$(awk -F'\t' '$1 == "test_targets" { print $2 }' "$STATE/header.tsv")"
  local targets tests
  targets="$(awk -F'\t' '$1 == "targets" { print $2 }' "$STATE/header.tsv")"
  tests="$(awk -F'\t' '$1 == "test_targets" { print $2 }' "$STATE/header.tsv")"
  local declared_bucket contracts expected
  declared_bucket="$(awk -F'\t' '$1 == "bucket" { print $2; exit }' "$STATE/header.tsv")"
  expected="$(awk -F'\t' '$1 == "expected_lines" { print $2; exit }' "$STATE/header.tsv")"
  [[ "$expected" =~ ^[0-9]+$ ]] || expected=0
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
  # cannot land in a smaller bucket. A new file has no size yet, so the
  # packet's expected_lines stands in, and a declared bucket larger than the
  # counts give is kept (the frontier model's estimate of the finished file).
  local lines=0
  [[ -f "$ROOT/$TARGET" ]] && lines="$(wc -l <"$ROOT/$TARGET" | tr -d ' ')"
  ((expected > lines)) && lines="$expected"
  BUCKET="$(bucket_for "$lines" "$contracts")"
  [[ "$BUCKET" != too-large ]] ||
    refuse "target is $lines lines with $contracts contract items: larger than the medium bucket (<=$MEDIUM_LINES lines, <=$MEDIUM_CONTRACTS items)"
  case "$declared_bucket:$BUCKET" in
    "":* | small:small | medium:medium) ;;
    medium:small) BUCKET=medium ;;
    small:medium)
      refuse "packet says bucket 'small' but $lines lines with $contracts contract items make it 'medium'; fix the header and route by the corrected bucket" ;;
    *) refuse "packet has unknown bucket '$declared_bucket' (small or medium)" ;;
  esac

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
  mkdir -p "$DELEGATE_DIR/results/$RUN_ID"
  progress "run $RUN_ID — '$MODEL_NAME', $BUCKET; logs: ${DELEGATE_DIR#"$ROOT"/}/results/$RUN_ID/"

  # -- snapshot the workspace (tracked + unignored untracked, minus delegation state)
  list_files "$ROOT" >"$STATE/files.nul"
  manifest "$ROOT" "$STATE/files.nul" >"$STATE/workspace.manifest"
  SNAPSHOT_SHA="$(sha_file "$STATE/workspace.manifest")"
  (cd "$ROOT" && tar -cf - --null -T "$STATE/files.nul") | (cd "$TREE" && tar -xf -) ||
    infra "could not copy the workspace snapshot"
  git -C "$TREE" init -q || infra "could not initialize scratch listing"
  # Ignored dependency directories (node_modules, .venv) are not in the
  # snapshot; install them so typecheck and tests can verify the candidate.
  verify_cmd bash "$TOOLCHAIN" install >"$STATE/install.log" 2>&1 ||
    say "warning: '$TOOLCHAIN install' failed in the scratch copy; steps needing dependencies may stay red: $(bounded_tail "$STATE/install.log" | tail -n 2 | tr '\n' ' ')"

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
  if [[ "$PACKET_FORMAT" == 2 ]]; then
    assemble_sections "$TREE" "$STATE/baseline-test.log" >>"$STATE/packet-body.md"
  fi
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
    progress "extracting candidate"
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
    progress "verifying — format"
    verify_cmd bash "$TOOLCHAIN" format >"$STATE/attempt-$n.format.log" 2>&1 || status=$?
    local focused=0 regressed="" still_red="" step
    if [[ "$status" == 0 ]]; then
      progress "verifying — focused tests"
      verify_cmd bash "$TOOLCHAIN" test "${test_args[@]}" >"$STATE/attempt-$n.focused.log" 2>&1 || focused=$?
      progress "verifying — gate steps"
      run_steps "attempt-$n"
      LAST_STEPS="$STATE/attempt-$n.steps"
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
  progress "publishing — $TARGET"
  cp "$TREE/$TARGET" "$tmp" || infra "could not stage the candidate in the workspace"
  [[ -x "$ROOT/$TARGET" ]] && chmod +x "$tmp"
  mv -f "$tmp" "$ROOT/$TARGET" || infra "could not publish the candidate"
  # Keep the file as published, so record-review can measure what review
  # changed in it.
  mkdir -p "$DELEGATE_DIR/results/$RUN_ID"
  cp "$TREE/$TARGET" "$DELEGATE_DIR/results/$RUN_ID/candidate"

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
      --profile)
        (($# >= 2)) && [[ -n "$2" ]] || { say "--profile requires a value"; exit 2; }
        profile="$2"; shift 2 ;;
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
  # How much of the published file survived review: lines review removed
  # from it and lines review added, against the target as it is now.
  local cand="$DELEGATE_DIR/results/$run/candidate" target changes='null'
  target="$(jq -r .target <<<"$rec")"
  if [[ -f "$cand" && -f "$ROOT/$target" ]]; then
    local published removed added
    published="$(wc -l <"$cand" | tr -d ' ')"
    removed="$( (diff "$cand" "$ROOT/$target" || true) | grep -c '^<' || true)"
    added="$( (diff "$cand" "$ROOT/$target" || true) | grep -c '^>' || true)"
    changes="$(jq -c -n --argjson p "$published" --argjson r "$removed" --argjson a "$added" \
      '{published_lines: $p, kept_lines: ($p - $r), removed_lines: $r, added_lines: $a}')"
    say "review kept $((published - removed)) of $published published lines in $target, removed $removed, added $added"
  fi
  jq -c -n --arg ts "$(now_utc)" --arg run "$run" --arg verdict "$verdict" --argjson changes "$changes" \
    '{type: "review", ts: $ts, run: $run, verdict: $verdict, review_changes: $changes}' >>"$ledger"
  local model fingerprint bucket
  model="$(jq -r .model.name <<<"$rec")"
  fingerprint="$(jq -r .fingerprint <<<"$rec")"
  bucket="$(jq -r .bucket <<<"$rec")"
  say "recorded $verdict for $run"
  say "record for '$model', $(describe_score "$model" "$fingerprint" "$bucket")"
}

cmd_status() {
  local profile name state bucket has_handoff=0
  profile="$(default_profile)"
  if [[ "${1:-}" == --profile ]]; then
    (($# >= 2)) && [[ -n "$2" ]] || { say "--profile requires a value"; exit 2; }
    profile="$2"; shift 2
  fi
  (($# == 0)) || { say "usage: delegate-run.sh status [--profile <path>]"; exit 2; }
  require_deps jq awk
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/delegate-status.XXXXXX")" || exit 3
  STATE="$WORK/state"
  mkdir -p "$STATE"
  trap cleanup EXIT
  load_profile "$profile"
  load_handoff_harness && has_handoff=1
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    load_model "$name"
    state="$(qualification_state "$name" "$FINGERPRINT")"
    printf '%s (%s, setup %s): %s\n' "$name" "$MODEL_ID" "$FINGERPRINT" "$state"
    for bucket in small medium; do
      printf '  %s\n' "$(describe_score "$name" "$FINGERPRINT" "$bucket")"
    done
    if [[ "$has_handoff" == 1 ]] && handoff_fingerprint; then
      for bucket in phase:implement phase:test-first+implement; do
        printf '  %s\n' "$(describe_score "$name" "$FINGERPRINT" "$bucket")"
      done
    fi
  done <<<"$(profile_models)"
}

cmd_init() {
  local profile key_env="" url urls=() keys=()
  profile="$(default_profile)"
  while (($#)); do
    case "$1" in
      --key-env)
        (($# >= 2)) && [[ -n "$2" ]] || { say "--key-env requires a value"; exit 2; }
        key_env="$2"; shift 2 ;;
      --profile)
        (($# >= 2)) && [[ -n "$2" ]] || { say "--profile requires a value"; exit 2; }
        profile="$2"; shift 2 ;;
      -*) say "unknown option: $1"; exit 2 ;;
      *)
        [[ "$1" =~ ^https?://[^[:space:]]+$ ]] || { say "not an http(s) base URL: $1"; exit 2; }
        if [[ -n "$key_env" && ! "$key_env" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
          say "--key-env takes a variable name, never a key: $key_env"
          exit 2
        fi
        urls+=("${1%/}"); keys+=("$key_env"); key_env=""; shift ;;
    esac
  done
  ((${#urls[@]})) || { say "usage: delegate-run.sh init [--key-env VAR] <base-url> ..."; exit 2; }
  require_deps curl jq awk
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/delegate-init.XXXXXX")" || exit 3
  STATE="$WORK/state"
  mkdir -p "$STATE"
  trap cleanup EXIT
  PROFILE_TSV="$STATE/profile.tsv"
  : >"$PROFILE_TSV"
  [[ -f "$profile" ]] && profile_entries "$profile" >"$PROFILE_TSV"

  local i ep listing id name ctx models=() existing
  printf '# Draft for %s: review, edit, then save it yourself.\n' "$profile"
  printf '# Confirm quant and runtime (servers do not report them), delete models you\n'
  printf '# will not use, list your choices in candidates, then run: delegate-run.sh qualify <name>\n'
  for ((i = 0; i < ${#urls[@]}; i++)); do
    url="${urls[$i]}"
    ep="$(awk -F'\t' -v u="$url" '$1 == "endpoint" && $3 == "base_url" && $4 == u { print $2; exit }' "$PROFILE_TSV")"
    if [[ -n "$ep" ]]; then
      ep="$(awk -F'\t' -v i="$ep" '$1 == "endpoint" && $2 == i && $3 == "name" { print $4; exit }' "$PROFILE_TSV")"
      printf '\n# endpoint %s (%s) is already in the profile\n' "$ep" "$url"
    else
      ep="$(sed -E 's#^https?://##; s#/.*$##; s#[^A-Za-z0-9]+#-#g; s#-+$##' <<<"$url")"
      printf '\n[[endpoint]]\nname = "%s"\nbase_url = "%s"\n' "$ep" "$url"
      [[ -n "${keys[$i]}" ]] && printf 'credential_env = "%s"\n' "${keys[$i]}"
    fi
    listing="$STATE/listing-$i.json"
    CRED_ENV="${keys[$i]}"
    if [[ -n "$CRED_ENV" && -n "${!CRED_ENV:-}" ]]; then
      curl -sS --connect-timeout 5 --max-time 15 -o "$listing" \
        -H @<(printf 'Authorization: Bearer %s\n' "${!CRED_ENV}") "$url/models" 2>/dev/null
    else
      curl -sS --connect-timeout 5 --max-time 15 -o "$listing" "$url/models" 2>/dev/null
    fi
    if ! jq -e '.data | type == "array"' "$listing" >/dev/null 2>&1; then
      printf '# %s: no model listing (unreachable, or set %s)\n' "$url" "${CRED_ENV:-a key variable with --key-env}"
      continue
    fi
    while IFS=$'\t' read -r id ctx; do
      [[ -n "$id" ]] || continue
      existing="$(awk -F'\t' -v e="$ep" -v m="$id" '
        $1 == "model" && $3 == "endpoint" && $4 == e { ep[$2] = 1 }
        $1 == "model" && $3 == "model_id" && $4 == m { mid[$2] = 1 }
        END { for (k in ep) if (k in mid) { print "yes"; exit } }' "$PROFILE_TSV")"
      if [[ "$existing" == yes ]]; then
        printf '# model %s on %s is already in the profile\n' "$id" "$ep"
        continue
      fi
      name="$(sed -E 's#[^A-Za-z0-9]+#-#g; s#^-+|-+$##g' <<<"$id" | tr 'A-Z' 'a-z')"
      models+=("$name")
      printf '\n[[model]]\nname = "%s"\nendpoint = "%s"\nmodel_id = "%s"\n' "$name" "$ep" "$id"
      printf 'quant = "CONFIRM"\nruntime = "CONFIRM"\n'
      [[ "$ctx" =~ ^[0-9]+$ && "$ctx" -gt 0 ]] && printf 'context = %s\n' "$ctx"
      printf 'timeout_seconds = 3600   # one call: swap, load, thinking, reply\n'
      printf "request = '{\"max_tokens\": 65536}'   # pin sampling and reasoning here\n"
    done <<<"$(jq -r '.data[] | [.id, ((.meta.n_ctx // .meta.n_ctx_train // .context_length // "") | tostring)] | @tsv' "$listing")"
  done

  local here
  here="$(cd "$ROOT" && pwd -P)"
  if [[ -n "$(project_get root 2>/dev/null)" ]]; then
    printf '\n# [[project]] for %s is already in the profile\n' "$here"
  else
    printf '\n[[project]]\nroot = "%s"\npolicy = "off"   # "auto" with activation_approved = true lets Implement delegate\n' "$here"
    printf 'candidates = []   # e.g. [%s]\n' "$( ((${#models[@]})) && printf '"%s", ' "${models[@]:0:2}" | sed 's/, $//')"
  fi
}

cmd_discover() {
  local profile endpoint id name listing found candidates
  profile="$(default_profile)"
  if [[ "${1:-}" == --profile ]]; then
    (($# >= 2)) && [[ -n "$2" ]] || { say "--profile requires a value"; exit 2; }
    profile="$2"; shift 2
  fi
  (($# == 0)) || { say "usage: delegate-run.sh discover [--profile <path>]"; exit 2; }
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
  if [[ "${1:-}" == --profile ]]; then
    (($# >= 2)) && [[ -n "$2" ]] || { say "--profile requires a value"; exit 2; }
    profile="$2"; shift 2
  fi
  (($# == 0)) || { say "usage: delegate-run.sh policy [--profile <path>]"; exit 2; }
  # No profile means delegation is off; say so without needing jq.
  [[ -f "$profile" ]] || { echo "off: no profile at $profile"; exit 1; }
  require_deps jq awk
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

# project_index : the [[project]] occurrence number for this checkout, or empty.
project_index() {
  local here idx root
  here="$(cd "$ROOT" && pwd -P)"
  while IFS=$'\t' read -r idx root; do
    [[ -n "$root" && -d "$root" ]] || continue
    [[ "$(cd "$root" && pwd -P)" == "$here" ]] && { printf '%s\n' "$idx"; return 0; }
  done <<<"$(awk -F'\t' '$1 == "project" && $3 == "root" { print $2 "\t" $4 }' "$PROFILE_TSV")"
}

# activate | deactivate : set this checkout's policy in the profile. Run only
# on the human's explicit yes; activate refuses without a qualified candidate.
cmd_set_policy() {
  local want="$1" profile idx name qualified=""
  shift
  profile="$(default_profile)"
  if [[ "${1:-}" == --profile ]]; then
    (($# >= 2)) && [[ -n "$2" ]] || { say "--profile requires a value"; exit 2; }
    profile="$2"; shift 2
  fi
  (($# == 0)) || { say "usage: delegate-run.sh activate|deactivate [--profile <path>]"; exit 2; }
  require_deps jq awk
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/delegate-policy.XXXXXX")" || exit 3
  STATE="$WORK/state"
  mkdir -p "$STATE"
  trap cleanup EXIT
  load_profile "$profile"
  idx="$(project_index)"
  [[ -n "$idx" ]] || refuse "no [[project]] entry for $ROOT in $profile; add one (delegate-run.sh init prints a draft)"
  local policy approved
  if [[ "$want" == auto ]]; then
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
    [[ -n "$qualified" ]] || refuse "no candidate in this checkout's [[project]] entry is qualified; run qualify first"
    policy='"auto"'; approved=true
  else
    policy='"off"'; approved=false
  fi
  say "before: policy = $(project_get policy), activation_approved = $(project_get activation_approved)"
  local tmp="$profile.delegate-run.$$"
  awk -v idx="$idx" -v policy="$policy" -v approved="$approved" '
    function close_block() {
      if (inblock) {
        if (!seen_p) print "policy = " policy
        if (!seen_a) print "activation_approved = " approved
      }
      inblock = 0
    }
    /^[ \t]*\[\[project\]\]/ { close_block(); n++; if (n == idx) { inblock = 1; seen_p = 0; seen_a = 0 } print; next }
    /^[ \t]*\[/ { close_block(); print; next }
    inblock && /^[ \t]*policy[ \t]*=/ { print "policy = " policy; seen_p = 1; next }
    inblock && /^[ \t]*activation_approved[ \t]*=/ { print "activation_approved = " approved; seen_a = 1; next }
    { print }
    END { close_block() }
  ' "$profile" >"$tmp" || { rm -f "$tmp"; infra "could not stage updated profile"; }
  # A failed stat may still write stdout (GNU stat -f does). Keep only the
  # successful invocation's output before handing permissions to chmod.
  local permissions
  if ! permissions="$(stat -c %a "$profile" 2>/dev/null)"; then
    permissions="$(stat -f %Lp "$profile" 2>/dev/null)" || { rm -f "$tmp"; infra "could not read profile permissions"; }
  fi
  chmod "$permissions" "$tmp" && mv -f "$tmp" "$profile" ||
    { rm -f "$tmp"; infra "could not rewrite $profile"; }
  load_profile "$profile"
  say "after:  policy = $(project_get policy), activation_approved = $(project_get activation_approved)"
  if [[ "$want" == auto ]]; then
    say "qualified candidates: $qualified. Each run still picks its delegation mode (none, files, handoff)."
  fi
}

cmd_reset() {
  local model="${1:-}" bucket="${2:-}"
  [[ -n "$model" && -n "$bucket" ]] || { say "usage: delegate-run.sh reset <model> <bucket>"; exit 2; }
  case "$bucket" in small | medium | phase:implement | phase:test-first+implement) ;; *) say "unknown bucket: $bucket"; exit 2 ;; esac
  require_deps jq
  mkdir -p "$DELEGATE_DIR"
  jq -c -n --arg ts "$(now_utc)" --arg model "$model" --arg bucket "$bucket" \
    '{type: "reset", ts: $ts, model: $model, bucket: $bucket}' >>"$DELEGATE_DIR/ledger.jsonl"
  say "reset '$model' for $bucket tasks; its record starts fresh"
}

# ---- handoff: a whole phase to a local agent session ----------------------------

# plan_files <spec> : the backticked paths listed under "## Files to touch".
plan_files() {
  awk '/^## Files to touch/ { on = 1; next } on && /^## / { exit }
    on && /^- `/ { sub(/^- `/, ""); sub(/`.*/, ""); print }' "$1"
}

# is_test_path <path> : the stack-neutral test-file rule used by the
# implement phase (tests are the oracle there and must not change).
is_test_path() {
  [[ "$1" =~ (^|/)(tests?|__tests__|spec)/ || "$1" =~ [._-](test|spec)\.[A-Za-z0-9]+$ || "$1" =~ (^|/)test_[^/]*$ ]]
}

handoff_prompt() {
  local spec="$1" phase="$2" phases
  case "$phase" in
    implement) phases="implementation, then /review-check" ;;
    *) phases="/test-first, then implementation, then /review-check" ;;
  esac
  cat <<PROMPT
You are a local model implementing one phase of an approved spec in an isolated worktree. Spec: $spec. Its plan is approved; the spec, its standing decisions, and its clarified decisions are final inputs.

Run $phases, following AGENTS.md. Rules:
- Change only the files the plan lists under "## Files to touch", plus the spec's own phase-handoff note.$( [[ "$phase" == implement ]] && printf '\n- The tests already exist and are the oracle: do not edit, add, or delete any test file. If a test looks wrong, stop and say so in the handoff note.' )
- Do not use local delegation (.agentic/delegate-run.sh or /delegate) and pass no model override to any subagent.
- Do not commit, push, or change branches. Do not ask the human anything: no one is watching. Where the spec leaves a choice open, pick the option that keeps the approved plan intact and record it in the handoff note.
- Stop when /review-check is green, or when you are blocked. Before stopping, append a short "### After handoff" entry under "## Phase handoff" in the spec: what you did, any choice you made, and anything left red or blocked.
PROMPT
}

# Audit the complete final tree against the starting commit, including
# staged, unstaged, deleted, and untracked files. Run before and after the
# gate: verifiers can write files too. A session must not move HEAD.
audit_handoff() {
  local wt="$1" spec="$2" phase="$3" branch="$4" result_dir="$5" f
  [[ "$(git -C "$wt" rev-parse HEAD)" == "$SNAPSHOT_SHA" &&
    "$(git -C "$wt" symbolic-ref -q HEAD)" == "refs/heads/$branch" ]] ||
    integrity "the session or verifier committed or changed branches (worktree kept at $wt)"
  {
    git -C "$wt" diff --name-only --no-renames -z "$SNAPSHOT_SHA" -- || infra "could not diff handoff changes"
    git -C "$wt" ls-files --others --exclude-standard -z || infra "could not list untracked handoff changes"
  } >"$STATE/changed.nul"
  : >"$STATE/changed"
  while IFS= read -r -d '' f; do
    [[ "$f" != *$'\n'* ]] || integrity "a changed path contains a newline"
    printf '%s\n' "$f" >>"$STATE/changed"
  done <"$STATE/changed.nul"
  LC_ALL=C sort -u "$STATE/changed" >"$STATE/changed.sorted"
  mv "$STATE/changed.sorted" "$STATE/changed"
  : >"$STATE/outside"
  : >"$STATE/tests-touched"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ "$f" == "$spec" || "$f" == docs/specs/README.md ]] && continue
    grep -qxF "$f" "$STATE/plan-files" || printf '%s\n' "$f" >>"$STATE/outside"
    if [[ "$phase" == implement ]] && is_test_path "$f"; then printf '%s\n' "$f" >>"$STATE/tests-touched"; fi
  done <"$STATE/changed"
  jq -n --arg wt "$wt" --arg branch "$branch" --arg phase "$phase" --arg harness "$HANDOFF_HARNESS" \
    --arg harness_version "$HANDOFF_HARNESS_VERSION" --arg pi_model "$ENDPOINT_NAME/$MODEL_ID" \
    --rawfile changed "$STATE/changed" --rawfile outside "$STATE/outside" --rawfile tests "$STATE/tests-touched" \
    '{worktree: $wt, branch: $branch, phase: $phase, harness: $harness, harness_version: $harness_version,
      pi_model: $pi_model, changed: ($changed | split("\n") | map(select(. != ""))),
      outside_plan: ($outside | split("\n") | map(select(. != ""))),
      test_files_changed: ($tests | split("\n") | map(select(. != "")))}' >"$result_dir/handoff.json"
  [[ -s "$STATE/outside" ]] && integrity "changes outside the plan's files: $(tr '\n' ' ' <"$STATE/outside")(worktree kept at $wt)"
  [[ -s "$STATE/tests-touched" ]] && integrity "the implement phase changed test files: $(tr '\n' ' ' <"$STATE/tests-touched")(worktree kept at $wt)"
  return 0
}

cmd_handoff() {
  local spec="" phase=implement profile allow_commit=0 progress_mode=""
  profile="$(default_profile)"
  MODEL_NAME=""
  while (($#)); do
    case "$1" in
      --phase)
        (($# >= 2)) && [[ -n "$2" ]] || { say "--phase requires a value"; exit 2; }
        phase="$2"; shift 2 ;;
      --model)
        (($# >= 2)) && [[ -n "$2" ]] || { say "--model requires a value"; exit 2; }
        MODEL_NAME="$2"; shift 2 ;;
      --profile)
        (($# >= 2)) && [[ -n "$2" ]] || { say "--profile requires a value"; exit 2; }
        profile="$2"; shift 2 ;;
      --progress)
        (($# >= 2)) && [[ -n "$2" ]] || { say "--progress requires a value"; exit 2; }
        progress_mode="$2"; shift 2 ;;
      --allow-commit) allow_commit=1; shift ;;
      -h | --help) usage; exit 0 ;;
      -*) say "unknown option: $1"; exit 2 ;;
      *) [[ -z "$spec" ]] || { say "one spec per handoff"; exit 2; }; spec="$1"; shift ;;
    esac
  done
  [[ -n "$spec" ]] || { say "usage: delegate-run.sh handoff <spec> --allow-commit [--phase implement|test-first+implement] [--model <name>] [--progress quiet|summary]"; exit 2; }
  configure_progress "$progress_mode"
  case "$phase" in implement | test-first+implement) ;; *) say "unknown phase: $phase"; exit 2 ;; esac
  [[ "$allow_commit" == 1 ]] || {
    say "refused: handoff creates a temporary commit on handoff/<run>; obtain explicit current-chat commit approval, then pass --allow-commit"
    exit 2
  }
  MODE=manual
  [[ -n "$MODEL_NAME" ]] || MODE=selected
  require_deps git jq awk perl curl

  load_handoff_harness || { say "agent harness unavailable: ${DELEGATE_HANDOFF_HARNESS:-pi}"; exit 2; }
  git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { say "not a git work tree: $ROOT"; exit 2; }

  mkdir -p "$DELEGATE_DIR/results"
  if ! mkdir "$DELEGATE_DIR/lock" 2>/dev/null; then
    say "another run holds $DELEGATE_DIR/lock; remove it if no run is active"
    exit 2
  fi
  LOCKED=1
  trap cleanup EXIT

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/delegate-handoff.XXXXXX")" || infra "could not create scratch directory"
  STATE="$WORK/state"
  mkdir -p "$STATE"
  [[ -f "$ROOT/$spec" ]] || refuse "spec not found: $spec"
  case "$spec" in /* | *..*) refuse "spec path must be relative to the repository: $spec" ;; esac
  RUN_ID="handoff-$(basename "$spec" .md)-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  PACKET_REL="$spec"
  PACKET_SHA="$(sha_file "$ROOT/$spec")"
  TARGET="$spec"
  BUCKET="phase:$phase"

  # -- preconditions
  grep -q '^\*\*Status:\*\* shipping' "$ROOT/$spec" || refuse "spec status is not 'shipping' (the plan must be approved first)"
  grep -q '^## Approved implementation plan' "$ROOT/$spec" || refuse "spec has no '## Approved implementation plan'"
  plan_files "$ROOT/$spec" >"$STATE/plan-files"
  [[ -s "$STATE/plan-files" ]] || refuse "spec lists no files under '## Files to touch'"
  [[ -z "$(git -C "$ROOT" status --porcelain)" ]] || refuse "the working tree is not clean; commit or stash first (the worktree starts from HEAD)"

  # -- model
  load_profile "$profile"
  if [[ -n "$MODEL_NAME" ]]; then
    load_model "$MODEL_NAME"
    check_credential
    QUALIFIED="$(qualification_state "$MODEL_NAME" "$FINGERPRINT")"
    [[ "$QUALIFIED" == qualified ]] ||
      refuse "model '$MODEL_NAME' is $QUALIFIED for its current setup; run: delegate-run.sh qualify $MODEL_NAME"
    handoff_fingerprint || refuse "invalid handoff model configuration"
    [[ "$(score "$MODEL_NAME" "$FINGERPRINT" "$BUCKET" | cut -d' ' -f7)" != demoted ]] ||
      say "warning: '$MODEL_NAME' is demoted for $BUCKET tasks; this manual run is still scored"
  else
    select_model
  fi
  local pi_model pi_thinking
  pi_model="$ENDPOINT_NAME/$MODEL_ID"
  pi_thinking="$(profile_get model "$MODEL_NAME" pi_thinking)"

  # -- worktree
  local base wt branch
  base="${DELEGATE_HANDOFF_DIR:-${TMPDIR:-/tmp}/agentic-handoff}"
  mkdir -p "$base" || infra "could not create $base"
  wt="$base/$RUN_ID"
  branch="handoff/$RUN_ID"
  SNAPSHOT_SHA="$(git -C "$ROOT" rev-parse HEAD)"
  git -C "$ROOT" worktree add -q -b "$branch" "$wt" "$SNAPSHOT_SHA" >"$STATE/worktree.log" 2>&1 ||
    infra "could not create the worktree: $(bounded_tail "$STATE/worktree.log")"
  TREE="$wt"
  local result_dir="$DELEGATE_DIR/results/$RUN_ID"
  mkdir -p "$result_dir/session" "$result_dir/pi-agent"
  progress "handoff $RUN_ID — '$MODEL_NAME', $BUCKET; logs: ${result_dir#"$ROOT"/}/"
  handoff_model_config >"$result_dir/pi-agent/models.json" || refuse "invalid handoff model configuration"
  say "worktree: $wt (branch $branch)"

  verify_cmd bash "$TOOLCHAIN" install >"$result_dir/install.log" 2>&1 ||
    say "warning: '$TOOLCHAIN install' failed in the worktree; see ${result_dir#"$ROOT"/}/install.log"
  local ready=0
  verify_cmd bash "$TOOLCHAIN" ready >"$STATE/ready.log" 2>&1 || ready=$?
  ((ready == 0)) || refuse "the gate is not ready in the worktree ($TOOLCHAIN ready exited $ready); remove it with: git worktree remove --force $wt"
  if [[ "$phase" == implement ]] && verify_cmd bash "$TOOLCHAIN" test >"$STATE/baseline.log" 2>&1; then
    refuse "the tests already pass: nothing to implement (run test-first first, or use --phase test-first+implement); remove the worktree with: git worktree remove --force $wt"
  fi

  # -- session
  # A new worktree lacks the ignored .pi/npm/; reuse the checkout's installed
  # Pi packages so the session does not depend on the npm registry.
  if [[ -d "$ROOT/.pi/npm" && ! -e "$wt/.pi/npm" ]] && git -C "$wt" check-ignore -q .pi/npm/; then
    mkdir -p "$wt/.pi" && cp -R "$ROOT/.pi/npm" "$wt/.pi/npm" ||
      say "warning: could not copy .pi/npm/ into the worktree; Pi will install its packages"
  fi
  handoff_prompt "$spec" "$phase" >"$result_dir/prompt.md"
  local -a hargs=(-p --approve --provider "$ENDPOINT_NAME" --model "$MODEL_ID" --session-dir "$result_dir/session" --mode json)
  [[ -n "$pi_thinking" ]] && hargs+=(--thinking "$pi_thinking")
  local -a envkeep=(PATH="$PATH" HOME="$HOME" LANG="${LANG:-C.UTF-8}" TERM=dumb PI_CODING_AGENT_DIR="$result_dir/pi-agent")
  [[ -n "${TMPDIR:-}" ]] && envkeep+=(TMPDIR="$TMPDIR")
  [[ -n "${CRED_ENV:-}" ]] && envkeep+=("$CRED_ENV=${!CRED_ENV}")
  # Pi installs the packages in .pi/settings.json into the worktree's ignored
  # .pi/npm/ on start. Its npm cache stays in the run directory, which is
  # writable inside Codex's sandbox where ~/.npm is not.
  envkeep+=(npm_config_cache="$result_dir/npm-cache")
  local limit="${DELEGATE_HANDOFF_TIMEOUT:-14400}" started rc=0
  started="$(date +%s)"
  say "session: $HANDOFF_HARNESS on '$MODEL_NAME' ($pi_model), phase $phase, limit ${limit}s"
  : >"$result_dir/harness.events.jsonl"
  : >"$result_dir/harness.log"
  start_pi_event_watcher "$result_dir/harness.events.jsonl" "$started" "$result_dir/progress-renderer.pid"
  (cd "$wt" && STEP_TIMEOUT="$limit" bounded env -i "${envkeep[@]}" "$HANDOFF_HARNESS" "${hargs[@]}" "$(cat "$result_dir/prompt.md")") \
    >"$result_dir/harness.events.jsonl" 2>"$result_dir/harness.log" || rc=$?
  finish_pi_event_watcher
  record_attempt 1 session "harness exit $rc" "$(($(date +%s) - started))"
  ((rc == 124)) && infra "the session hit its ${limit}s limit; worktree kept at $wt"
  local harness_diag
  harness_diag="$(bounded_tail "$result_dir/harness.log" | tail -n 5)"
  [[ -n "$harness_diag" ]] || harness_diag="no stderr; see ${result_dir#"$ROOT"/}/harness.events.jsonl"
  ((rc == 0)) || infra "the harness exited $rc: $harness_diag"

  # -- verify, independently of what the session said
  progress "independently verifying — plan scope"
  audit_handoff "$wt" "$spec" "$phase" "$branch" "$result_dir"
  [[ -s "$STATE/changed" ]] || { OUTCOME=needs_frontier; REASON="the session changed nothing"; say "needs_frontier: $REASON"; finish 10; }
  local gate_status=0
  progress "independently verifying — full gate"
  verify_cmd bash "$TOOLCHAIN" gate >"$result_dir/gate.log" 2>&1 || gate_status=$?
  audit_handoff "$wt" "$spec" "$phase" "$branch" "$result_dir"
  if ((gate_status != 0)); then
    OUTCOME=needs_frontier
    REASON="the session ended with the gate red: $(bounded_tail "$result_dir/gate.log" | tail -n 5 | tr '\n' ' ')"
    say "needs_frontier: $REASON"
    say "worktree kept at $wt; read the spec's '### After handoff' note there"
    finish 10
  fi
  GATE_LEVEL=full

  git -C "$wt" add -A >/dev/null 2>&1 &&
    git -C "$wt" commit -q -m "Local handoff $RUN_ID ($phase on $MODEL_NAME)" >"$STATE/commit.log" 2>&1 ||
    infra "could not commit on $branch: $(bounded_tail "$STATE/commit.log")"
  OUTCOME=green
  REASON=""
  say "green: $phase verified (full gate, plan scope) and committed on $branch."
  say "Next: review the branch (git diff HEAD...$branch), then: git merge --squash $branch"
  say "  then: delegate-run.sh handoff-clean $RUN_ID"
  finish 0
}

# handoff-clean [<run-id> | --all] : remove handoff worktrees and their
# branches. A run id removes that one; --all removes every handoff worktree
# of this repository. Without either, lists them. Never touches the main
# working tree or any branch outside handoff/.
cmd_handoff_clean() {
  require_deps git awk
  local target="${1:-}" path branch removed=0
  git -C "$ROOT" worktree prune
  while IFS=$'\t' read -r path branch; do
    [[ "$branch" == handoff/* ]] || continue
    if [[ -z "$target" ]]; then
      printf '%s\t%s\n' "${branch#handoff/}" "$path"
      continue
    fi
    [[ "$target" == --all || "$target" == "${branch#handoff/}" ]] || continue
    git -C "$ROOT" worktree remove --force "$path" 2>/dev/null || rm -rf "$path"
    git -C "$ROOT" branch -D "$branch" >/dev/null 2>&1
    say "removed $branch ($path)"
    removed=$((removed + 1))
  done < <(git -C "$ROOT" worktree list --porcelain |
    awk '/^worktree / { p = substr($0, 10) } /^branch refs\/heads\// { print p "\t" substr($0, 19) }')
  # Branches whose worktree is already gone.
  if [[ -n "$target" ]]; then
    while IFS= read -r branch; do
      [[ -n "$branch" ]] || continue
      [[ "$target" == --all || "$target" == "${branch#handoff/}" ]] || continue
      git -C "$ROOT" branch -D "$branch" >/dev/null 2>&1 && { say "removed $branch"; removed=$((removed + 1)); }
    done < <(git -C "$ROOT" branch --list 'handoff/*' --format='%(refname:short)')
    git -C "$ROOT" worktree prune
    ((removed > 0)) || { say "no handoff worktree matches '$target'"; exit 2; }
  fi
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
  init) shift; cmd_init "$@" ;;
  discover) shift; cmd_discover "$@" ;;
  policy) shift; cmd_policy "$@" ;;
  status) shift; cmd_status "$@" ;;
  reset) shift; cmd_reset "$@" ;;
  handoff) shift; cmd_handoff "$@" ;;
  handoff-clean) shift; cmd_handoff_clean "$@" ;;
  activate) shift; cmd_set_policy auto "$@" ;;
  deactivate) shift; cmd_set_policy off "$@" ;;
  -h | --help | "") usage; [[ -n "${1:-}" ]] ;;
  *) say "unknown subcommand: $1 (run with --help)"; exit 2 ;;
esac
