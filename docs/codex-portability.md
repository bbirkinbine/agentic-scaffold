# Codex CLI portability plan

Status: implementation in progress on `feat/codex-cli-parity` (2026-07-30).
The shared source layer, complete contract, Codex project surface, dual-client
bootstraps for both repository flavors, adapter validation, and flavor/profile
smoke coverage are implemented. Fresh-project authenticated workflow
acceptance in both Claude Code and Codex remains before this plan can be
marked complete.

Verification baseline: 2026-07-30, official Codex documentation and
`codex-cli 0.146.0`. Recheck paths, schemas, trust behavior, and CLI flags
against the current Codex release when implementation changes those surfaces.

## Target

"100% Codex CLI support" means a fresh project created by this scaffold can
be used from Codex without asking Codex to discover or translate Claude-only
files by hand:

- Codex loads the complete project contract from `AGENTS.md`.
- The Spec → Plan → Test-first → Implement → Verify loop has a Codex-native
  entry point for every phase.
- Planner, test-first, analyzer, reviewer, adversarial-review, security,
  performance, and evaluator roles are available as Codex custom agents where
  enabled.
- Reusable workflow guidance is available as Codex skills.
- Safety, formatting, spec-dashboard, compaction, and turn-end checks run
  through Codex hooks or repository tooling.
- Repository skills load from `.agents/skills/`, while Codex configuration,
  custom agents, hooks, and command rules load from the trusted project
  `.codex/` layer.
- `bootstrap.sh --update` manages both the Claude and Codex surfaces.
- Claude Code remains supported with no duplicated policy that can silently
  diverge.
- The workflow remains usable in `codex exec` as well as the interactive CLI.
- A user can switch clients during a feature without regenerating the
  scaffold or changing the spec, plan, test, review, or verification
  artifacts.

The Python flavor supplies the full workflow named above. The generic flavor
supplies the same complete client contract and stack-neutral safety layer as
its Claude surface, but deliberately does not invent language-specific
formatting, testing, CI, workflow skills, or specialist agents. Its parity
test is same policy and guardrails in both clients; its validation commands
remain a project-specific placeholder the owner must fill.

This does not mean that Claude and Codex use identical filenames, schemas, or
interactive commands. It means that the repository exposes equivalent
behavior through each client’s supported integration surface.
Interchangeability applies to the repository contract, workflows, and
artifacts; live conversation state and client-specific UI are not portable
between clients.

## Workflow fidelity and quality bar

Codex support is not complete merely because Codex can open the repository
and edit Python files. The migration must preserve the scaffold's purpose:
producing accurate, maintainable, high-quality Python software through an
agentic workflow that resists shallow, unverified, or over-generated output.

The Codex orchestrator must follow the same scaled workflow as Claude Code:

| Task size | Required workflow |
| --- | --- |
| Trivial — rename, typo, about 10 lines or fewer | Branch optional; skip spec and plan; make the focused change and verify it. |
| Small — one function or one file | Branch; one-sentence spec; test-first required; plan optional. |
| Medium — 3–10 files | Full Spec → Plan → Test-first → Implement → Verify loop. |
| Large — new subsystem or cross-cutting refactor | Record the architectural decision in an ADR, split into Medium specs, and run the full loop for each. |

For Medium and Large work, Codex must act as an orchestrator rather than an
unstructured code generator:

1. Read the active product spec, feature spec, applicable ADRs, and repository
   instructions before proposing changes.
2. Create or select the feature branch before implementation.
3. Produce a read-only file-by-file plan and stop at the human plan-approval
   checkpoint.
4. Delegate test authoring to the test-first agent. That agent may edit tests
   and run pytest, but must not edit implementation files.
5. Prove that the new tests fail for the expected behavioral reason. An import
   typo, broken fixture, or unrelated failure does not satisfy the red phase.
6. Implement only the behavior required to make the approved tests and spec
   pass. Do not add speculative abstractions or adjacent features.
7. Cross-check the spec, tests, and diff when `/analyze` or its Codex workflow
   equivalent is installed.
8. Run the complete local gate: Ruff lint, Ruff formatting, strict mypy, and
   pytest. A partial or red gate is not success.
9. Delegate review to fresh read-only reviewer context that did not participate
   in implementation. Use both collaborative and adversarial review on
   meaningful changes, plus enabled security, performance, or product-eval
   specialists when their triggers apply.
