#!/usr/bin/env bash
# Static validation for the shared workflow sources and rendered Codex surface.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_DIR="$REPO_DIR/python"
SHARED_DIR="$REPO_DIR/shared"

fail() {
  echo "CODEX ADAPTER FAIL: $*" >&2
  exit 1
}

assert_agents_import() {
  local file="$1"
  cmp -s <(printf '%s\n' '@AGENTS.md') "$file" \
    || fail "$file must contain only the exact @AGENTS.md import shim"
}

# This scaffold repository is the one authoring exception: CLAUDE.md remains
# the source and root AGENTS.md is its complete Codex-readable copy. Generated
# projects use AGENTS.md as the canonical contract and a one-line Claude import
# shim so client policy cannot diverge after bootstrap.
cmp -s "$REPO_DIR/AGENTS.md" "$REPO_DIR/CLAUDE.md" \
  || fail "root AGENTS.md is not the complete CLAUDE.md authoring contract"
assert_agents_import "$PYTHON_DIR/CLAUDE.md"
assert_agents_import "$REPO_DIR/CLAUDE.md.template"
assert_agents_import "$PYTHON_DIR/subdir-CLAUDE.md.example"
cmp -s "$REPO_DIR/generic/project-contract.md" \
  "$REPO_DIR/AGENTS.md.template" \
  || fail "stale generic contract templates"
[[ -s "$PYTHON_DIR/subdir-AGENTS.md.example" ]] \
  || fail "nested AGENTS.md example is empty"

for source in "$SHARED_DIR"/hooks/*.sh; do
  name="$(basename "$source")"
  cmp -s "$source" "$PYTHON_DIR/.agentic/hooks/$name" \
    || fail "python/.agentic/hooks/$name differs from shared/hooks/$name.
    It is a rendered copy, so an edit made there is lost on the next render.
    Move the change into shared/hooks/$name and re-run
    scripts/render-client-surfaces.sh."
done
cmp -s "$SHARED_DIR/codex/config.toml" "$PYTHON_DIR/.codex/config.toml" \
  || fail "stale shared Codex config adapter"
cmp -s "$SHARED_DIR/codex/safety.rules" \
  "$PYTHON_DIR/.codex/rules/safety.rules" \
  || fail "stale shared Codex rules adapter"

contract_bytes="$(wc -c < "$PYTHON_DIR/AGENTS.md" | tr -d ' ')"
default_contract_limit=32768
contract_limit="$(
  sed -n 's/^project_doc_max_bytes[[:space:]]*=[[:space:]]*//p' \
    "$PYTHON_DIR/.codex/config.toml"
)"
[[ "$contract_limit" =~ ^[0-9]+$ ]] || fail "project_doc_max_bytes is not numeric"
((contract_bytes < contract_limit)) \
  || fail "AGENTS.md is ${contract_bytes} bytes; configured limit is ${contract_limit}"
generic_contract_bytes="$(wc -c < "$REPO_DIR/AGENTS.md.template" | tr -d ' ')"
((generic_contract_bytes < contract_limit)) \
  || fail "generic AGENTS.md is ${generic_contract_bytes} bytes; limit is ${contract_limit}"
scaffold_contract_bytes="$(wc -c < "$REPO_DIR/AGENTS.md" | tr -d ' ')"
nested_contract_bytes="$(
  wc -c < "$PYTHON_DIR/subdir-AGENTS.md.example" | tr -d ' '
)"
# Codex defaults to a 32 KiB combined instruction-chain budget before a
# trusted project config can raise it. Keep every root portable at that
# default, and prove the representative Python root + nested-area chain also
# fits rather than checking only the configured 64 KiB ceiling.
for root_contract in \
  "scaffold:$scaffold_contract_bytes" \
  "python:$contract_bytes" \
  "generic:$generic_contract_bytes"; do
  label="${root_contract%%:*}"
  bytes="${root_contract#*:}"
  ((bytes < default_contract_limit)) \
    || fail "$label root AGENTS.md is ${bytes} bytes; default limit is ${default_contract_limit}"
done
representative_chain_bytes=$((contract_bytes + nested_contract_bytes + 2))
((representative_chain_bytes < default_contract_limit)) \
  || fail "Python root+nested instruction chain is ${representative_chain_bytes} bytes; default limit is ${default_contract_limit}"

