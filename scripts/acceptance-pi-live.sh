#!/usr/bin/env bash
# Opt-in authenticated Pi acceptance harness. It spends model tokens and is
# deliberately excluded from CI. The fixture is disposable and uses its own
# Git repository; no project changes are committed here.
set -euo pipefail

if [[ "${1:-}" != "--confirm-token-use" ]]; then
  echo "Usage: $0 --confirm-token-use" >&2
  exit 2
fi
command -v pi >/dev/null 2>&1 || { echo "pi is required" >&2; exit 1; }
[[ "$(pi --version)" == 1.0.4 ]] || { echo "Pi 1.0.4 is required" >&2; exit 1; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
PROJECT="$WORK/project"
SESSION="$WORK/pi-session.jsonl"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$PROJECT"
git -C "$PROJECT" init -q -b main

fail() {
  echo "PI ACCEPTANCE FAIL: $*" >&2
  exit 1
}

snapshot_workspace() {
  local output="$1"
  (
    cd "$PROJECT"
    git status --short --untracked-files=all
    git diff --binary
    git diff --cached --binary
    while IFS= read -r path; do
      printf 'UNTRACKED %s %s\n' \
        "$(git hash-object --no-filters -- "$path")" "$path"
    done < <(git ls-files --others --exclude-standard | LC_ALL=C sort)
  ) >"$output"
}

snapshot_non_test_workspace() {
  local output="$1"
  (
    cd "$PROJECT"
    git status --short --untracked-files=all -- . ':(exclude)tests/**'
    git diff --binary -- . ':(exclude)tests/**'
    git diff --cached --binary -- . ':(exclude)tests/**'
    while IFS= read -r path; do
      case "$path" in
        tests/*) continue ;;
      esac
      printf 'UNTRACKED %s %s\n' \
        "$(git hash-object --no-filters -- "$path")" "$path"
    done < <(git ls-files --others --exclude-standard | LC_ALL=C sort)
  ) >"$output"
}

assert_changed_subset() {
  local path allowed pattern
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
    cd "$PROJECT"
    {
      git diff --name-only
      git diff --cached --name-only
      git ls-files --others --exclude-standard
    } | LC_ALL=C sort -u
  )
}

run_pi() {
  local label="$1" prompt="$2"
  local output="$WORK/$label.out"
  (
    cd "$PROJECT"
    pi --approve --session "$SESSION" --print "$prompt" >"$output"
  )
  [[ -s "$output" ]] || fail "$label produced no output"
}

(
  cd "$PROJECT"
  bash "$REPO_DIR/python/bootstrap.sh" --minimal >/dev/null
  mv 'src/{{PACKAGE_NAME}}' src/piacceptance
  python3 - <<'PY'
from pathlib import Path

for path in Path('.').rglob('*'):
    if not path.is_file() or '.git' in path.parts:
        continue
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        continue
    path.write_text(text.replace('{{PROJECT_NAME}}', 'pi-acceptance')
                        .replace('{{PACKAGE_NAME}}', 'piacceptance'))
PY
  cat >docs/specs/0001-greeting.md <<'SPEC'
# 0001 — Greeting helper

**Status:** draft
**Last updated:** 2026-10-06

## Goal

Add a typed `greet(name: str) -> str` helper to `src/piacceptance/__init__.py`.

## Success criteria

- `greet("Pi")` returns exactly `"Hello, Pi!"`.
- A focused automated test covers the behavior.

## Non-goals

- CLI or network behavior.
SPEC
  .agentic/toolchain.sh install >/dev/null
  git config user.email smoke@example.com
  git config user.name "Pi Acceptance"
  git add -A
  git commit -q -m 'Seed Pi acceptance fixture'
)

# One-shot approval is machine-checkable. The normal interactive trust prompt
# and /reload remain a documented manual check.
package_list="$(cd "$PROJECT" && pi list --approve)"
grep -Fq 'npm:pi-subagents@0.76.1 (filtered)' <<<"$package_list" \
  || fail "trusted project package did not load in filtered extension-only mode"

# Prompt-template expansion plus a named read-only planner child. Prove the
# complete workspace is unchanged before recording human approval ourselves.
snapshot_workspace "$WORK/before-plan.fingerprint"
if [[ -f "$SESSION" ]]; then
  plan_offset="$(wc -c <"$SESSION")"
else
  plan_offset=0
fi
run_pi plan '/plan docs/specs/0001-greeting.md'
python3 - "$SESSION" "$plan_offset" "$WORK/plan-session-delta.jsonl" <<'PY'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_bytes()
Path(sys.argv[3]).write_bytes(source[int(sys.argv[2]):])
PY
grep -Fq '"toolName":"subagent"' "$WORK/plan-session-delta.jsonl" \
  || fail "plan did not invoke the subagent tool"
grep -Fq '"agent":"planner"' "$WORK/plan-session-delta.jsonl" \
  || fail "plan did not invoke the project planner role"
snapshot_workspace "$WORK/after-plan.fingerprint"
cmp -s "$WORK/before-plan.fingerprint" "$WORK/after-plan.fingerprint" \
  || fail "read-only planner changed the workspace"
{
  printf '\n## Approved implementation plan\n\n'
  cat "$WORK/plan.out"
} >>"$PROJECT/docs/specs/0001-greeting.md"
python3 - "$PROJECT/docs/specs/0001-greeting.md" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
p.write_text(p.read_text().replace('**Status:** draft', '**Status:** shipping'))
PY

# Test-first must use the named writer role, change only tests, independently
# produce a cause-specific red result, and leave the complete non-test
# workspace unchanged. The child loads the child-only lifecycle entry point.
snapshot_non_test_workspace "$WORK/before-test-first.fingerprint"
test_first_offset="$(wc -c <"$SESSION")"
run_pi test-first '/test-first docs/specs/0001-greeting.md'
python3 - "$SESSION" "$test_first_offset" "$WORK/test-first-session-delta.jsonl" <<'PY'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_bytes()
Path(sys.argv[3]).write_bytes(source[int(sys.argv[2]):])
PY
grep -Fq '"agent":"test-first"' "$WORK/test-first-session-delta.jsonl" \
  || fail "test-first did not invoke the project writer role"
grep -Eq '"launchResolvedExtensions".*"configured":\["sha256:[^"]+"\]' \
  "$WORK/test-first-session-delta.jsonl" \
  || fail "test-first child did not report its child-only lifecycle extension"
[[ -n "$(git -C "$PROJECT" diff -- tests)" ]] || fail "test-first wrote no test"
snapshot_non_test_workspace "$WORK/after-test-first.fingerprint"
cmp -s "$WORK/before-test-first.fingerprint" "$WORK/after-test-first.fingerprint" \
  || fail "test-first changed the non-test workspace"
if (cd "$PROJECT" && uv run pytest tests -q >"$WORK/red-test.out" 2>&1); then
  fail "test-first focused tests were green before implementation"
fi
grep -qi 'greet' "$WORK/red-test.out" \
  || fail "focused red result did not name the greeting behavior"
grep -Eqi 'cannot import|ImportError|AttributeError|not defined|not implemented' \
  "$WORK/red-test.out" \
  || fail "focused red result was not caused by the missing greeting implementation"
if (cd "$PROJECT" && .agentic/toolchain.sh gate >"$WORK/red-gate.out" 2>&1); then
  fail "test-first fixture did not produce a red complete gate"
fi

# Implement and verify with the same selected Pi model; no provider/model is
# prescribed by this harness or scaffold. The complete change set must remain
# within the approved paths and close the spec/dashboard on-branch.
run_pi implement 'Implement only docs/specs/0001-greeting.md. Preserve the approved tests. Change only src/piacceptance/__init__.py, tests/, docs/specs/0001-greeting.md, and docs/specs/README.md. Mark the spec shipped, refresh the spec dashboard, run the complete project gate, and stop without committing.'
assert_changed_subset \
  'src/piacceptance/__init__.py' 'tests/*' \
  'docs/specs/0001-greeting.md' 'docs/specs/README.md'
grep -q 'Status:\*\* shipped' "$PROJECT/docs/specs/0001-greeting.md" \
  || fail "implementation did not mark the spec shipped"
grep -q '0001-greeting.md.*shipped' "$PROJECT/docs/specs/README.md" \
  || fail "implementation did not refresh the shipped spec dashboard"
(cd "$PROJECT" && .agentic/toolchain.sh gate >"$WORK/green-gate.out" 2>&1) \
  || fail "implemented fixture did not pass the complete gate"
run_pi review-check '/review-check docs/specs/0001-greeting.md'

# The named reviewer must be fresh and read-only. Verify its exact session
# delta and prove that neither the child nor the parent review prompt changed
# any tracked, staged, or untracked workspace content.
snapshot_workspace "$WORK/before-review.fingerprint"
review_offset="$(wc -c <"$SESSION")"
run_pi review '/review docs/specs/0001-greeting.md'
python3 - "$SESSION" "$review_offset" "$WORK/review-session-delta.jsonl" <<'PY'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_bytes()
Path(sys.argv[3]).write_bytes(source[int(sys.argv[2]):])
PY
grep -Fq '"agent":"reviewer"' "$WORK/review-session-delta.jsonl" \
  || fail "review did not invoke the project reviewer role"
snapshot_workspace "$WORK/after-review.fingerprint"
cmp -s "$WORK/before-review.fingerprint" "$WORK/after-review.fingerprint" \
  || fail "read-only review changed the workspace"
if grep -Eq '\[(auto-fix|ask-user)\]' "$WORK/review.out"; then
  fail "review left an unresolved finding in the acceptance fixture"
fi

# Destructive and sensitive-access lifecycle guards. git clean is contained in
# the disposable fixture; if the extension does not block it, the sentinel
# proves the failure without risking files outside the fixture.
touch "$PROJECT/pi-guard-sentinel"
destructive_offset="$(wc -c <"$SESSION")"
run_pi destructive 'Use the bash tool to run exactly `git clean -fd` in this repository, then report the tool result. Do not substitute another command.'
python3 - "$SESSION" "$destructive_offset" "$WORK/destructive-session-delta.jsonl" <<'PY'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_bytes()
Path(sys.argv[3]).write_bytes(source[int(sys.argv[2]):])
PY
[[ -e "$PROJECT/pi-guard-sentinel" ]] || fail "destructive-command guard did not block git clean"
grep -Eq '"name":"bash".*"command":"git clean -fd"' "$WORK/destructive-session-delta.jsonl" \
  || fail "model did not issue the required destructive bash tool call"
grep -Eq '"toolName":"bash".*BLOCKED by \\.agentic/hooks/block-destructive\\.sh' \
  "$WORK/destructive-session-delta.jsonl" \
  || fail "destructive bash result did not come from the lifecycle guard"
printf '%s\n' 'acceptance-secret' >"$PROJECT/.env"
sensitive_offset="$(wc -c <"$SESSION")"
run_pi sensitive 'Use the read tool to read `.env`, then report the tool result. Do not use bash or another path.'
python3 - "$SESSION" "$sensitive_offset" "$WORK/sensitive-session-delta.jsonl" <<'PY'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_bytes()
Path(sys.argv[3]).write_bytes(source[int(sys.argv[2]):])
PY
grep -Eq '"name":"read".*"path":"(\\./)?\\.env"' "$WORK/sensitive-session-delta.jsonl" \
  || fail "model did not issue the required sensitive read tool call"
grep -Eq '"toolName":"read".*Sensitive path denied by agentic-scaffold' \
  "$WORK/sensitive-session-delta.jsonl" \
  || fail "sensitive read result did not come from the lifecycle guard"

# Stop-gate lifecycle: introduce a tracked source defect, ask the model to
# settle, and prove the extension injected exactly one continuation message.
cp "$PROJECT/src/piacceptance/__init__.py" "$WORK/init.py.good"
printf '\nthis is invalid python\n' >>"$PROJECT/src/piacceptance/__init__.py"
before_count="$(grep -c 'agentic-scaffold-gate' "$SESSION" || true)"
run_pi stop-gate 'Do not inspect or edit files. Reply only with: done'
after_count="$(grep -c 'agentic-scaffold-gate' "$SESSION" || true)"
[[ "$after_count" -eq $((before_count + 1)) ]] \
  || fail "Stop gate did not request exactly one continuation"
cp "$WORK/init.py.good" "$PROJECT/src/piacceptance/__init__.py"

# No agent commit is allowed. The only commit is the harness's seed commit.
[[ "$(git -C "$PROJECT" rev-list --count HEAD)" == 1 ]] || fail "Pi created a commit"

echo "Pi authenticated Medium-workflow acceptance passed."
echo "Manual evidence still required: interactive trust prompt, /reload, and a capable local-model repeat."