10. Resolve `[auto-fix]` findings and rerun the gate. Stop and ask the human on
    `[ask-user]` findings because they change product intent or a deliberate
    trade-off.
11. Stop at the post-verification checkpoint before commit. Never commit or
    push without the human authorization required by the repository contract.

Bug fixes have an additional invariant: reproduce the failure first, then add
a test that fails for the diagnosed cause, and only then implement the fix.
The required evidence is a meaningful red → green transition, not merely a
new test that passes after the code is written.

On multi-session work, the spec is durable state. Codex must append the
documented `## Phase handoff` block at phase boundaries and resume from the
latest handoff in a fresh session rather than relying on conversation memory.

### What "no AI slop" means operationally

Use objective review and verification rules rather than treating this phrase
as a style preference. Generated work is not acceptable when it contains any
of the following without explicit human approval:

- implementation before an approved spec or required failing tests;
- tests that only exercise code, mirror the implementation, or assert the
  function against itself rather than pinning required behavior;
- invented paths, APIs, constraints, benchmark results, citations, external
  constants, test vectors, or source provenance;
- fabricated or single-source round-trip fixtures presented as independent
  correctness evidence;
- undeclared scope, implementation of a spec non-goal, or speculative
  abstractions for features that do not exist;
- new dependencies without the dependency-hygiene decision covering
  maintenance, license, advisories, and standard-library alternatives;
- missing strict types, stale or tautological public docstrings, concealed
  side effects, or oversized mixed-responsibility modules;
- swallowed failures, placeholder implementations, disabled checks, weakened
  assertions, or claims of success without the command output that proves
  them;
- secrets, internal context, incompatible copied material, or unverified
  external-authority values in a public repository;
- review findings rationalized away by the implementation context instead of
  independently adjudicated.

The scaffold enforces this quality bar in layers:

1. **Behavioral contract:** `AGENTS.md`, workflow skills, and custom-agent
   instructions define required order, scope, and role separation.
2. **Lifecycle guardrails:** sandbox and approval settings plus hooks warn,
   block supported destructive operations, format edits, preserve handoff
   context, and prevent a red strict gate from being reported as complete.
3. **Independent evaluation:** analyze, reviewer, adversarial reviewer, and
   opt-in specialists test semantic agreement with the spec beyond what lint
   and unit tests can see.
4. **Repository enforcement:** pre-commit and CI run client-independent
   quality, hygiene, and supply-chain gates even if an agent skips a local
   workflow step.

The first two layers strongly steer and constrain the agent, but they are not
a proof of program correctness and hooks do not intercept every possible tool
path. The executable gates and fresh-context review are therefore mandatory.
Do not claim stronger enforcement for Codex than the scaffold provides for
Claude Code.

## Implementation status

The portability gap described in the original plan is now represented by
generated, testable client adapters:

- `workflow/` is the client-neutral source for the complete project contract,
  phase workflows, reusable skills, roles, and standing rules.
- `AGENTS.md` is the canonical rendered contract; `CLAUDE.md` imports it
  through Claude Code's supported `@AGENTS.md` syntax.
- Claude Code keeps Markdown commands/agents/skills under `.claude/`; Codex
  receives workflow skills under `.agents/skills/` and custom-agent TOML
  under `.codex/agents/`.
- `.agentic/hooks/` contains shared shell logic. `.claude/settings.json` and
  `.codex/hooks.json` provide client-specific lifecycle schemas.
- `.codex/config.toml` supplies the project permission profile and feature
  settings; `.codex/rules/safety.rules` covers narrow command-execution
  decisions rather than duplicating behavioral policy.
- `bootstrap.sh` installs both surfaces for every profile, persists profile
  and hook-mode choices across flagless updates, protects customized client
  configuration, prunes only unchanged managed files on profile shrink, and
  migrates recognizable pointer, duplicate-contract, and Claude-only layouts.
- `scripts/validate-codex-adapters.sh` and the profile smoke tests reject
  source drift, malformed TOML/JSON, orphan adapters, incomplete hook matrices,
  instruction-budget overflow, broken safety-rule decisions, unsafe update
  transitions, and incomplete installations.
- `generic/bootstrap.sh` installs a canonical generic contract plus Claude
  import, shared
  hooks, both clients' project configuration, Codex rules, and its startup
  guide; `scripts/smoke-test-generic.sh` covers fresh installs, updates, and
  legacy-pointer migration.

The remaining gap is execution evidence, not another adapter design:
authenticated Claude Code and Codex runs from the same fresh bootstrapped
project must demonstrate the Medium workflow acceptance case below, with an
additional interactive Codex trust check.

