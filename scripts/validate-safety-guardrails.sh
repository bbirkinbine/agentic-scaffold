#!/usr/bin/env bash
# Table-driven fixtures for the shared destructive hook and Codex exec policy.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/shared/hooks/block-destructive.sh"
RULES="$REPO_DIR/shared/codex/safety.rules"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "SAFETY VALIDATION FAIL: $*" >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || fail "python3 is required"
command -v codex >/dev/null 2>&1 \
  || fail "codex CLI is required for deterministic execpolicy validation"

hook_cases=(
  'allow::bare Git status::git status'
  'allow::Git status with -C::git -C . status'
  'allow::absolute Git status::/usr/bin/git status'
  'allow::similar Git subcommand::git cleanup'
  'allow::Terraform plan::terraform plan'
  'block::bare Git clean::git clean -fd'
  'block::long Git clean flags::git clean --force --directories'
  'block::Git clean with -C::git -C /tmp/project clean -fd'
  'block::absolute Git clean::/usr/bin/git clean --force -d'
  'block::Homebrew Git clean with -C::/opt/homebrew/bin/git -C . clean -d --force'
  'block::command-wrapped Git clean::command git clean -fd'
  'block::env-wrapped Git clean::env SAFE=1 git -C . clean --force --directories'
  'block::sudo-wrapped Git clean::sudo git clean -fd'
  'block::shell-wrapped Git clean::bash -lc "git clean -fd"'
  'block::Git history rewrite with -C::git -C . filter-repo --force'
  'block::catastrophic rm::rm -rf /'
  'block::Terraform destroy::terraform destroy'
)

for fixture in "${hook_cases[@]}"; do
  expected="${fixture%%::*}"
  remainder="${fixture#*::}"
  label="${remainder%%::*}"
  command="${remainder#*::}"
  stdout="$TMP_DIR/hook.stdout"
  stderr="$TMP_DIR/hook.stderr"

  if python3 -c \
    'import json,sys; print(json.dumps({"tool_input": {"command": sys.argv[1]}}))' \
    "$command" | bash "$HOOK" >"$stdout" 2>"$stderr"; then
    actual=allow
  else
    actual=block
  fi

  [[ "$actual" == "$expected" ]] \
    || fail "hook case '$label' expected $expected, got $actual: $command"
  if [[ "$expected" == block ]]; then
    grep -q 'BLOCKED' "$stderr" \
      || fail "hook case '$label' blocked without an actionable reason"
  fi
done

policy_cases=(
  'prompt::bare commit::git commit -m test'
  'prompt::absolute commit::/usr/bin/git commit -m test'
  'prompt::wrapped commit::command git commit -m test'
  'prompt::bare push::git push origin feature'
  'prompt::wrapped push::env git push'
  'forbidden::bare clean::git clean -fd'
  'forbidden::absolute long-form clean::/usr/local/bin/git clean --force --directories'
  'forbidden::wrapped clean::/usr/bin/env git clean -fd'
  'prompt::Git -C clean requires review before hook enforcement::git -C . clean -fd'
  'prompt::absolute Git -C commit::/opt/homebrew/bin/git -C . commit -m test'
  'prompt::wrapped Git -C status::command git -C . status'
  'unmatched::safe status::git status'
)

for fixture in "${policy_cases[@]}"; do
  expected="${fixture%%::*}"
  remainder="${fixture#*::}"
  label="${remainder%%::*}"
  command="${remainder#*::}"
  read -r -a argv <<<"$command"

  if ! output="$(
    codex execpolicy check --rules "$RULES" -- "${argv[@]}" \
      2>"$TMP_DIR/execpolicy.stderr"
  )"; then
    cat "$TMP_DIR/execpolicy.stderr" >&2
    fail "execpolicy check failed for '$label': $command"
  fi
  actual="$(
    printf '%s' "$output" \
      | python3 -c \
        'import json,sys; print(json.load(sys.stdin).get("decision", "unmatched"))'
  )"
  [[ "$actual" == "$expected" ]] \
    || fail "policy case '$label' expected $expected, got $actual: $command"
done

echo "Safety hook and execpolicy validation OK (${#hook_cases[@]} hook cases, ${#policy_cases[@]} policy cases)."