for source in "$PYTHON_DIR"/workflow/commands/*.md; do
  name="$(basename "$source" .md)"
  cmp -s "$source" "$PYTHON_DIR/.claude/commands/$name.md" \
    || fail "stale Claude command adapter: $name"
  [[ -f "$PYTHON_DIR/.agents/skills/$name/SKILL.md" ]] \
    || fail "missing Codex workflow skill: $name"
done

for source in "$PYTHON_DIR"/workflow/skills/*/SKILL.md; do
  name="$(basename "$(dirname "$source")")"
  cmp -s "$source" "$PYTHON_DIR/.claude/skills/$name/SKILL.md" \
    || fail "stale Claude skill adapter: $name"
  cmp -s "$source" "$PYTHON_DIR/.agents/skills/$name/SKILL.md" \
    || fail "stale Codex skill adapter: $name"
done

python3 - "$PYTHON_DIR" <<'PY'
import json
import os
import re
import sys
import tomllib
from collections import Counter
from pathlib import Path

root = Path(sys.argv[1])
repo = root.parent
generic = repo / "generic"
shared = repo / "shared"


def fail(message: str) -> None:
    raise SystemExit(f"CODEX ADAPTER FAIL: {message}")


def split_frontmatter(path: Path) -> tuple[dict[str, str], str]:
    lines = path.read_text().splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        fail(f"invalid frontmatter: {path}")
    try:
        boundary = next(
            index for index, line in enumerate(lines[1:], start=1)
            if line.strip() == "---"
        )
    except StopIteration:
        fail(f"unterminated frontmatter: {path}")
    metadata: dict[str, str] = {}
    for line in lines[1:boundary]:
        if ": " in line:
            key, value = line.rstrip("\n").split(": ", 1)
            metadata[key] = value
    return metadata, "".join(lines[boundary + 1:]).lstrip("\n")


def markdown_source(path: Path) -> str:
    lines = path.read_text().splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return "".join(lines)
    try:
        boundary = next(
            index for index, line in enumerate(lines[1:], start=1)
            if line.strip() == "---"
        )
    except StopIteration:
        fail(f"unterminated frontmatter: {path}")
    return "".join(lines[boundary + 1:])


def assert_inventory(label: str, expected: set[str], actual: set[str]) -> None:
    missing = sorted(expected - actual)
    orphaned = sorted(actual - expected)
    if missing or orphaned:
        fail(f"{label} inventory differs; missing={missing}, orphaned={orphaned}")


# Reproduce the renderer's complete canonical contract, including every byte
# of every standing rule. Heading-only checks allow Claude and Codex policy to
# diverge while looking structurally complete.
expected_contract = [
    (root / "workflow" / "project-contract.md").read_text(),
    "\n<!-- agentic-scaffold:standing-rules:start -->\n",
    "\n## Standing rules\n\n",
    "These rules are authoritative for every client. They live here once\n",
    "rather than in duplicate client-specific policy files. Do not\n",
    "hand-edit this marked block;\n",
    "`bootstrap.sh --update` refreshes it while preserving content outside\n",
    "the markers.\n",
]
for source in sorted((root / "workflow" / "rules").glob("*.md")):
    expected_contract.extend(["\n---\n\n", markdown_source(source)])
expected_contract.append("\n<!-- agentic-scaffold:standing-rules:end -->\n")
if root.joinpath("AGENTS.md").read_text() != "".join(expected_contract):
    fail("AGENTS.md is not the exact rendered project contract and standing rules")

rule_adapters = sorted((root / ".claude" / "rules").glob("*.md"))
if rule_adapters:
    fail(
        "Claude standing-rule adapters duplicate canonical AGENTS.md policy: "
        + ", ".join(str(path.relative_to(root)) for path in rule_adapters)
    )

command_sources = {
    path.stem for path in (root / "workflow" / "commands").glob("*.md")
}
skill_sources = {
    path.parent.name
    for path in (root / "workflow" / "skills").glob("*/SKILL.md")
}
overlap = command_sources & skill_sources
if overlap:
    fail(f"workflow command/skill names collide: {sorted(overlap)}")

assert_inventory(
    "Claude command adapter",
    command_sources,
    {path.stem for path in (root / ".claude" / "commands").glob("*.md")},
)
assert_inventory(
    "Claude reusable skill adapter",
    skill_sources,
    {
        path.parent.name
        for path in (root / ".claude" / "skills").glob("*/SKILL.md")
    },
)
assert_inventory(
    "Codex repository skill adapter",
    command_sources | skill_sources,
    {
        path.parent.name
        for path in (root / ".agents" / "skills").glob("*/SKILL.md")
    },
)