## Implementation preflight

An agent implementing this plan must not work from this document alone. Before
editing, read and inventory both scaffold flavors and their shared sources:

- `generic/project-contract.md`, `generic/bootstrap.sh`,
  `generic/.claude/settings.json`, `generic/.codex/hooks.json`, and
  `generic/docs/codex-cli.md`;
- `shared/hooks/` and `shared/codex/`;
- `python/README.md`, `python/WORKFLOW.md`, `python/CLAUDE.md`, and
  `python/AGENTS.md`;
- every source under `python/workflow/`, every rendered hook under
  `python/.agentic/hooks/`, and the client adapters under
  `python/.claude/`, `python/.agents/`, and `python/.codex/`;
- `python/.claude/settings.json`, `python/bootstrap.sh`, and
  `scripts/smoke-test.sh`;
- `python/pyproject.toml`, `.pre-commit-config.yaml`, the Python GitHub Actions
  workflows, issue and PR templates, and Dependabot configuration;
- `python/docs/project-types.md`, `workflow-diagram.md`, `specs/README.md`,
  `adr/README.md`, `agent-handoff.md`, `parallel-agents.md`,
  `serena-setup.md`, `plugin-packaging.md`, `evals.md`, and `llm-product.md`.

Record the current profile membership, opt-in behavior, permissions, inputs,
outputs, checkpoints, and verification commands before generating any Codex
adapter. Preserve existing Claude behavior and unrelated user changes. Verify
all version-sensitive Codex paths, schemas, trust rules, hook payloads, and CLI
flags against the current official documentation and installed CLI rather
than relying only on the verification baseline recorded above.

## Design decisions

### 1. Make `AGENTS.md` the shared instruction authority

Move the durable repository contract into `AGENTS.md`, because Codex loads it
by default. Keep `CLAUDE.md` as the one-line `@AGENTS.md` import supported by
Claude Code. This gives both clients one policy authority without relying on
symlink support on Windows or maintaining two generated copies.

Do not leave a short pointer as the only Codex-facing file. A pointer may be
kept as an explanatory note inside the shared contract, but the full rules
must be in the file Codex automatically loads.

Codex stops adding discovered instruction files when their combined size
reaches `project_doc_max_bytes` (32 KiB by default). The generated contract
must fit under that default with deliberate headroom, or the project config
must raise and test the limit. CI must measure the complete root-to-working-
directory instruction chain, not just the root file. Prefer concise root
guidance plus nested `AGENTS.md` files for genuinely subtree-specific rules;
do not split global rules into nested files merely to evade the limit. Codex
discovers the chain only through its launch directory, so a nested file
requires `codex --cd <subtree>` (or an equivalent working directory) and must
not be the sole home of a critical global rule.
As of 2026-07-30, the rendered Python root contract is 26,575 bytes, the
representative root-plus-nested chain is 27,643 bytes, and the generic
contract is 8,724 bytes. All remain below Codex's 32 KiB default before the
project layer is trusted; the checked-in config raises
`project_doc_max_bytes` to 65,536 afterward. The adapter validator measures
both limits and the representative chain. Re-measure after every
standing-rule or contract change.

The shared contract should use client-neutral language. Client-specific
commands belong in a command/skill mapping table, not in the core rules.

### 2. Keep policy in shared files and adapters in client directories

Create a neutral source layer for workflow text and role instructions, then
render or copy thin adapters into each client surface:

```text
shared/
  hooks/
  codex/

generic/
  project-contract.md
  .claude/
  .codex/

python/
  workflow/
    rules/
    commands/
    roles/
    skills/

.agentic/
  hooks/

.claude/
  agents/
  commands/
  rules/
  settings.json

.agents/
  skills/                 # repository skills discovered by Codex

.codex/
  agents/
  hooks.json
  config.toml
  rules/
```

The neutral layer is the source of truth. Claude Markdown, Codex TOML, hook
configuration, and client-specific command wrappers are generated or
updated from it. The generator must fail on missing source entries instead of
silently producing a partial client surface.

The tree above mixes repository-level sources and installed adapters. In this
repository, stack-neutral hook/config sources live at the root, generic
contract sources live under `generic/`, and Python workflow sources live
under `python/workflow/`:

```text
shared/hooks/...
shared/codex/...
generic/project-contract.md
python/workflow/...
python/.claude/...
python/.agents/skills/...
python/.codex/...
```

