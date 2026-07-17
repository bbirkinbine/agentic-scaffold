#!/usr/bin/env bash
# protect-main.sh — apply a branch-protection ruleset to the CURRENT repo's
# default branch, scaled to the repo's shape. This is the one-command version
# of the "Protect main" step in new-project-checklist.md; run it from inside
# the target repo (like bootstrap.sh), once, after the first push:
#
#   bash path/to/agentic-scaffold/scripts/protect-main.sh [options]
#
# It reads the repo's own state — no profile flag, nothing stored — and only
# applies what fits. See "Shape detection" below and the checklist's
# "Pick the smallest type that fits" philosophy: protection is the server-side
# teeth of "CI is the gate you cannot skip", so it belongs on GitHub-backed
# repos that have CI, and stays out of local-only / no-CI repos.
#
# Shape detection (each signal read live from the target repo):
#   1. Remote        — no GitHub repo resolvable  -> LOCAL-ONLY -> skip cleanly.
#   2. CI checks      — none found                -> PR + no-force-push only
#                                                    (required-status-checks
#                                                     omitted: nothing to require).
#                     — found                     -> also require those contexts.
#   3. Collaborators  — solo (<=1)                -> 0 required approvals,
#                                                    non-strict status checks.
#                     — team (>1)                 -> 1 approval, strict up-to-date.
#   4. Visibility     — private                   -> ruleset still created, but
#                                                    warns it stays dormant until
#                                                    public (and needs a paid plan
#                                                    to enforce on private repos).
#
# Flags override any detected value:
#   --team | --solo        force the collaborator shape
#   --strict | --no-strict force strict_required_status_checks_policy
#   --name NAME            ruleset name (default: protect-main)
#   --dry-run              print detected shape + the ruleset JSON, POST nothing
#   --yes                  skip the confirmation prompt (required non-interactively)
#   --force                update an existing ruleset of the same name instead of skipping
#
# Requires: gh (authenticated), git. jq optional (gh's built-in --jq is used).

set -euo pipefail

NAME=protect-main
DRY_RUN=0
ASSUME_YES=0
FORCE=0
TEAM_OVERRIDE=""     # "", team, solo
STRICT_OVERRIDE=""   # "", 1, 0

die() { echo "protect-main: $*" >&2; exit 1; }
note() { echo "protect-main: $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --team) TEAM_OVERRIDE=team ;;
    --solo) TEAM_OVERRIDE=solo ;;
    --strict) STRICT_OVERRIDE=1 ;;
    --no-strict) STRICT_OVERRIDE=0 ;;
    --name) shift; NAME="${1:?--name needs a value}" ;;
    --dry-run) DRY_RUN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

command -v gh  >/dev/null || die "gh (GitHub CLI) is required"
command -v git >/dev/null || die "git is required"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"

# --- Signal 1: is this a GitHub-backed repo? -------------------------------
# gh repo view resolves owner/repo from the current repo's remote. If it can't
# (no remote, not on GitHub, or not authenticated), the repo is effectively
# local-only for our purposes — there is nothing on a server to protect.
if ! REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || [ -z "$REPO" ]; then
  note "no GitHub repo resolvable from this directory (local-only or no remote)."
  note "branch protection is a server-side rule; nothing to do. Skipping."
  exit 0
fi
BRANCH="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)"
[ -n "$BRANCH" ] || die "could not determine the default branch for $REPO"

# --- Signal 4: visibility (used for the dormant-ruleset warning) -----------
PRIVATE="$(gh api "repos/$REPO" --jq '.private' 2>/dev/null || echo false)"

# --- Signal 3: solo vs team -> approvals + strict policy --------------------
if [ -n "$TEAM_OVERRIDE" ]; then
  SHAPE="$TEAM_OVERRIDE"
else
  COLLABS="$(gh api "repos/$REPO/collaborators" --jq 'length' 2>/dev/null || echo 1)"
  if [ "${COLLABS:-1}" -gt 1 ]; then SHAPE=team; else SHAPE=solo; fi
fi
if [ "$SHAPE" = team ]; then
  APPROVALS=1
  STRICT_DEFAULT=1
else
  # Solo: requiring >=1 approval would make merges impossible (you cannot
  # approve your own PR). Require a PR, but zero approvals.
  APPROVALS=0
  STRICT_DEFAULT=0
fi
# strict_required_status_checks_policy: require the PR branch be up to date
# before merge. On for teams (avoids merging around a stale base); off for
# solo (rebase-before-merge churn is pure friction with one author).
if [ -n "$STRICT_OVERRIDE" ]; then STRICT="$STRICT_OVERRIDE"; else STRICT="$STRICT_DEFAULT"; fi
[ "$STRICT" = 1 ] && STRICT_JSON=true || STRICT_JSON=false

# --- Signal 2: CI check contexts on the default branch ---------------------
# The required-status-check "context" is the check-run display name (for GitHub
# Actions, the job name). Read them off the tip of the default branch — the most
# reliable source, since it is what GitHub itself matched. If CI has not run yet
# (fresh repo), fall back to parsing job names out of the workflow files.
CONTEXTS="$(gh api "repos/$REPO/commits/$BRANCH/check-runs" \
              --jq '[.check_runs[].name] | unique | .[]' 2>/dev/null || true)"
