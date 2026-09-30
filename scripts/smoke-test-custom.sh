#!/usr/bin/env bash
# Smoke-test the custom flavor end to end: bootstrap the core profile into a
# temp dir, assert the installed file set, prove the unfilled runner keeps
# every gate consumer quiet, fill the runner with a small shell toolchain,
# prove the gate then goes green, goes red on a defect with the step named,
# and blocks the Stop hook, and prove `--update` leaves the project-owned
# runner, CI workflow, and Dependabot ecosystems alone. Covers generic
# migration and active-runner failures across the gate consumers. Broader
# profile-transition cases live in scripts/smoke-test.sh.
#
# Usage:
#   scripts/smoke-test-custom.sh
#
# Requires: bash, git, python3. No network.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/project"
cd "$WORK/project"

fail() {
  echo "CUSTOM SMOKE FAIL: $*" >&2
  exit 1
}

git init -q -b main
bash "$REPO_DIR/custom/bootstrap.sh" --core >"$WORK/bootstrap.out"
grep -q 'The gate runner is a template' "$WORK/bootstrap.out" \
  || fail "bootstrap did not say the runner needs filling"

must() { [[ -e "$1" ]] || fail "expected file missing: $1"; }
must_not() { [[ ! -e "$1" ]] || fail "file should not be installed: $1"; }

# --- file set: the whole workflow surface, no other stack's files, no starter ---
for path in CLAUDE.md WORKFLOW.md AGENTS.md README.md .gitignore \
  .pre-commit-config.yaml .agentic/toolchain.sh .agentic/scaffold-state \
  .agentic/hooks/gate-on-stop.sh .agentic/hooks/format-after-edit.sh \
  .agentic/hooks/closeout-check.sh .agentic/hooks/block-destructive.sh \
  .agentic/hooks/branch-check.sh \
  .claude/settings.json .claude/agents/reviewer.md .claude/agents/test-first.md \
  .claude/commands/spec.md .claude/commands/plan.md \
  .claude/commands/review-check.md .claude/commands/review.md \
  .claude/commands/product-spec.md \
  .codex/config.toml .codex/hooks.json .codex/rules/safety.rules \
  .agents/skills/spec/SKILL.md .agents/skills/review-check/SKILL.md \
  .github/workflows/ci.yml .github/dependabot.yml \
  docs/specs/README.md docs/project-types.md docs/agent-handoff.md; do
  must "$path"
done
for path in pyproject.toml package.json src tests starter stack.sh bootstrap.sh \
  .claude/skills; do
  must_not "$path"
done
[[ -x .agentic/toolchain.sh ]] || fail "toolchain.sh is not executable"

printf '@AGENTS.md\n' | cmp -s - CLAUDE.md || fail "CLAUDE.md is not the @AGENTS.md import shim"
grep -q 'The scaffold has no adapter for this stack' AGENTS.md \
  || fail "AGENTS.md lacks the custom stack block"
grep -q '^### Test-first' AGENTS.md || fail "AGENTS.md lacks the stack's test-first section"
grep -q 'External-reference provenance' AGENTS.md || fail "AGENTS.md lost the neutral provenance rule"
grep -q 'toolchain.sh` once filled' AGENTS.md || fail "AGENTS.md don't-touch list does not guard the runner"
! grep -q '# Python code conventions\|# TypeScript code conventions' AGENTS.md \
  || fail "AGENTS.md carries another stack's rule"
! grep -q 'pytest\|uv sync\|Vitest' AGENTS.md README.md \
  || fail "the contract or README names another stack's tools"
grep -Fxq 'PROFILE=core' .agentic/scaffold-state || fail "persisted profile is not core"
grep -q 'gate-on-stop.sh' .claude/settings.json || fail "Claude Stop hook not wired"
grep -q 'toolchain.sh ready' .github/workflows/ci.yml || fail "consumer CI does not guard on ready"
grep -q 'toolchain.sh gate' .github/workflows/ci.yml || fail "consumer CI does not call the runner's gate"

# Toolchain and ecosystem configuration are never recorded as managed.
! grep -q 'toolchain.sh$\|workflows/ci.yml$\|dependabot.yml$' .agentic/scaffold-managed-files \
  || fail "project-owned toolchain or ecosystem config was recorded as scaffold-managed"

git add -A
git -c user.email=smoke@example.com -c user.name=Smoke commit -qm "scaffold" --no-verify