for source in sorted((root / "workflow" / "commands").glob("*.md")):
    metadata, body = split_frontmatter(source)
    name = source.stem
    target = root / ".agents" / "skills" / name / "SKILL.md"
    skill_metadata, skill_body = split_frontmatter(target)
    if skill_metadata.get("name") != name:
        fail(f"invalid workflow skill name: {name}")
    if skill_metadata.get("description") != metadata.get("description"):
        fail(f"stale workflow skill description: {name}")
    if not skill_body.rstrip("\n").endswith(body.rstrip("\n")):
        fail(f"stale workflow skill body: {name}")

for source in sorted((root / "workflow" / "skills").glob("*/SKILL.md")):
    name = source.parent.name
    for target in (
        root / ".claude" / "skills" / name / "SKILL.md",
        root / ".agents" / "skills" / name / "SKILL.md",
    ):
        if source.read_bytes() != target.read_bytes():
            fail(f"stale reusable skill adapter: {target.relative_to(root)}")


def validate_roles(source_dir: Path, optional: bool) -> None:
    sources = sorted(source_dir.glob("*.md"))
    metadata_by_name: dict[str, tuple[Path, dict[str, str], str]] = {}
    for source in sources:
        metadata, body = split_frontmatter(source)
        name = metadata.get("name", "")
        if not name or name in metadata_by_name:
            fail(f"invalid or duplicate role name: {source}")
        metadata_by_name[name] = (source, metadata, body)

    claude_dir = root / ".claude" / "agents"
    codex_dir = root / ".codex" / "agents"
    if optional:
        claude_dir /= "optional"
        codex_dir /= "optional"
    label = "optional role" if optional else "role"
    assert_inventory(
        f"Claude {label} adapter",
        set(metadata_by_name),
        {path.stem for path in claude_dir.glob("*.md")},
    )
    assert_inventory(
        f"Codex {label} adapter",
        set(metadata_by_name),
        {path.stem for path in codex_dir.glob("*.toml")},
    )

    for name, (source, metadata, body) in metadata_by_name.items():
        claude_target = claude_dir / f"{name}.md"
        if source.read_bytes() != claude_target.read_bytes():
            fail(f"stale Claude {label} adapter: {name}")
        codex_target = codex_dir / f"{name}.toml"
        data = tomllib.loads(codex_target.read_text())
        if data.get("name") != name or data.get("description") != metadata.get(
            "description"
        ):
            fail(f"invalid Codex {label} metadata: {name}")
        instructions = data.get("developer_instructions", "")
        if not instructions.rstrip("\n").endswith(body.rstrip("\n")):
            fail(f"stale Codex {label} prompt: {name}")


validate_roles(root / "workflow" / "roles", optional=False)
validate_roles(root / "workflow" / "roles" / "optional", optional=True)

for path in sorted((root / ".codex").rglob("*.toml")):
    tomllib.loads(path.read_text())
tomllib.loads((shared / "codex" / "config.toml").read_text())


def load_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        fail(f"invalid JSON in {path}: {error}")
    if not isinstance(data, dict):
        fail(f"JSON root is not an object: {path}")
    return data


HookEntry = tuple[str, str, str, tuple[str, ...]]


def hook_matrix(
    data: dict,
    *,
    client: str,
    source: Path,
    script_root: Path,
) -> Counter[HookEntry]:
    events = data.get("hooks")
    if not isinstance(events, dict):
        fail(f"missing hooks object: {source}")
    entries: list[HookEntry] = []
    for event, groups in events.items():
        if not isinstance(groups, list):
            fail(f"hook groups are not a list for {event}: {source}")
        for group in groups:
            if not isinstance(group, dict):
                fail(f"hook group is not an object for {event}: {source}")
            matcher = group.get("matcher")
            if event == "PostToolUse":
                expected_matcher = "Edit|Write" if client == "claude" else "apply_patch"
                if matcher != expected_matcher:
                    fail(
                        f"{client} PostToolUse matcher must be "
                        f"{expected_matcher!r}: {source}"
                    )
                normalized_matcher = "edit"
            elif event == "PreToolUse":
                if matcher != "Bash":
                    fail(f"{client} PreToolUse matcher must be 'Bash': {source}")
                normalized_matcher = "shell"
            else:
                if matcher is not None:
                    fail(f"unexpected matcher for {event}: {source}")
                normalized_matcher = "*"

            hooks = group.get("hooks")
            if not isinstance(hooks, list):
                fail(f"hooks list missing for {event}: {source}")
            for hook in hooks:
                if not isinstance(hook, dict) or hook.get("type") != "command":
                    fail(f"non-command hook for {event}: {source}")
                command = hook.get("command")
                if not isinstance(command, str):
                    fail(f"hook command is not a string for {event}: {source}")
                match = re.search(r"\.agentic/hooks/([A-Za-z0-9_.-]+\.sh)", command)
                if not match:
                    fail(f"hook does not call .agentic/hooks script: {source}")
                script = match.group(1)
                script_path = script_root / script
                if not script_path.is_file():
                    fail(f"missing hook script {script_path} referenced by {source}")
                if not os.access(script_path, os.X_OK):
                    fail(f"hook script is not executable: {script_path}")

                has_codex_flag = bool(
                    re.search(r"(^|\s)--codex(\s|$)", command)
                )
                needs_codex_flag = client == "codex" and script in {
                    "context-reminder.sh",
                    "gate-on-stop.sh",
                }
                if has_codex_flag != needs_codex_flag:
                    fail(f"wrong --codex hook flag for {script}: {source}")
                flags = tuple(
                    flag
                    for flag in ("--hook", "--strict")
                    if re.search(
                        rf"(^|\s){re.escape(flag)}(\s|$)",
                        command,
                    )
                )
                entries.append((event, normalized_matcher, script, flags))
    return Counter(entries)


