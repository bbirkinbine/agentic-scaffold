#!/usr/bin/env bash
# Authenticated behavioral parity check for the Medium Python workflow.
#
# This is deliberately manual: it calls both paid AI clients several times.
# It creates the same temporary fixture for each client, then proves artifacts
# and diffs instead of trusting either model's claim that it followed the loop.
#
# Usage:
#   bash scripts/acceptance-workflow-live.sh --confirm-token-use
#
# Optional:
#   --client claude|codex|both   (default: both)
#   CLAUDE_PHASE_BUDGET_USD=2    (maximum for each Claude phase)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENTS="both"
CONFIRMED=0

while (($#)); do
  case "$1" in
    --confirm-token-use) CONFIRMED=1 ;;
    --client)
      shift
      CLIENTS="${1:-}"
      ;;
    -h | --help)
      sed -n '2,13p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

[[ "$CONFIRMED" == 1 ]] || {
  echo "Refusing to spend model tokens without --confirm-token-use." >&2
  exit 2
}
case "$CLIENTS" in
  claude | codex | both) ;;
  *)
    echo "ERROR: --client must be claude, codex, or both" >&2
    exit 1
    ;;
esac

command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 is required" >&2
  exit 1
}
command -v uv >/dev/null 2>&1 || {
  echo "ERROR: uv is required" >&2
  exit 1
}

TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN=timeout
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN=gtimeout
else
  echo "ERROR: GNU timeout is required (brew install coreutils on macOS)" >&2
  exit 1
fi

if [[ "$CLIENTS" == claude || "$CLIENTS" == both ]]; then
  command -v claude >/dev/null 2>&1 || {
    echo "ERROR: Claude Code CLI is not installed" >&2
    exit 1
  }
  if [[ -z "${ANTHROPIC_API_KEY:-}" ]] &&
    ! claude auth status 2>/dev/null \
      | python3 -c 'import json,sys; assert json.load(sys.stdin)["loggedIn"]'; then
    echo "ERROR: Claude Code is not authenticated" >&2
    exit 1
  fi
fi
if [[ "$CLIENTS" == codex || "$CLIENTS" == both ]]; then
  command -v codex >/dev/null 2>&1 || {
    echo "ERROR: Codex CLI is not installed" >&2
    exit 1
  }
  codex login status >/dev/null 2>&1 || {
    echo "ERROR: Codex CLI is not authenticated" >&2
    exit 1
  }
fi

WORK_DIR="$(mktemp -d)"
PRESERVE_WORK=0
cleanup() {
  if [[ "$PRESERVE_WORK" == 1 ]]; then
    echo "Preserved failure evidence under: $WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT
BASE_DIR="$WORK_DIR/base"
RESULTS_DIR="$WORK_DIR/results"
mkdir -p "$BASE_DIR" "$RESULTS_DIR"

fail() {
  PRESERVE_WORK=1
  echo "WORKFLOW LIVE ACCEPTANCE FAIL: $*" >&2
  exit 1
}

snapshot_workspace() {
  local project="$1"
  local output="$2"
  (
    cd "$project"
    git status --short
    git diff --binary
    while IFS= read -r path; do
      printf 'UNTRACKED %s %s\n' \
        "$(git hash-object --no-filters -- "$path")" "$path"
    done < <(git ls-files --others --exclude-standard | LC_ALL=C sort)
  ) >"$output"
}

assert_changed_subset() {
  local project="$1"
  shift
  local path allowed
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    allowed=0
    for pattern in "$@"; do
      # shellcheck disable=SC2254 # callers intentionally pass path globs
      case "$path" in
        $pattern) allowed=1 ;;
      esac
    done
    [[ "$allowed" == 1 ]] || fail "unexpected changed path: $path"
  done < <(
    cd "$project"
    {
      git diff --name-only
      git ls-files --others --exclude-standard
    } | LC_ALL=C sort -u
  )
}