`python/workflow/` is the scaffold's neutral authoring layer and does not need
to be copied into every consumer project. `python/bootstrap.sh` installs the
rendered project surfaces at the consumer repository root:

```text
AGENTS.md
CLAUDE.md                 # symlink or synchronized representation
.claude/...
.agents/skills/...
.codex/...
WORKFLOW.md
```

Files required outside `.codex/` are therefore part of the implementation,
not optional documentation work: the authoritative `AGENTS.md`, compatible
`CLAUDE.md`, repository skills under `.agents/skills/`, the neutral workflow
sources, dual-client bootstrap logic, adapter validators and smoke tests, and
client-neutral usage documentation. Existing client-independent files such as
`pyproject.toml`, specs, ADRs, pre-commit, CI, and Dependabot remain shared
rather than receiving Codex copies.

### 3. Treat commands as workflows, not filenames

Each existing Claude command needs a mapping entry with:

- workflow name and purpose;
- required inputs and output artifact;
- Claude entry point, such as `/plan`;
- Codex entry point, such as a project skill or explicit `codex exec`
  prompt;
- whether it may edit files;
- verification command;
- whether the workflow is available in minimal, Python-core, or full mode.

The plan must cover at least `spec`, `product-spec`, `scope-check`, `clarify`,
`adr`, `plan`, `test-first`, `analyze`, `review-check`, `review`,
`review-adversarial`, `security`, `performance`, `eval`, and `specs-status`.

If Codex does not provide a stable custom slash-command mechanism for a
workflow, expose the workflow as a skill and document the equivalent
`codex exec` invocation. Do not claim that a Claude slash command is
available in Codex when it is not.

Repository skills belong under `.agents/skills/<name>/SKILL.md`. Document
explicit skill invocation with `$<name>` or the `/skills` selector, while
allowing Codex to select the skill implicitly from its description. Keep the
Claude adapter under `.claude/skills/` when Claude Code requires that path;
generate both from the same neutral skill source.

The adapters must preserve phase boundaries and permissions, not only names:

| Workflow | Codex entry point | Role and required result |
| --- | --- | --- |
| `product-spec` | Skill | Interview one question at a time; write or refresh `docs/specs/0000-product.md`; stop for review. |
| `scope-check` | Skill | Ask the five forcing questions; return the scope summary; do not create code. |
| `spec` | Skill | Create the numbered feature spec from the issue or local sequence; mark assumptions; stop for human ownership. |
| `clarify` | Skill | Ask at most five high-leverage questions one at a time and fold each answer into the draft spec. |
| `adr` | Skill | Draft the independently numbered decision record; never proceed to implementation. |
| `plan` | Skill plus read-only `planner` agent | Survey real paths and return files, ordered operations, risks, decisions, and out-of-scope; write no code. |
| `test-first` | Skill plus test-writing agent | Edit tests only, run the focused tests, and return expected failing output before implementation. |
| `analyze` | Skill plus read-only `analyzer` agent | Build success-criterion coverage and spec ↔ tests ↔ diff consistency findings; change nothing. |
| Implement | Main Codex orchestrator | Make the smallest implementation satisfying the approved spec and failing tests. |
| `review-check` | Skill | Run Ruff lint and formatting, strict mypy, and pytest; refuse a passing verdict on any failure. |
| `review` | Skill plus read-only `reviewer` agent | Independently assess spec match, test quality, edge cases, side effects, hygiene, and provenance. |
| `review-adversarial` | Skill plus read-only adversarial agent | Argue against merging without inventing speculative requirements; use the same finding schema. |
| `security` | Skill plus optional read-only security agent | Produce evidence-based application-security findings when the project or diff triggers it. |
| `performance` | Skill plus optional read-only performance agent | Produce evidence-based performance findings and measurement commands; do not invent benchmarks. |
| `eval` | Skill plus optional evaluator agent | Author cases from the spec and external data, stop for rubric approval, or run the suite against the approved threshold. |
| `specs-status` | Skill plus shared repository script | Refresh the generated dashboard from spec status fields and report it. |

Each Codex skill must stop at the same checkpoint as the corresponding Claude
command. A single convenience skill must not silently collapse spec, plan,
tests, implementation, review, and commit into one unreviewed operation.

### 4. Translate agents instead of copying them

For each Claude agent, create a Codex custom-agent TOML file with:

- `name`;
- `description`;
- `developer_instructions` copied from the neutral role definition;
- an explicit read-only sandbox for reviewers and analyzers;
- a write-capable sandbox only for roles that are intended to edit;
- model and reasoning settings only when the workflow has a documented need.

The Codex files belong under `.codex/agents/`; one standalone TOML file
defines each project-scoped custom agent. The translation test must parse
every generated TOML file and verify required fields.

Custom-agent sandbox settings are defaults, not an isolation boundary.
Subagents inherit the parent session policy, and live parent overrides can
supersede an agent file. Reviewer acceptance tests must therefore start from
a read-only parent session and prove that the reviewer cannot write.

Use these role boundaries:

- `planner`, `analyzer`, `reviewer`, `reviewer-adversarial`, security, and
  performance agents default to `sandbox_mode = "read-only"`.
- `test-first` needs workspace write access to create tests, but its
  instructions forbid implementation edits. Because Codex sandbox modes are
  not test-directory allowlists, acceptance must inspect the agent's diff and
  fail if it changed `src/` or other implementation paths.
- The evaluator may write only when authoring an opted-in eval suite; its run
  and judge modes should otherwise be read-only where practical.
- The main orchestrator owns implementation. Review agents recommend changes
  and never rewrite the code they are judging.

Preserve the existing structured outputs, including the planner's files and
order, the analyzer's criterion-coverage table, reviewer finding tags, and
specialist evidence plus verification commands. These schemas are part of
the workflow contract because later phases and human checkpoints consume
them.

Claude agents remain under `.claude/agents/` for Claude Code. Their prompts
must be generated from the same role source so review criteria do not diverge.

### 5. Port hooks with Codex’s hook contract

Retain the shell logic where it is client-neutral, but add Codex-specific
wiring and payload tests. The Codex layer should cover:

- session-start branch warning;
- pre-tool destructive-command block;
- post-edit formatting and spec-dashboard refresh;
- pre-compaction context-preservation reminder;
- stop-time quality gate when strict hooks are enabled.

It must also preserve or explicitly classify the non-hook behavior currently
carried by Claude settings:

- `.env`, `.env.*`, `*.pem`, and `*.key` read protection needs a tested
  Codex-native control or an explicit documented limitation. Command rules
  alone are not equivalent to Claude's `Read(...)` deny entries.
- The Claude status line is client UI customization. Provide a supported
  Codex alternative if one exists at implementation time, otherwise mark it
  as a deliberate client-specific difference.
- `strip-ai-attribution.sh` is already a pre-commit `commit-msg` hook and
  remains shared repository tooling; it does not need a Codex lifecycle-hook
  adapter.

Codex hook configuration belongs in `.codex/hooks.json` or the supported
project `config.toml` hook tables. Hook matchers and stdin payloads must be
tested against Codex examples; Claude’s JSON payload assumptions must not be
reused without verification.

In particular:

- `PostToolUse` can match Codex file edits with `apply_patch`, `Edit`, or
  `Write`, but Codex reports the canonical tool name as `apply_patch`. The
  existing spec-dashboard hook expects Claude's `file_path` field and needs a
  Codex payload adapter rather than a path-only copy.
- Codex ignores plain stdout from `PreCompact`. The current inline `echo`
  must become valid Codex JSON output, such as a `systemMessage`, and receive
  a payload test.
- The Stop adapter must honor `stop_hook_active` so a red quality gate causes
  at most one automatic continuation before the failure is returned to the
  user.
- Codex currently intercepts only supported tool paths and not every shell or
  built-in operation. Treat `PreToolUse` as a guardrail, not a complete
  enforcement boundary.

The safety model should have three independent layers:

1. Codex sandbox and approval configuration;
2. Codex hooks for turn/tool lifecycle enforcement;
3. repository-level pre-commit and CI checks that work with no agent.

The third layer remains authoritative for anything that must survive a
different client or a bypassed local hook.

Project hooks load only from a trusted `.codex` layer. The bootstrap output
and usage guide must explain the trust step without recommending
`--dangerously-bypass-hook-trust` as normal operation. Acceptance tests must
cover trusted and untrusted fresh-project behavior separately.

### 6. Separate behavioral guidance from command policy

Translate `.claude/rules/` content that describes coding behavior into the
shared `AGENTS.md` contract or nested `AGENTS.md` files. Do not copy those
files into `.codex/rules/`: Codex rules are for command execution policy,
not a general replacement for repository guidance.