# --- unfilled runner: not ready, and every gate consumer stays quiet ---
bash .agentic/toolchain.sh ready && fail "unfilled runner reports ready"
lint_err="$(bash .agentic/toolchain.sh lint 2>&1)" && fail "unfilled lint step exited 0"
[[ "$lint_err" == *"not defined yet"* ]] || fail "unfilled step does not say so; got: $lint_err"
gate_output="$(bash .agentic/toolchain.sh gate --quiet)" && fail "unfilled gate is green"
[[ "$gate_output" == "failed: configuration" ]] \
  || fail "unfilled quiet gate did not name configuration; got: $gate_output"

# Execute the shipped CI step and pre-commit entries, not copies of their logic.
python3 - <<'PY'
from pathlib import Path
import re
ci = Path('.github/workflows/ci.yml').read_text()
body = re.search(r'- name: Quality gate\n        run: \|\n((?:          .*\n)+)', ci)[1]
Path('ci-gate.sh').write_text(''.join(line[10:] for line in body.splitlines(True)))
hooks = Path('.pre-commit-config.yaml').read_text()
for name in ('format', 'lint'):
    entry = re.search(rf'- id: toolchain-{name}\n.*\n        entry: (.*)', hooks)[1]
    Path(f'commit-{name}.sh').write_text(entry + '\n')
PY
bash -e ci-gate.sh >"$WORK/ci.out" || fail "unconfigured CI should skip"
grep -q 'no quality gate ran' "$WORK/ci.out" || fail "CI did not announce skip"
for step in format lint; do
  bash "commit-$step.sh" || fail "unconfigured pre-commit $step should skip"
done

mkdir -p scripts tests
printf '#!/usr/bin/env bash\necho hello\n' >scripts/hello.sh
printf '#!/usr/bin/env bash\n[[ "$(bash scripts/hello.sh)" == hello ]]\n' >tests/run.sh
stop_output="$(printf '{"stop_hook_active":false}\n' | bash .agentic/hooks/gate-on-stop.sh)"
[[ -z "$stop_output" ]] || fail "Stop hook decided on an unfilled runner: $stop_output"
bash .agentic/hooks/format-after-edit.sh || fail "edit hook failed on an unfilled runner"

# A half-filled runner is still not ready: no gate on steps nobody chose.
fill() {
  python3 - "$@" <<'PY'
import re
import sys
from pathlib import Path

path = Path(".agentic/toolchain.sh")
text = path.read_text()
for assignment in sys.argv[1:]:
    name, _, body = assignment.partition("=")
    if name.startswith("TC_"):
        text, count = re.subn(rf'^{name}="".*$', f'{name}="{body}"', text, flags=re.M)
    else:
        text, count = re.subn(
            rf"^{name}\(\) \{{ unfilled .*$", f"{name}() {{ {body}; }}", text, flags=re.M
        )
    if count != 1:
        sys.exit(f"fill: no single template line for {name}")
path.write_text(text)
PY
}
fill TC_SOURCE_DIRS=scripts TC_TEST_DIRS=tests \
  tc_install=no_tool tc_format=no_tool tc_format_check=no_tool \
  'tc_lint=local f; for f in scripts/*.sh; do bash -n "$f" || return 1; done'
bash .agentic/toolchain.sh ready && fail "half-filled runner reports ready"

# --- filled runner: the gate is on ---
fill tc_typecheck=no_tool \
  'tc_test=if (($#)); then bash "$@"; else bash tests/run.sh; fi'
sed -i.bak 's/^TC_CONFIGURED=0/TC_CONFIGURED=1/' .agentic/toolchain.sh
rm -f .agentic/toolchain.sh.bak
bash -n .agentic/toolchain.sh || fail "filled runner is not valid bash"
bash .agentic/toolchain.sh ready || fail "filled runner is not ready"
[[ "$(bash .agentic/toolchain.sh source-dirs)" == "scripts" ]] || fail "source-dirs is not scripts"
bash .agentic/toolchain.sh install || fail "no_tool install step failed"
bash .agentic/toolchain.sh gate >/dev/null || fail "gate is red on a clean filled project"
bash .agentic/toolchain.sh test tests/run.sh || fail "focused test target failed"
bash -e ci-gate.sh >"$WORK/ci.out" || fail "CI failed on a clean active project"
for step in format lint; do
  bash "commit-$step.sh" || fail "pre-commit $step failed on a clean active project"
done
bash .agentic/hooks/format-after-edit.sh --strict || fail "strict edit hook failed on a clean active project"
git add -A
git -c user.email=smoke@example.com -c user.name=Smoke commit -qm "fill the runner" --no-verify

