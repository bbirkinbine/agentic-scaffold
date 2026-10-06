#!/usr/bin/env bash
# Validate rendered Pi prompts, pi-subagents roles, settings, and lifecycle adapter.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$REPO_DIR/workflow"
FAILURES=0

fail() { echo "PI ADAPTER FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }
frontmatter() {
  local key="$1" file="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm=1; next }
    in_fm && $0 == "---" { exit }
    in_fm && index($0, key ":") == 1 {
      sub("^[^:]*:[[:space:]]*", "")
      print
      exit
    }
  ' "$file"
}
body() { awk 'NR == 1 && $0 == "---" { in_fm=1; next } in_fm && $0 == "---" { in_fm=0; next } !in_fm { print }' "$1"; }

python3 - "$WORKFLOW/client/pi/settings.json" <<'PY' || fail "Pi settings structure does not match the pinned adapter contract"
import json
import sys
from pathlib import Path

settings = json.loads(Path(sys.argv[1]).read_text())
assert settings == {
    "packages": [{
        "source": "npm:pi-subagents@0.76.1",
        "autoload": False,
        "extensions": ["+./index.js"],
        "skills": [],
        "prompts": [],
        "themes": [],
    }],
    "extensions": ["+./extensions/agentic-hooks.ts"],
    "subagents": {
        "projectRootResolution": "git-root",
        "disableBuiltins": True,
        "agentExcludeDirs": ["../.agents"],
        "modelScope": {"enforce": True, "strict": True, "allow": ["inherit"]},
    },
}
PY

for flavor in python typescript custom; do
  root="$REPO_DIR/$flavor"
  [[ -f "$root/.pi/settings.json" ]] || { fail "$flavor missing .pi/settings.json"; continue; }
  python3 -m json.tool "$root/.pi/settings.json" >/dev/null || fail "$flavor Pi settings are invalid JSON"
  cmp -s "$WORKFLOW/client/pi/settings.json" "$root/.pi/settings.json" || fail "$flavor Pi settings drifted"
  grep -Fq 'npm:pi-subagents@0.76.1' "$root/.pi/settings.json" || fail "$flavor package is not exactly pinned"
  grep -Fq '"autoload": false' "$root/.pi/settings.json" || fail "$flavor package autoload is not disabled"
  grep -Fq '"disableBuiltins": true' "$root/.pi/settings.json" || fail "$flavor built-in subagents remain enabled"
  grep -Fq '"../.agents"' "$root/.pi/settings.json" || fail "$flavor legacy agent discovery can reach .agents"
  grep -Fq '"inherit"' "$root/.pi/settings.json" || fail "$flavor does not enforce inherited models"
  [[ -f "$root/.pi/extensions/agentic-hooks.ts" ]] || fail "$flavor missing parent lifecycle extension"
  [[ -f "$root/.pi/extensions/agentic-child-hooks.ts" ]] || fail "$flavor missing child lifecycle extension"
  cmp -s "$REPO_DIR/shared/pi/agentic-hooks.ts" "$root/.pi/extensions/agentic-hooks.ts" || fail "$flavor parent lifecycle extension drifted"
  cmp -s "$REPO_DIR/shared/pi/agentic-child-hooks.ts" "$root/.pi/extensions/agentic-child-hooks.ts" || fail "$flavor child lifecycle extension drifted"

  for source in "$WORKFLOW"/commands/*.md; do
    name="$(basename "$source")"
    cmp -s "$source" "$root/.pi/prompts/$name" || fail "$flavor prompt drift: $name"
  done
  while IFS= read -r rendered; do
    name="$(basename "$rendered")"
    [[ -f "$WORKFLOW/commands/$name" ]] || fail "$flavor orphan Pi prompt: $name"
  done < <(find "$root/.pi/prompts" -maxdepth 1 -type f -name '*.md' -print)

  for source in "$WORKFLOW"/roles/*.md "$WORKFLOW"/roles/optional/*.md; do
    [[ -f "$source" ]] || continue
    name="$(basename "$source")"
    if [[ "$source" == */optional/* ]]; then
      rendered="$root/.pi/agents/optional/$name"
    else
      rendered="$root/.pi/agents/$name"
    fi
    [[ -f "$rendered" ]] || { fail "$flavor missing Pi role: $name"; continue; }
    [[ "$(frontmatter name "$rendered")" == "${name%.md}" ]] || fail "$flavor role name mismatch: $name"
    [[ "$(frontmatter description "$rendered")" == "$(frontmatter description "$source")" ]] || fail "$flavor role description drift: $name"
    [[ "$(frontmatter model "$rendered")" == inherit ]] || fail "$flavor role pins a model: $name"
    [[ "$(frontmatter defaultContext "$rendered")" == fresh ]] || fail "$flavor role is not fresh-context: $name"
    [[ "$(frontmatter inheritProjectContext "$rendered")" == true ]] || fail "$flavor role drops project context: $name"
    src_body="$(mktemp)"; rendered_body="$(mktemp)"
    body "$source" >"$src_body"
    body "$rendered" | tail -n +4 >"$rendered_body"
    cmp -s "$src_body" "$rendered_body" || fail "$flavor role body drift: $name"
    rm -f "$src_body" "$rendered_body"

    tools="$(frontmatter tools "$rendered")"
    case "${name%.md}" in
      test-first|evaluator)
        [[ "$tools" == 'read, grep, find, ls, bash, edit, write' ]] || fail "$flavor writer role tools mismatch: $name"
        [[ "$(frontmatter acceptanceRole "$rendered")" == writer ]] || fail "$flavor writer role acceptance mismatch: $name"
        ;;
      *)
        [[ "$tools" == 'read, grep, find, ls' ]] || fail "$flavor read-only role has mutation/shell tools: $name"
        [[ "$(frontmatter acceptanceRole "$rendered")" == read-only ]] || fail "$flavor read-only role acceptance mismatch: $name"
        ;;
    esac
    expected_extension='../extensions/agentic-child-hooks.ts'
    [[ "$(frontmatter subagentOnlyExtensions "$rendered")" == "$expected_extension" ]] || fail "$flavor role lacks child-only lifecycle guards: $name"
    # Optional definitions are copy templates. Validate the documented promoted
    # destination, where the relative extension path must resolve.
    promoted="$root/.pi/agents/$name"
    resolved_extension="$(python3 -c 'import os, sys; print(os.path.abspath(os.path.join(os.path.dirname(sys.argv[1]), sys.argv[2])))' "$promoted" "$expected_extension")"
    [[ "$resolved_extension" == "$root/.pi/extensions/agentic-child-hooks.ts" ]] || fail "$flavor promoted role extension path is invalid: $name"
  done

  while IFS= read -r rendered; do
    rel="${rendered#"$root/.pi/agents/"}"
    if [[ "$rel" == optional/* ]]; then
      source="$WORKFLOW/roles/optional/${rel#optional/}"
    else
      source="$WORKFLOW/roles/$rel"
    fi
    [[ -f "$source" ]] || fail "$flavor orphan or misplaced Pi role: $rel"
  done < <(find "$root/.pi/agents" -type f -name '*.md' -print)
done

[[ -f "$REPO_DIR/generic/.pi/settings.json" ]] || fail "generic missing Pi settings"
python3 -m json.tool "$REPO_DIR/generic/.pi/settings.json" >/dev/null || fail "generic Pi settings are invalid JSON"
cmp -s "$REPO_DIR/shared/pi/agentic-hooks.ts" "$REPO_DIR/generic/.pi/extensions/agentic-hooks.ts" || fail "generic lifecycle extension drifted"
grep -Fq 'agentic-hooks.ts' "$REPO_DIR/generic/.pi/settings.json" || fail "generic does not load lifecycle extension"
! grep -Eq 'packages|subagents' "$REPO_DIR/generic/.pi/settings.json" || fail "generic must not load workflow packages or subagents"
[[ ! -e "$REPO_DIR/generic/.pi/prompts" && ! -e "$REPO_DIR/generic/.pi/agents" ]] || fail "generic must not include workflow prompts or roles"

extension="$REPO_DIR/shared/pi/agentic-hooks.ts"
child_extension="$REPO_DIR/shared/pi/agentic-child-hooks.ts"
grep -Fq 'parentLifecycle: false' "$child_extension" || fail "child lifecycle entry point does not disable parent completion behavior"
for event in session_start input user_bash tool_call tool_result agent_before_settle turn_end; do
  grep -Fq "pi.on(\"$event\"" "$extension" || fail "extension missing $event handler"
done
! grep -Fq 'session_before_compact' "$extension" || fail "extension claims unsupported default-compaction parity"
! grep -Eq '(provider|defaultProvider|model):[[:space:]]*(anthropic|openai|google|ollama|llama|claude|gpt|gemini)' \
  "$extension" "$WORKFLOW/client/pi/settings.json" "$WORKFLOW"/roles/*.md || fail "Pi adapter pins an LLM provider/model"

if ! command -v pi >/dev/null 2>&1; then
  fail "Pi 1.0.4 is required to validate project package settings"
elif [[ "$(pi --version)" != 1.0.4 ]]; then
  fail "Pi validator baseline is 1.0.4; found $(pi --version)"
else
  runtime_fixture="$(mktemp -d)"
  git -C "$runtime_fixture" init -q -b main
  (cd "$runtime_fixture" && bash "$REPO_DIR/python/bootstrap.sh" --minimal --no-stop-gate >/dev/null)
  if ! package_list="$(cd "$runtime_fixture" && pi list --approve 2>&1)"; then
    fail "Pi rejected or could not resolve the pinned project package settings"
  elif ! grep -Fq 'npm:pi-subagents@0.76.1 (filtered)' <<<"$package_list"; then
    fail "Pi did not load pi-subagents 0.76.1 in extension-only filtered mode"
  fi
  python3 - "$runtime_fixture" <<'PY' || fail "Pi RPC resource/agent discovery fixture failed"
import json
import select
import subprocess
import sys
import time

cwd = sys.argv[1]
process = subprocess.Popen(
    ["pi", "--approve", "--no-session", "--mode", "rpc"],
    cwd=cwd,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
assert process.stdin is not None and process.stdout is not None

def request(payload, request_id, timeout=60, done_text=None):
    process.stdin.write(json.dumps({"id": request_id, **payload}) + "\n")
    process.stdin.flush()
    records = []
    deadline = time.time() + timeout
    while time.time() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], 1)
        if not ready:
            continue
        line = process.stdout.readline()
        if not line:
            break
        record = json.loads(line)
        records.append(record)
        if done_text is not None and done_text in line:
            return record, records
        if record.get("id") == request_id and record.get("type") == "response":
            if not record.get("success"):
                raise AssertionError(record.get("error", "RPC request failed"))
            return record, records
    raise AssertionError(f"timed out waiting for {request_id}")

try:
    response, _ = request({"type": "get_commands"}, "commands")
    commands = response["data"]["commands"]
    project_prompts = {
        item["name"] for item in commands
        if item.get("source") == "prompt" and item.get("sourceInfo", {}).get("scope") == "project"
    }
    project_skills = {
        item["name"] for item in commands
        if item.get("source") == "skill" and item.get("sourceInfo", {}).get("scope") == "project"
    }
    expected = {"spec", "plan", "test-first", "review-check", "review"}
    assert project_prompts == expected, (project_prompts, expected)
    assert project_skills == {f"skill:{name}" for name in expected}, project_skills

    _, doctor_records = request(
        {"type": "prompt", "message": "/subagents-doctor"},
        "doctor",
        done_text="Subagents doctor report",
    )
    doctor = "\n".join(json.dumps(item) for item in doctor_records)
    assert "project 3" in doctor, doctor
    assert "project 5" in doctor, doctor
    assert "package 0" in doctor, doctor
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
PY
  rm -rf "$runtime_fixture"
fi

gate_count="$(grep -c 'continue: true' "$extension" || true)"
[[ "$gate_count" == 1 ]] || fail "extension must expose exactly one continuation path"
grep -Fq 'stopContinuationUsed = true' "$extension" || fail "extension has no continuation loop guard"
grep -Fq 'event.source === "interactive" || event.source === "rpc"' "$extension" || fail "extension does not reset only on operator input"

if command -v node >/dev/null 2>&1 && node --help 2>&1 | grep -q experimental-strip-types; then
  fixture="$(mktemp -d)"
  mkdir -p "$fixture/.agentic/hooks"
  cat >"$fixture/.agentic/hooks/gate-on-stop.sh" <<'HOOK'
#!/usr/bin/env bash
payload="$(cat)"
printf '%s\n' "$payload" >>.agentic/gate-payloads
printf '%s\n' '{"decision":"block","reason":"fixture gate is red"}'
HOOK
  cat >"$fixture/.agentic/hooks/block-destructive.sh" <<'HOOK'
#!/usr/bin/env bash
payload="$(cat)"
if [[ "$payload" == *'rm -rf /'* ]]; then
  echo 'fixture destructive block' >&2
  exit 2
fi
HOOK
  cat >"$fixture/.agentic/hooks/format-after-edit.sh" <<'HOOK'
#!/usr/bin/env bash
cat >/dev/null
printf '%s' "$*" >.agentic/format-args
HOOK
  cat >"$fixture/.agentic/hooks/specs-status.sh" <<'HOOK'
#!/usr/bin/env bash
cat >/dev/null
printf '%s' "$*" >.agentic/status-args
HOOK
  chmod +x "$fixture/.agentic/hooks/"*.sh
  printf '%s\n' 'STRICT_HOOKS=0' 'NO_STOP_GATE=0' >"$fixture/.agentic/scaffold-state"
  if ! PI_EXTENSION="$extension" PI_CHILD_EXTENSION="$child_extension" PI_FIXTURE="$fixture" node --experimental-strip-types --input-type=module <<'NODE'
import { pathToFileURL } from "node:url";
import { readFile, writeFile } from "node:fs/promises";
const handlers = new Map();
const mod = await import(pathToFileURL(process.env.PI_EXTENSION));
mod.default({ on(name, handler) { handlers.set(name, handler); } });
const childHandlers = new Map();
const childMod = await import(pathToFileURL(process.env.PI_CHILD_EXTENSION));
childMod.default({ on(name, handler) { childHandlers.set(name, handler); } });
const gate = handlers.get("agent_before_settle");
const input = handlers.get("input");
const toolCall = handlers.get("tool_call");
const toolResult = handlers.get("tool_result");
const userBash = handlers.get("user_bash");
if (!gate || !input || !toolCall || !toolResult || !userBash) throw new Error("required handlers not registered");
if (!childHandlers.has("tool_call") || !childHandlers.has("tool_result") || !childHandlers.has("user_bash")) {
  throw new Error("child safety/post-edit handlers not registered");
}
if (childHandlers.has("agent_before_settle") || childHandlers.has("session_start") || childHandlers.has("turn_end")) {
  throw new Error("child extension registered parent lifecycle handlers");
}
const ctx = { cwd: process.env.PI_FIXTURE, hasUI: false, ui: { notify() {} } };
const event = { entries: [], context: { canContinue: false }, outcome: "completed" };
const first = await gate(event, ctx);
const second = await gate(event, ctx);
const payloads = await readFile(`${process.env.PI_FIXTURE}/.agentic/gate-payloads`, "utf8");
if (payloads.includes('"stop_hook_active":true')) throw new Error("extension delegated its retry guard to the shell hook");
await input({ source: "extension" });
const stillArmed = await gate(event, ctx);
await input({ source: "interactive" });
const reset = await gate(event, ctx);
const payloadCountBeforeError = (await readFile(`${process.env.PI_FIXTURE}/.agentic/gate-payloads`, "utf8")).trim().split("\n").length;
const errorOutcome = await gate({ ...event, outcome: "error" }, ctx);
const payloadCountAfterError = (await readFile(`${process.env.PI_FIXTURE}/.agentic/gate-payloads`, "utf8")).trim().split("\n").length;
if (first?.continue !== true || second !== undefined || stillArmed !== undefined || reset?.continue !== true) {
  throw new Error("one-continuation state machine failed");
}
if (errorOutcome !== undefined || payloadCountAfterError !== payloadCountBeforeError) {
  throw new Error("provider error incorrectly entered settlement enforcement");
}
await writeFile(`${process.env.PI_FIXTURE}/.agentic/scaffold-state`, "STRICT_HOOKS=0\nNO_STOP_GATE=1\n");
await input({ source: "interactive" });
if (await gate(event, ctx) !== undefined) throw new Error("no-stop mode continued");
const destructive = await toolCall({ toolName: "bash", input: { command: "rm -rf /" } }, ctx);
if (destructive?.block !== true) throw new Error("destructive command was not blocked");
const secret = await toolCall({ toolName: "read", input: { path: ".env" } }, ctx);
if (secret?.block !== true) throw new Error("sensitive read was not blocked");
const grepSecret = await toolCall({ toolName: "grep", input: { pattern: "secret", path: ".env" } }, ctx);
if (grepSecret?.block !== true) throw new Error("explicit sensitive grep was not blocked");
const grepResult = await toolResult({
  toolName: "grep",
  input: { pattern: "secret", path: "." },
  content: [{ type: "text", text: "src/public.py:1: public\nkeys/private.pem:1: secret" }],
  isError: false,
}, ctx);
if (grepResult?.isError !== true || grepResult.content?.[0]?.text?.includes("secret")) {
  throw new Error("directory grep result exposed sensitive-file content");
}
const childSecret = await childHandlers.get("tool_call")({ toolName: "read", input: { path: ".env" } }, ctx);
if (childSecret?.block !== true) throw new Error("child sensitive read was not blocked");
const direct = await userBash({ command: "rm -rf /", excludeFromContext: false }, ctx);
if (direct?.result?.exitCode !== 2) throw new Error("direct user bash bypassed guard");
await writeFile(`${process.env.PI_FIXTURE}/.agentic/scaffold-state`, "STRICT_HOOKS=1\nNO_STOP_GATE=0\n");
await toolResult({ toolName: "edit", input: { path: "src/example.ts" }, content: [], isError: false }, ctx);
if (await readFile(`${process.env.PI_FIXTURE}/.agentic/format-args`, "utf8") !== "--strict") {
  throw new Error("strict mode did not reach formatter");
}
if (await readFile(`${process.env.PI_FIXTURE}/.agentic/status-args`, "utf8") !== "--hook") {
  throw new Error("spec dashboard hook did not run");
}
NODE
  then
    fail "extension one-continuation fixture failed"
  fi
  rm -rf "$fixture"
else
  fail "Node with TypeScript stripping is required for Pi lifecycle fixtures"
fi

if (( FAILURES > 0 )); then
  echo "Pi adapter validation failed with $FAILURES issue(s)." >&2
  exit 1
fi

echo "Pi adapter validation passed."