Add Codex command rules only for deliberate approval/forbidden decisions,
such as destructive commands or approved quality-gate prefixes. Keep the
rules narrow, store project rules as `.rules` files under `.codex/rules/`,
and test them with `codex execpolicy check`.

### 7. Make bootstrap dual-client by default

Update `python/bootstrap.sh` so every Python profile installs the shared
contract and both client surfaces. Add `generic/bootstrap.sh` so the
stack-neutral flavor does the same without inheriting Python-specific
workflow or validation. Preserve existing invocations and add options only
where they clarify intent, for example:

- `--claude-only` for legacy Claude-only projects;
- `--codex-only` for projects that do not want Claude files;
- default behavior: both clients.

The managed-file inventory must include `.agents/skills/` and the generated
Codex adapters under `.codex/`. Project-owned files must remain protected
from `--update`, including the customized shared contract, `pyproject.toml`,
README, `.gitignore`, and handoff notes.

Update completion output, both flavor READMEs, and the new-project checklist
so a project can tell which client surfaces and hooks were installed, which
Python profile/optional roles apply, and whether the project `.codex` layer
still needs trust review.

### 8. Remove client assumptions from shared documentation

Audit every document for client-specific claims. At minimum:

- `WORKFLOW.md`: describe the loop in client-neutral terms and show both
  entry-point forms;
- `python/CLAUDE.md` / `python/AGENTS.md`: replace the pointer arrangement
  with the shared-contract arrangement;
- `python/docs/parallel-agents.md`: split Claude-specific built-ins from the
  Codex subagent/worktree equivalent;
- `python/docs/serena-setup.md`: add Codex MCP registration and identify
  which Serena context is supported;
- `python/docs/plugin-packaging.md`: keep the Claude plugin path separate
  from the Codex plugin path and document the supported overlap;
- `python/README.md` and `docs/project-types.md`: list the dual-client
  inventory and client mapping;
- root `README.md`, the generic contract templates, and
  `new-project-checklist.md`: replace the generic pointer workflow with the
  dual-client generic bootstrap;
- `.github/workflows/claude-review.yml.example`: label it as Claude-only and
  document the Codex review alternative rather than implying parity.

Use official Codex documentation links for behavior that can change:

- [AGENTS.md discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
- [Codex rules](https://learn.chatgpt.com/docs/agent-configuration/rules)
- [Codex skills](https://learn.chatgpt.com/docs/build-skills)
- [Codex CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli)

### 9. Add a Codex validation matrix

Static validation is required in CI; authenticated Codex execution is a
local validation step because CI should not require a personal Codex login.

Static checks:

- every generated `AGENTS.md` contains the complete contract and no broken
  pointer;
- the combined discovered `AGENTS.md` instruction chain stays below the
  tested `project_doc_max_bytes` budget;
- `AGENTS.md` contains the complete contract and `CLAUDE.md` is exactly the
  `@AGENTS.md` import;
- every Codex agent TOML parses and has required fields;
- every Codex hook references an existing executable script;
- every repository skill is under `.agents/skills/<name>/SKILL.md` and has
  the required `name` and `description` metadata;
- every `.codex/rules/*.rules` file passes fixture checks through
  `codex execpolicy check`;
- every workflow mapping has both client entries or an explicit
  `unsupported` reason;
- no Codex profile installs a Claude-only file as its only implementation;
- no generated path contains unresolved placeholders;
- Bash syntax, ShellCheck, smoke tests, Ruff, mypy, pytest, and pre-commit
  continue to pass.

Local Codex checks:

```bash
codex --ask-for-approval never exec --sandbox read-only \
  "List the instruction files and project agent surfaces you loaded."

codex --ask-for-approval never exec --sandbox read-only \
  "Run the documented review-check workflow and report its verification commands."
```

`--ask-for-approval` is a global flag and must appear before the `exec`
subcommand. Do not copy examples that place it after `exec`; current Codex
CLI rejects that ordering.

The local checklist must verify that Codex:

- loads root and nested `AGENTS.md` files in the expected order;
- stays within the configured instruction byte budget without truncating the
  project contract;
- can invoke the planner, test-first, and reviewer roles;
- recognizes the installed skills;
- loads project agents, hooks, config, and rules after the project is trusted,
  and does not silently claim they loaded when the project is untrusted;
- runs the destructive-command hook and blocks its test fixtures;
- preserves the documented secret-read protection or reports the approved
  client limitation;
- runs the formatting/spec-dashboard hook on an edit fixture;
- stops or reports a failure when the strict quality gate is red;
- produces the same required artifacts as the Claude workflow.

### End-to-end workflow acceptance

Run at least one authenticated acceptance feature from a fresh temporary
project produced by each relevant bootstrap profile. Use a deliberately small
but Medium-shaped fixture with a feature spec, existing source, and tests. The
acceptance record must show, in order:

1. Codex loaded the root contract, applicable nested instructions, skills,
   custom agents, hooks, and command policy after normal trust review.
2. The orchestrator selected the correct active spec and feature branch.
3. The planner ran read-only, cited real repository paths, declared
   out-of-scope work, and stopped before test or implementation edits.
4. After explicit plan approval, the test-first agent changed tests but no
   implementation files and captured a failure caused by the missing required
   behavior.
5. The orchestrator implemented only the approved scope and produced the
   expected red → green transition.
6. The analyzer, when installed, mapped every success criterion to a
   meaningful test and found no undeclared behavior.
7. `review-check` ran every configured command and refused success if any one
   was red.
8. Fresh read-only collaborative and adversarial reviewers evaluated the diff
   against the spec and returned the required finding tags.
9. `[auto-fix]` findings were resolved followed by another full gate, while a
   seeded `[ask-user]` product decision stopped for human input.
10. Codex stopped before commit and reported the spec, changed files, tests,
    gate results, and unresolved decisions.

Add separate negative fixtures that prove the quality boundaries:

- an ambiguous spec makes test-first stop rather than guess;
- a bug fix cannot be accepted without reproduction and a cause-specific red
  test;
- a tautological or implementation-mirroring test is rejected in analysis or
  review;
- a proposed direct dependency triggers the dependency-hygiene decision
  before `uv add` or a manifest edit;
- a fabricated external reference or unpinned authoritative value is caught;
- implementation of a declared non-goal is reported as scope creep;
- a reviewer launched read-only cannot edit the workspace;
- a red hook or CI fixture cannot be summarized as passing;
- sensitive-file and destructive-command fixtures exercise the documented
  Codex protection or the approved client limitation.

Where practical, capture `codex exec --json` event output and repository diffs
as acceptance evidence. Do not treat a model's statement that it followed the
workflow as proof; verify the artifact order, file boundaries, and command
results independently.

### 10. Test all bootstrap profiles

Extend `scripts/smoke-test.sh` for `minimal`, `python-core`, and `full`,
including strict-hook variants. Each profile should assert the intended
Codex file set just as it currently asserts the Claude file set.

Add a separate adapter smoke test that runs without an API login and checks:

- directory and file inventory;
- executable permissions;
- JSON/TOML syntax;
- hook references;
- hook payload fixtures for every supported Codex event;
- rule fixtures through `codex execpolicy check`;
- the combined `AGENTS.md` instruction byte budget;
- workflow mapping completeness;
- the canonical AGENTS/CLAUDE import relationship.

Run a manual Codex acceptance pass after each change to Codex config or
agent schema, because CLI schema and trust behavior can change independently
of this repository.

## Implementation order

1. [x] Inventory the current commands, agents, skills, rules, hooks, and
   advanced documents.
2. [x] Build the neutral source layer and make `AGENTS.md` authoritative.
3. [x] Add Codex agent translations and skill/workflow adapters.
4. [x] Add Codex hook configuration and payload handling.
5. [x] Add narrow Codex command-policy rules.
6. [x] Update both flavors, profiles, `--update`, inventories, and opt-in-role
   handling.
7. [x] Rewrite shared documentation and add the Codex usage guide.
8. [x] Add static adapter validation and extend all profile smoke tests.
9. [ ] Complete the full Medium authenticated acceptance case in both Claude
   Code and Codex from the same fresh temporary project. A read-only
   authenticated Codex load test already proves the
   Python strict config, complete contract, `$spec` skill discovery, and Stop
   hook. A separate generic load test proves its strict config, complete
   contract, and ask-for-real-validation behavior while placeholders remain.

   Hook-layer enforcement is verified live (2026-07-30, Codex CLI 0.146.0,
   authenticated `codex exec` against a fresh temp repo, hook trust
   bypassed because the probe authored its own hooks). Each invocation ignores
   user configuration and marks only its fresh fixture as a trusted project
   through a CLI override; authentication remains in the caller's
   `CODEX_HOME`. `PreToolUse` with
   `matcher: "Bash"` fires on shell commands (a `"shell"` matcher never
   fires — `Bash` is canonical); the stdin payload carries `tool_name` and
   `tool_input.command` in the Claude-compatible shape the shared hooks
   parse; a non-zero hook exit denies the tool call with stderr relayed to
   the model as the reason — `git clean -fd` was refused and an untracked
   canary file survived; `PostToolUse` fires with `tool_name:
   "apply_patch"` on file edits; the `Stop` hook runs at turn end.

   The execpolicy layer is likewise verified live with a control: a fresh
   project carrying only `.codex/rules/safety.rules` (no hooks) refused
   `git clean -fd` and the canary survived; the identical run with the
   rules file removed executed the command and deleted it. Codex therefore
   auto-loads project rules at runtime — the layer is enforcement, not
   documentation.

   These probes are repeatable: `bash scripts/acceptance-codex-live.sh`
   (authenticated Codex required; spends real tokens; not a CI gate). Run
   it after any change to `shared/codex/`, to hook payload parsing, or a
   Codex CLI upgrade. Still manual: persisted hook-definition review and
   trust without the bypass flag, plus the interactive project-trust flow and
   the full Medium workflow case below.

   The dual-client phase harness is
   `bash scripts/acceptance-workflow-live.sh --confirm-token-use`. It gives
   Claude Code and Codex separate copies of the same committed Medium fixture,
   runs fresh plan, test-first, implementation, and review sessions, and
   independently checks the read-only plan/review boundaries, named custom
   agent starts through an acceptance-only `SubagentStart` hook, test-only
   failure, cause-specific red result, approved path set, real
   Ruff/mypy/pytest gate, docs/spec closure, and absence of an agent commit.
   Codex invocations ignore user configuration and explicitly trust only the
   temporary fixture through a CLI override. The harness is intentionally
   excluded from CI and refuses to run without the explicit token-use flag.
   Passing it still does not replace the interactive Codex trust check,
   persisted hook-definition trust, or the separate negative fixtures listed
   in the acceptance section.
10. [x] Complete the final public-repo hygiene and adapter-drift diff review.

## Completion criteria

The migration is complete when all of the following are true:

- A new project opened with Codex receives the full contract from
  `AGENTS.md` without opening `CLAUDE.md` manually.
- Every workflow in the command mapping has a tested Codex invocation or an
  explicitly documented client limitation.
- Codex custom agents, skills, hooks, and command policy load from the
  generated project surfaces after normal project trust review.
- A Medium acceptance feature demonstrates the ordered plan checkpoint,
  test-only red phase, scoped implementation, full green gate, independent
  review, finding adjudication, and pre-commit stop.
- Codex refuses to invent missing requirements, external provenance, test
  evidence, benchmark results, or passing status, and stops for the human at
  the same product-decision boundaries as Claude Code.
- Generated Python changes satisfy the scaffold's strict typing, meaningful
  test, public-docstring, dependency, module-cohesion, public-hygiene, and
  external-reference rules rather than merely compiling.
- The complete instruction chain loads without exceeding the tested
  `project_doc_max_bytes` budget.
- Safety mappings cover destructive commands and sensitive-file reads, or
  document a reviewed client limitation instead of claiming false parity.
- Claude Code still loads the same behavioral policy and passes its existing
  workflow.
- All three bootstrap profiles and strict-hook variants pass static and
  repository smoke tests.
- The generic flavor's fresh, update, and legacy-migration smoke tests pass.
- Fresh-project manual acceptance passes for interactive `codex` and
  non-interactive `codex exec`.
- A feature can begin in Claude Code and resume in Codex, or the reverse, from
  the same spec and latest phase handoff without regenerating scaffolding or
  changing workflow artifacts.
- README, `python/README.md`, `WORKFLOW.md`, and the orientation docs explain
  the dual-client model without treating one client’s terminology as a
  universal standard.

## Explicit non-goals

- Do not make Codex emulate Claude’s private settings schema.
- Do not claim identical slash-command syntax across clients.
- Do not require a global `~/.codex` modification for a checked-out project
  to work.
- Do not use `--dangerously-bypass-hook-trust` as the documented setup path
  for ordinary interactive or non-interactive work.
- Do not describe `PreToolUse` hooks or command rules as a replacement for
  Codex sandboxing and approval controls.
- Do not weaken repository CI or pre-commit checks because an agent hook is
  available.
- Do not remove the Claude surface until the dual-client acceptance matrix
  passes and existing Claude users have a migration path.