# Clean tree: the Stop hook allows the stop.
stop_output="$(printf '{"stop_hook_active":false}\n' | bash .agentic/hooks/gate-on-stop.sh)"
[[ -z "$stop_output" ]] || fail "Stop hook emitted a decision on a clean tree: $stop_output"

# A defect turns the gate red with the step named, and the Stop hook blocks.
printf 'if then fi (\n' >scripts/broken.sh
gate_output="$(bash .agentic/toolchain.sh gate --quiet)" && fail "gate stayed green on a syntax defect"
case "$gate_output" in
  failed:*lint*) ;;
  *) fail "quiet gate did not name lint; got: $gate_output" ;;
esac
stop_output="$(printf '{"stop_hook_active":false}\n' | bash .agentic/hooks/gate-on-stop.sh)"
[[ "$stop_output" == *'"decision":"block"'* ]] \
  || fail "Stop hook did not block a red gate; got: $stop_output"
[[ "$stop_output" == *lint* ]] || fail "Stop hook block reason does not name the failing step"
rm -f scripts/broken.sh

# A failing test is caught by the test step, not by lint.
printf '#!/usr/bin/env bash\necho goodbye\n' >scripts/hello.sh
gate_output="$(bash .agentic/toolchain.sh gate --quiet)" && fail "gate stayed green on a failing test"
[[ "$gate_output" == "failed: test" ]] || fail "quiet gate did not name only test; got: $gate_output"
git checkout -q -- scripts/hello.sh

# Active gates must fail across consumers on lost directories or broken runners.
cp .agentic/toolchain.sh "$WORK/active-toolchain.sh"
for defect in missing-tests missing-source syntax runtime-error missing-function unfilled-step missing-runner; do
  case "$defect" in
    missing-tests) mv tests "$WORK/tests" ;;
    missing-source) mv scripts "$WORK/scripts" ;;
    syntax) printf '\nif then\n' >>.agentic/toolchain.sh ;;
    runtime-error) printf '#!/usr/bin/env bash\nexit 1\n' >.agentic/toolchain.sh ;;
    missing-function) sed -i.bak '/^tc_lint()/d' .agentic/toolchain.sh ;;
    unfilled-step) sed -i.bak 's/^tc_lint().*/tc_lint() { unfilled lint; }/' .agentic/toolchain.sh ;;
    missing-runner) rm .agentic/toolchain.sh ;;
  esac
  bash -e ci-gate.sh >"$WORK/ci.out" 2>&1 && fail "CI skipped $defect"
  for step in format lint; do
    bash "commit-$step.sh" >"$WORK/commit.out" 2>&1 && fail "pre-commit $step skipped $defect"
  done
  bash .agentic/hooks/format-after-edit.sh >"$WORK/edit.out" 2>&1 && fail "edit hook skipped $defect"
  stop_output="$(printf '{"stop_hook_active":false}\n' | bash .agentic/hooks/gate-on-stop.sh 2>/dev/null)"
  [[ "$stop_output" == *'"decision":"block"'* ]] || fail "Stop hook skipped $defect"
  [[ ! -d "$WORK/tests" ]] || mv "$WORK/tests" tests
  [[ ! -d "$WORK/scripts" ]] || mv "$WORK/scripts" scripts
  cp "$WORK/active-toolchain.sh" .agentic/toolchain.sh
  rm -f .agentic/toolchain.sh.bak
done

# --- --update refreshes managed files and leaves the project's alone ---
printf '\n# PROJECT CI STEP SURVIVES\n' >>.github/workflows/ci.yml
cat >>.github/dependabot.yml <<'YAML'
  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "weekly"
YAML
cp .github/dependabot.yml "$WORK/dependabot.yml"
cp .agentic/toolchain.sh "$WORK/filled-toolchain.sh"
printf '\n# local tamper\n' >>.agentic/hooks/branch-check.sh
bash "$REPO_DIR/custom/bootstrap.sh" --update >/dev/null
cmp -s .agentic/toolchain.sh "$WORK/filled-toolchain.sh" \
  || fail "--update overwrote the project-owned toolchain runner"
grep -q 'PROJECT CI STEP SURVIVES' .github/workflows/ci.yml \
  || fail "--update overwrote the project-owned CI workflow"
cmp -s .github/dependabot.yml "$WORK/dependabot.yml" \
  || fail "--update overwrote the project-owned Dependabot ecosystems"
cmp -s .agentic/hooks/branch-check.sh "$REPO_DIR/shared/hooks/branch-check.sh" \
  || fail "--update did not refresh a managed hook"