def assert_hook_matrix(
    label: str,
    actual: Counter[HookEntry],
    expected: list[HookEntry],
) -> None:
    wanted = Counter(expected)
    if actual != wanted:
        missing = list((wanted - actual).elements())
        extra = list((actual - wanted).elements())
        fail(f"{label} hook matrix differs; missing={missing}, extra={extra}")


python_default: list[HookEntry] = [
    ("SessionStart", "*", "branch-check.sh", ()),
    ("PreToolUse", "shell", "block-destructive.sh", ()),
    ("PostToolUse", "edit", "format-after-edit.sh", ()),
    ("PostToolUse", "edit", "specs-status.sh", ("--hook",)),
    ("PreCompact", "*", "context-reminder.sh", ()),
    ("Stop", "*", "gate-on-stop.sh", ()),
]
python_strict = [
    (
        event,
        matcher,
        script,
        ("--strict",) if script == "format-after-edit.sh" else flags,
    )
    for event, matcher, script, flags in python_default
]
python_no_stop = [
    entry for entry in python_default if entry[0] != "Stop"
]
generic_default: list[HookEntry] = [
    ("SessionStart", "*", "branch-check.sh", ()),
    ("PreToolUse", "shell", "block-destructive.sh", ()),
    ("PreCompact", "*", "context-reminder.sh", ()),
]

python_claude_path = root / ".claude" / "settings.json"
python_claude = load_json(python_claude_path)
assert_hook_matrix(
    "Python Claude",
    hook_matrix(
        python_claude,
        client="claude",
        source=python_claude_path,
        script_root=root / ".agentic" / "hooks",
    ),
    python_default,
)

codex_hook_paths = {
    path.name: path for path in (root / ".codex").glob("hooks*.json")
}
assert_inventory(
    "Codex hook variant",
    {"hooks.json", "hooks.strict.json", "hooks.no-stop.json"},
    set(codex_hook_paths),
)
for filename, expected in (
    ("hooks.json", python_default),
    ("hooks.strict.json", python_strict),
    ("hooks.no-stop.json", python_no_stop),
):
    path = codex_hook_paths[filename]
    assert_hook_matrix(
        f"Python Codex {filename}",
        hook_matrix(
            load_json(path),
            client="codex",
            source=path,
            script_root=root / ".agentic" / "hooks",
        ),
        expected,
    )

generic_claude_path = generic / ".claude" / "settings.json"
generic_codex_path = generic / ".codex" / "hooks.json"
assert_hook_matrix(
    "generic Claude",
    hook_matrix(
        load_json(generic_claude_path),
        client="claude",
        source=generic_claude_path,
        script_root=shared / "hooks",
    ),
    generic_default,
)
assert_hook_matrix(
    "generic Codex",
    hook_matrix(
        load_json(generic_codex_path),
        client="codex",
        source=generic_codex_path,
        script_root=shared / "hooks",
    ),
    generic_default,
)
PY

bash "$REPO_DIR/scripts/validate-safety-guardrails.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

bash "$PYTHON_DIR/.agentic/hooks/context-reminder.sh" --codex \
  | python3 -m json.tool >/dev/null