if [ -z "$CONTEXTS" ]; then
  # Fallback: job names from any workflow yaml. Best-effort; check-runs is better.
  if compgen -G ".github/workflows/*.y*ml" >/dev/null 2>&1; then
    CONTEXTS="$(awk '
      /^jobs:[[:space:]]*$/ {injobs=1; next}
      injobs && /^[[:space:]]{2}[A-Za-z0-9_-]+:[[:space:]]*$/ {
        gsub(/[[:space:]]|:/,""); print; next
      }
      injobs && /^[A-Za-z]/ {injobs=0}
    ' .github/workflows/*.y*ml 2>/dev/null | sort -u)"
    [ -n "$CONTEXTS" ] && note "no CI run found yet; using workflow job names as check contexts (verify after first CI run)."
  fi
fi

# Build the required_status_checks array (empty -> omit the whole rule).
CONTEXTS_JSON=""
if [ -n "$CONTEXTS" ]; then
  while IFS= read -r ctx; do
    [ -z "$ctx" ] && continue
    esc="${ctx//\\/\\\\}"; esc="${esc//\"/\\\"}"
    CONTEXTS_JSON="$CONTEXTS_JSON${CONTEXTS_JSON:+,}{\"context\":\"$esc\"}"
  done <<< "$CONTEXTS"
fi

# --- Assemble the ruleset JSON ---------------------------------------------
RULES="{\"type\":\"pull_request\",\"parameters\":{\"required_approving_review_count\":$APPROVALS,\"dismiss_stale_reviews_on_push\":false,\"require_code_owner_review\":false,\"require_last_push_approval\":false,\"required_review_thread_resolution\":false}}"
if [ -n "$CONTEXTS_JSON" ]; then
  RULES="$RULES,{\"type\":\"required_status_checks\",\"parameters\":{\"strict_required_status_checks_policy\":$STRICT_JSON,\"required_status_checks\":[$CONTEXTS_JSON]}}"
fi
RULES="$RULES,{\"type\":\"non_fast_forward\"}"

BODY="{\"name\":\"$NAME\",\"target\":\"branch\",\"enforcement\":\"active\",\"conditions\":{\"ref_name\":{\"include\":[\"~DEFAULT_BRANCH\"],\"exclude\":[]}},\"rules\":[$RULES]}"

# --- Report the detected shape ---------------------------------------------
echo "protect-main: repo         $REPO (default branch: $BRANCH)"
echo "protect-main: visibility   $([ "$PRIVATE" = true ] && echo private || echo public)"
echo "protect-main: shape        $SHAPE  ->  required approvals: $APPROVALS, strict checks: $STRICT_JSON"
if [ -n "$CONTEXTS_JSON" ]; then
  echo "protect-main: CI checks    require: $(echo "$CONTEXTS" | paste -sd, -)"
else
  echo "protect-main: CI checks    none found  ->  PR + no-force-push only (required-status-checks omitted)"
fi

if [ "$DRY_RUN" = 1 ]; then
  echo "protect-main: --dry-run, ruleset JSON:"
  if command -v jq >/dev/null; then printf '%s' "$BODY" | jq .; else printf '%s\n' "$BODY"; fi
  exit 0
fi

# --- Idempotency: does a ruleset of this name already exist? ----------------
EXISTING_ID="$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name==\"$NAME\") | .id" 2>/dev/null | head -1 || true)"
if [ -n "$EXISTING_ID" ] && [ "$FORCE" != 1 ]; then
  note "a ruleset named '$NAME' already exists (id $EXISTING_ID). Re-run with --force to update it. Skipping."
  exit 0
fi

# --- Confirm (state-changing) ----------------------------------------------
if [ "$ASSUME_YES" != 1 ]; then
  if [ ! -t 0 ]; then die "non-interactive; pass --yes to apply (or --dry-run to preview)"; fi
  action=$([ -n "$EXISTING_ID" ] && echo "update" || echo "create")
  printf 'protect-main: %s ruleset "%s" on %s:%s? [y/N] ' "$action" "$NAME" "$REPO" "$BRANCH"
  read -r reply
  case "$reply" in y|Y|yes|YES) ;; *) note "aborted."; exit 0 ;; esac
fi

# --- Apply ------------------------------------------------------------------
if [ -n "$EXISTING_ID" ]; then
  printf '%s' "$BODY" | gh api -X PUT "repos/$REPO/rulesets/$EXISTING_ID" --input - >/dev/null
  note "updated ruleset '$NAME' (id $EXISTING_ID)."
else
  printf '%s' "$BODY" | gh api -X POST "repos/$REPO/rulesets" --input - >/dev/null
  note "created ruleset '$NAME'."
fi

if [ "$PRIVATE" = true ]; then
  note "NOTE: this repo is private. On the Free plan the ruleset does not enforce"
  note "until the repo is public; re-verify it after the public flip. See"
  note "new-project-checklist.md -> 'After flipping'."
fi