bash .agentic/toolchain.sh gate --quiet || fail "gate is red after --update"
for profile in minimal core; do
  bash "$REPO_DIR/custom/bootstrap.sh" --update "--$profile" >/dev/null
  cmp -s .github/dependabot.yml "$WORK/dependabot.yml" \
    || fail "profile transition overwrote project-owned Dependabot configuration"
done

# --- close-out gate: silent on a chore branch, as in the other flavors ---
CLOSEOUT_BRANCH=chore/bump-tools bash .agentic/hooks/closeout-check.sh >/dev/null 2>&1 \
  || fail "closeout gate fired on a chore branch"

# Upgrade generic with both stock and customized client settings. Project
# contracts remain owned by the project; candidates make reconciliation explicit.
for variant in stock customized update; do
  mkdir "$WORK/$variant"
  cd "$WORK/$variant"
  git init -q -b main
  bash "$REPO_DIR/generic/bootstrap.sh" >/dev/null
  printf '\nProject contract survives migration.\n' >>AGENTS.md
  cp AGENTS.md "$WORK/contract-$variant.md"
  printf 'Project workflow survives migration.\n' >WORKFLOW.md
  if [[ "$variant" == customized ]]; then
    python3 - <<'PY'
import json
from pathlib import Path
for name in ('.claude/settings.json', '.codex/hooks.json'):
    p = Path(name)
    data = json.loads(p.read_text())
    data['hooks']['Stop'] = [{'hooks': [{'type': 'command', 'command': 'echo local-hook'}]}]
    p.write_text(json.dumps(data) + '\n')
PY
    cp .claude/settings.json "$WORK/local-claude.json"
    cp .codex/hooks.json "$WORK/local-codex.json"
    printf '\n# Local preference survives migration.\n' >>.codex/config.toml
    cp .codex/config.toml "$WORK/local-config.toml"
  fi
  migration_args=()
  [[ "$variant" != update ]] || migration_args+=(--update)
  bash "$REPO_DIR/custom/bootstrap.sh" "${migration_args[@]}" >"$WORK/migration.out"
  [[ -f .agentic/scaffold-state ]] || fail "generic state directory was not migrated"
  [[ -d .agentic/generic-scaffold-state ]] || fail "generic hashes were not preserved"
  cmp -s AGENTS.md "$WORK/contract-$variant.md" || fail "migration changed project contract"
  grep -Fxq 'Project workflow survives migration.' WORKFLOW.md || fail "migration overwrote project workflow"
  must .agentic/generic-migration/AGENTS.md
  must .agents/skills/spec/SKILL.md
  if [[ "$variant" != customized ]]; then
    for config in .claude/settings.json .codex/hooks.json; do
      grep -q 'gate-on-stop.sh' "$config" || fail "migration left generic hooks in $config"
    done
  else
    cmp -s .claude/settings.json "$WORK/local-claude.json" || fail "migration lost Claude customization"
    cmp -s .codex/hooks.json "$WORK/local-codex.json" || fail "migration lost Codex customization"
    cmp -s .codex/config.toml "$WORK/local-config.toml" || fail "migration lost Codex preferences"
    must .agentic/generic-migration/.codex/config.toml
    for config in .claude/settings.json .codex/hooks.json; do
      grep -q 'gate-on-stop.sh' ".agentic/generic-migration/$config" || fail "missing hook merge candidate"
    done
    grep -q 'manual reconciliation' "$WORK/migration.out" || fail "migration omitted reconciliation warning"
  fi
  bash "$REPO_DIR/custom/bootstrap.sh" --update >"$WORK/update.out"
  grep -q 'Using recorded bootstrap choices' "$WORK/update.out" || fail "migrated state unreadable"
  grep -Fxq 'PROFILE=core' .agentic/scaffold-state || fail "migration lost core profile"
  grep -Fxq 'NO_STOP_GATE=0' .agentic/scaffold-state || fail "migration inherited generic no-Stop behavior"
  if [[ "$variant" == customized ]]; then
    cmp -s .claude/settings.json "$WORK/local-claude.json" || fail "update lost migrated customization"
  fi
  bash "$REPO_DIR/generic/bootstrap.sh" --update >"$WORK/reverse.out" 2>&1 \
    && fail "generic bootstrap accepted a migrated stack state"
  grep -q 'uses a stack flavor' "$WORK/reverse.out" || fail "reverse migration did not explain the correct update command"
done

echo "custom smoke-test OK"