fixture_project="$tmp_dir/project"
mkdir -p "$fixture_project/.agentic/hooks" "$fixture_project/docs/specs"
cp "$PYTHON_DIR/.agentic/hooks/specs-status.sh" \
  "$fixture_project/.agentic/hooks/specs-status.sh"
cp "$PYTHON_DIR/.agentic/hooks/gate-on-stop.sh" \
  "$fixture_project/.agentic/hooks/gate-on-stop.sh"
printf '%s\n' \
  '# Specs' \
  '<!-- specs-status:start -->' \
  '<!-- specs-status:end -->' \
  >"$fixture_project/docs/specs/README.md"
printf '%s\n' \
  '# Fixture' \
  '' \
  '**Status:** draft' \
  >"$fixture_project/docs/specs/0001-fixture.md"
(
  cd "$fixture_project"
  printf '%s\n' \
    '{"tool_input":{"command":"*** Update File: docs/specs/0001-fixture.md"}}' \
    | bash .agentic/hooks/specs-status.sh --hook
)
grep -q '\[Fixture\](0001-fixture.md)' \
  "$fixture_project/docs/specs/README.md" \
  || fail "spec-dashboard hook ignored Codex apply_patch fixture"

mkdir -p "$fixture_project/src" "$fixture_project/tests" "$tmp_dir/bin"
printf '%s\n' 'x = 1' >"$fixture_project/src/changed.py"
printf '%s\n' '#!/usr/bin/env sh' 'exit 1' >"$tmp_dir/bin/uv"
chmod +x "$tmp_dir/bin/uv"
git -C "$fixture_project" init -q
stop_output="$(
  cd "$fixture_project"
  printf '%s\n' '{"stop_hook_active":false}' \
    | PATH="$tmp_dir/bin:$PATH" \
      bash .agentic/hooks/gate-on-stop.sh --codex
)"
printf '%s\n' "$stop_output" \
  | python3 -c \
    'import json,sys; data=json.load(sys.stdin); assert data["decision"] == "block"'

legacy_project="$tmp_dir/legacy-project"
mkdir -p "$legacy_project/.claude/rules" "$legacy_project/src" \
  "$legacy_project/tests"
printf '%s\n' \
  '# AGENTS.md' \
  '' \
  'This portable fallback says the authoritative content lives in `CLAUDE.md`.' \
  >"$legacy_project/AGENTS.md"
printf '%s\n' \
  '# Project: migration-fixture' \
  '' \
  'CUSTOMIZED CONTRACT MUST SURVIVE' \
  >"$legacy_project/CLAUDE.md"
printf '%s\n' \
  '# Local rule' \
  '' \
  'CUSTOMIZED RULE MUST SURVIVE' \
  >"$legacy_project/.claude/rules/local.md"
(
  cd "$legacy_project"
  bash "$PYTHON_DIR/bootstrap.sh" --update --minimal >/dev/null
)
assert_agents_import "$legacy_project/CLAUDE.md"
grep -q 'CUSTOMIZED CONTRACT MUST SURVIVE' "$legacy_project/AGENTS.md" \
  || fail "legacy contract migration overwrote customized policy"
grep -q 'CUSTOMIZED RULE MUST SURVIVE' "$legacy_project/AGENTS.md" \
  || fail "legacy contract migration dropped a project rule"
[[ ! -e "$legacy_project/.claude/rules/local.md" ]] \
  || fail "legacy migration left a duplicate Claude-specific rule behind"
grep -q '<!-- agentic-scaffold:standing-rules:start -->' \
  "$legacy_project/AGENTS.md" \
  || fail "legacy contract migration omitted managed rule markers"
[[ -f "$legacy_project/.codex/config.toml" ]] \
  || fail "legacy update did not install Codex project config"
(
  cd "$legacy_project"
  bash "$PYTHON_DIR/bootstrap.sh" --update --minimal >/dev/null
)
assert_agents_import "$legacy_project/CLAUDE.md"
grep -q 'CUSTOMIZED CONTRACT MUST SURVIVE' "$legacy_project/AGENTS.md" \
  || fail "managed rule refresh overwrote customized policy"
grep -q 'CUSTOMIZED RULE MUST SURVIVE' "$legacy_project/AGENTS.md" \
  || fail "managed rule refresh dropped project-local migrated rules"

printf 'Codex adapter validation OK (Python root %s, root+nested %s, generic %s; default limit %s, configured %s).\n' \
  "$contract_bytes" "$representative_chain_bytes" "$generic_contract_bytes" \
  "$default_contract_limit" "$contract_limit"