run_client() {
  local client="$1"
  local mode="$2"
  local project="$3"
  local output="$4"
  local prompt="$5"
  local budget="${CLAUDE_PHASE_BUDGET_USD:-2}"

  if [[ "$client" == claude ]]; then
    (
      cd "$project"
      "$TIMEOUT_BIN" 600 claude -p \
        --setting-sources project \
        --permission-mode "$mode" \
        --output-format text \
        --no-session-persistence \
        --max-budget-usd "$budget" \
        "$prompt"
    ) >"$output" 2>&1
  else
    local canonical_project sandbox=workspace-write trust_override
    [[ "$mode" == plan ]] && sandbox=read-only
    canonical_project="$(cd "$project" && pwd -P)" \
      || fail "cannot resolve fixture path: $project"
    [[ "$canonical_project" == /* && "$canonical_project" != *['"\']* ]] \
      || fail "fixture path cannot be represented safely in a TOML trust override: $canonical_project"
    trust_override="projects={\"$canonical_project\"={trust_level=\"trusted\"}}"
    "$TIMEOUT_BIN" 600 codex \
      -c "$trust_override" \
      --strict-config \
      --ask-for-approval never \
      --sandbox "$sandbox" \
      --dangerously-bypass-hook-trust \
      exec --ignore-user-config --ephemeral --cd "$canonical_project" \
      --output-last-message "$output" \
      "$prompt" >"$output.log" 2>&1
  fi
}

assert_codex_subagents_started() {
  local client="$1" project="$2"
  shift 2
  [[ "$client" == codex ]] || return 0

  local log="$project/.agentic/acceptance-subagent-start.jsonl"
  if ! python3 - "$log" "$@" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
expected = set(sys.argv[2:])
seen = set()
for line in path.read_text().splitlines():
    payload = json.loads(line)
    if payload.get("hook_event_name") == "SubagentStart":
        agent_type = payload.get("agent_type")
        if isinstance(agent_type, str):
            seen.add(agent_type)

missing = sorted(expected - seen)
if missing:
    raise SystemExit(
        f"missing SubagentStart event(s) for {', '.join(missing)}; "
        f"captured agent types: {', '.join(sorted(seen)) or '<none>'}"
    )
PY
  then
    fail "$client did not load and start the expected project agent(s)"
  fi

  # Restore the committed empty capture file before workspace assertions.
  : >"$log"
}

# Build one committed fixture, then copy it byte-for-byte for both clients.
(
  cd "$BASE_DIR"
  bash "$REPO_DIR/python/bootstrap.sh" --python-core --no-stop-gate >/dev/null
  mv 'src/{{PACKAGE_NAME}}' src/shop
)
cat >"$BASE_DIR/.agentic/hooks/capture-subagent-start.sh" <<'EOF'
#!/usr/bin/env bash
# Acceptance-only proof that trusted project hooks and named agents both loaded.

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
payload="$(cat)"
printf '%s\n' "$payload" >>"$root/.agentic/acceptance-subagent-start.jsonl"
EOF
chmod +x "$BASE_DIR/.agentic/hooks/capture-subagent-start.sh"
: >"$BASE_DIR/.agentic/acceptance-subagent-start.jsonl"
python3 - "$BASE_DIR/.codex/hooks.json" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
config = json.loads(path.read_text())
config["hooks"]["SubagentStart"] = [
    {
        "hooks": [
            {
                "type": "command",
                "command": (
                    'bash "$(git rev-parse --show-toplevel)/'
                    '.agentic/hooks/capture-subagent-start.sh"'
                ),
            }
        ]
    }
]
path.write_text(json.dumps(config, indent=2) + "\n")
PY
python3 - "$BASE_DIR" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
replacements = {
    "{{PROJECT_NAME}}": "acceptance-shop",
    "{{PACKAGE_NAME}}": "shop",
    "{{ENTRY_POINT}}": "shop",
    "{{ONE_PARAGRAPH_DESCRIPTION}}": "A disposable workflow parity fixture.",
    "{{YYYY-MM-DD}}": "2026-07-30",
    "{{WHAT_IS_IN_PROGRESS_OR_BLOCKED}}": "Spec 0001 is the acceptance feature.",
    "{{WHAT_THE_NEXT_SPEC_IS — e.g., \"Spec for the next feature lives at `docs/specs/0001-<feature>.md`\"}}": "Spec 0001 is active.",
}
for relative in ("AGENTS.md", "README.md", "pyproject.toml", "src/shop/__init__.py"):
    path = root / relative
    text = path.read_text()
    for old, new in replacements.items():
        text = text.replace(old, new)
    text = re.sub(r"\{\{[^{}\n]+\}\}", "acceptance fixture", text)
    path.write_text(text)
PY

cat >"$BASE_DIR/src/shop/pricing.py" <<'PY'
"""Pricing primitives for the acceptance fixture."""


def bulk_discount_percent(quantity: int) -> int:
    """Return the percentage discount for a quantity."""
    raise NotImplementedError
PY
cat >"$BASE_DIR/src/shop/cart.py" <<'PY'
"""Cart totals for the acceptance fixture."""


def bulk_total(unit_price_cents: int, quantity: int) -> int:
    """Return a bulk-priced cart total in cents."""
    raise NotImplementedError
PY
cat >"$BASE_DIR/src/shop/__init__.py" <<'PY'
"""Public package surface for the acceptance fixture."""
PY
mkdir -p "$BASE_DIR/docs"
cat >"$BASE_DIR/docs/usage.md" <<'MD'
# Usage

Bulk pricing is not implemented yet.
MD
cat >"$BASE_DIR/docs/specs/0001-bulk-discount.md" <<'MD'
# Bulk discount

**Status:** draft
**Last updated:** 2026-07-30

## Goal

Add deterministic integer-cent bulk pricing without adding a dependency.

## Success criteria

- `bulk_discount_percent(quantity)` returns 0 below 10 and 10 at or above 10.
- Negative quantity raises `ValueError`.
- `bulk_total(unit_price_cents, quantity)` applies that percentage using
  integer arithmetic; negative price raises `ValueError`.
- Both functions are exported by `shop`, tested at the threshold and error
  boundaries, and documented in `docs/usage.md`.

## Non-goals

- Fractional cents, coupons, persistence, network calls, or a new dependency.

## External references

- None. This is fixture-local behavior.
MD
(
  cd "$BASE_DIR"
  uv sync >/dev/null
  rm -rf .venv
  bash .agentic/hooks/specs-status.sh
  git init -q
  git config user.email acceptance@example.invalid
  git config user.name "Workflow Acceptance"
  git add .
  git commit -qm "Create acceptance fixture"
  git switch -qc spec-0001-bulk-discount
)

run_acceptance() {
  local client="$1"
  local project="$WORK_DIR/$client"
  local phase_dir="$RESULTS_DIR/$client"
  local entry_prefix test_output review_before review_after
  mkdir -p "$phase_dir"
  cp -R "$BASE_DIR" "$project"

  if [[ "$client" == claude ]]; then
    entry_prefix="/"
  else
    entry_prefix='$'
  fi

  run_client "$client" plan "$project" "$phase_dir/plan.txt" \
    "Invoke ${entry_prefix}plan docs/specs/0001-bulk-discount.md. Be read-only. The plan must name src/shop/pricing.py, src/shop/cart.py, src/shop/__init__.py, tests/test_bulk_discount.py, and docs/usage.md; include risks and explicit out-of-scope work; then stop for approval." \
    || fail "$client plan command failed"
  assert_codex_subagents_started "$client" "$project" planner
  [[ -z "$(git -C "$project" status --short)" ]] \
    || fail "$client plan changed the workspace"
  for expected in pricing.py cart.py test_bulk_discount.py; do
    grep -qi "$expected" "$phase_dir/plan.txt" \
      || fail "$client plan omitted $expected"
  done
  grep -Eqi 'out[- ]of[- ]scope' "$phase_dir/plan.txt" \
    || fail "$client plan omitted explicit out-of-scope work"

  python3 - "$project/docs/specs/0001-bulk-discount.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text().replace("**Status:** draft", "**Status:** shipping")
text += """

## Approved implementation plan

**Approved:** 2026-07-30

1. Add boundary and error tests in `tests/test_bulk_discount.py`.
2. Implement the discount rule in `src/shop/pricing.py`.
3. Apply it in `src/shop/cart.py` with integer arithmetic.
4. Export both functions from `src/shop/__init__.py`.
5. Update `docs/usage.md`; run Ruff, mypy, and pytest; review without commit.
"""
path.write_text(text)
PY
  cp "$project/docs/specs/0001-bulk-discount.md" \
    "$phase_dir/approved-spec.md"

  run_client "$client" acceptEdits "$project" "$phase_dir/test-first.txt" \
    "Invoke ${entry_prefix}test-first docs/specs/0001-bulk-discount.md. Follow the approved plan. Change only tests/test_bulk_discount.py, independently run that focused test, require a NotImplementedError red result, and stop without editing src, docs, configuration, or the spec." \
    || fail "$client test-first command failed"
  assert_codex_subagents_started "$client" "$project" test-first
  [[ -f "$project/tests/test_bulk_discount.py" ]] \
    || fail "$client test-first did not create the required test"
  cmp -s "$project/docs/specs/0001-bulk-discount.md" \
    "$phase_dir/approved-spec.md" \
    || fail "$client test-first changed the approved spec"
  [[ -z "$(git -C "$project" diff --name-only -- src docs/usage.md)" ]] \
    || fail "$client test-first edited implementation or user docs"
  assert_changed_subset "$project" \
    'docs/specs/0001-bulk-discount.md' 'tests/*'
  test_output="$phase_dir/red.txt"
  if (cd "$project" && uv run pytest tests/test_bulk_discount.py -q) \
    >"$test_output" 2>&1; then
    fail "$client test-first phase was green before implementation"
  fi
  grep -q 'NotImplementedError' "$test_output" \
    || fail "$client red phase failed for the wrong reason"

  run_client "$client" acceptEdits "$project" "$phase_dir/implement.txt" \
    "Implement only docs/specs/0001-bulk-discount.md and its approved plan. Make the focused tests green, export the public functions, update docs/usage.md, mark the spec shipped, regenerate docs/specs/README.md, and do not add dependencies, change workflow scaffolding, commit, push, or broaden scope." \
    || fail "$client implementation command failed"
  assert_changed_subset "$project" \
    'docs/specs/0001-bulk-discount.md' 'docs/specs/README.md' 'docs/usage.md' \
    'src/shop/__init__.py' 'src/shop/pricing.py' 'src/shop/cart.py' 'tests/*'
  grep -qi 'bulk' "$project/docs/usage.md" \
    || fail "$client implementation did not document bulk pricing"
  grep -q 'Status:\*\* shipped' "$project/docs/specs/0001-bulk-discount.md" \
    || fail "$client implementation did not close the spec on-branch"
  grep -q 'bulk-discount.md.*shipped' "$project/docs/specs/README.md" \
    || fail "$client implementation did not refresh the spec dashboard"
  (
    cd "$project"
    uv run ruff check .
    uv run ruff format --check .
    uv run mypy src/
    uv run pytest -q
  ) >"$phase_dir/gate.txt" 2>&1 \
    || fail "$client implementation failed the real quality gate"

  review_before="$phase_dir/review-before.snapshot"
  review_after="$phase_dir/review-after.snapshot"
  snapshot_workspace "$project" "$review_before"
  run_client "$client" plan "$project" "$phase_dir/review.txt" \
    "Invoke ${entry_prefix}review docs/specs/0001-bulk-discount.md and then ${entry_prefix}review-adversarial docs/specs/0001-bulk-discount.md. Stay read-only. Inspect committed, staged, unstaged, and untracked work. Return sections titled Collaborative review and Adversarial review. If clear, include an explicit [no-op] disposition; otherwise use the required finding tags. Do not commit." \
    || fail "$client review command failed"
  assert_codex_subagents_started \
    "$client" "$project" reviewer reviewer-adversarial
  snapshot_workspace "$project" "$review_after"
  cmp -s "$review_before" "$review_after" \
    || fail "$client review changed the workspace"
  grep -qi 'Collaborative review' "$phase_dir/review.txt" \
    || fail "$client omitted collaborative review output"
  grep -qi 'Adversarial review' "$phase_dir/review.txt" \
    || fail "$client omitted adversarial review output"
  grep -Fq '[no-op]' "$phase_dir/review.txt" \
    || fail "$client reviews did not return a clear no-op disposition"
  if grep -Eq '\[(auto-fix|ask-user)\]' "$phase_dir/review.txt"; then
    fail "$client fixture still has an unresolved review finding"
  fi
  [[ "$(git -C "$project" rev-list --count HEAD)" == 1 ]] \
    || fail "$client committed during the workflow"

  echo "PASS: $client completed plan → test-only red → scoped green → read-only reviews"
}

case "$CLIENTS" in
  claude) run_acceptance claude ;;
  codex) run_acceptance codex ;;
  both)
    run_acceptance claude
    run_acceptance codex
    ;;
esac

echo "Workflow live acceptance OK: $CLIENTS"
