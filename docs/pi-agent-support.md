# Pi Agent Support

**Status:** implemented and locally validated; authenticated full-loop,
trust/reload, and local-model evidence remain open
**Last updated:** 2026-10-06

## Goal

Add Pi as a first-class client of the scaffold without creating a second workflow authority: generated projects keep `AGENTS.md`, the shared workflow sources, `.agents/skills/`, and `.agentic/toolchain.sh` canonical while receiving Pi-native prompts, specialist-role adapters, project configuration, lifecycle enforcement, documentation, and validation alongside the existing Claude Code and Codex surfaces.

## Success criteria

- Every stack flavor installs a trusted `.pi` project surface that exposes the installed workflow names as Pi slash prompts, renders the shared roles as Pi subagents, and loads the existing Agent Skills catalog without treating skill files as subagent definitions.
- Pi lifecycle wiring runs the shared branch warning, destructive-command guard, post-edit formatter/spec-dashboard refresh, and default or strict turn-end gate through the existing `.agentic` scripts and `.agentic/toolchain.sh`; `--no-stop-gate` remains effective.
- The generic flavor installs Pi project configuration and stack-neutral safety wiring but does not invent a formatter, workflow loop, specialist roles, or quality gate.
- Bootstrap install, update, profile transitions, and protected client-configuration behavior cover Pi without overwriting project customizations.
- Documentation describes Claude Code, Codex CLI, and Pi entry points, trust/reload behavior, role requirements, safety limits, and client switching without claiming sandbox parity.
- Pi support does not pin an LLM provider or model: the same adapter and workflow work with any Pi-supported remote or local model that can use the required tools.
- Static validation and flavor smoke tests reject stale or incomplete Pi adapters, malformed Pi configuration, unsafe role tool sets, missing extension targets, and broken install/update transitions.
- An explicit gap analysis records what remains unverified or weaker than Claude/Codex after implementation, including authenticated live workflow evidence and OS-level containment.

## Non-goals

- Replacing `.agentic/toolchain.sh` with a Pi-specific linter or language-server plugin.
- Making Pi extensions or subagent tool allowlists an OS security boundary.
- Adopting an independent third-party workflow state machine that would compete with specs and `AGENTS.md` as durable workflow state.
- Removing or weakening the Claude Code or Codex adapters.
- Claiming full parity before a fresh-project live Pi acceptance run demonstrates the Medium workflow.

## External references

- Pi documentation for project configuration, context files, project trust, skills, prompt templates, extensions, packages, and security: <https://pi.dev/docs>, retrieved 2026-10-05, license: MIT repository documentation.
- `pi-subagents` project-agent discovery, role frontmatter, tool allowlists, project settings, and fresh-context execution: <https://github.com/nicobailon/pi-subagents>, retrieved 2026-10-05, license: MIT. The implementation may pin an exact package version after compatibility validation.

No upstream code or documentation text will be copied. The Pi adapter will be implemented against the documented interfaces and this scaffold's existing shell contracts.

## Sketch

Render Pi prompts directly from `workflow/commands/` and Pi subagent Markdown from `workflow/roles/`. Keep `.agents/skills/` as the portable skill surface. Add a small project-local Pi extension that translates Pi lifecycle events to the existing shell hooks and requests at most one continuation when the Stop gate is red. Project `.pi/settings.json` declares the required subagent package and excludes `.agents/skills/` from legacy agent discovery. Extend the renderer, both bootstraps, adapter validation, smoke tests, and client-neutral documentation rather than editing generated flavor directories by hand. Pi roles inherit the session's selected model; no provider or model is prescribed, so Pi can orchestrate Claude, Codex-family, or local models through the same repository contract.

## Approved implementation plan

**Approved:** 2026-10-05

# Plan: Pi agent support

## Files to touch

### Authoritative adapter sources

- `shared/pi/agentic-hooks.ts` — add one project-local Pi extension source shared by stack and generic installs. It should:
  - run `branch-check.sh` at session start;
  - translate Pi shell-tool input into the JSON expected by `block-destructive.sh` and cancel on its blocking exit;
  - run formatter and spec-dashboard hooks only when their scripts exist;
  - derive strict/default/no-stop behavior from `.agentic/scaffold-state`;
  - invoke `gate-on-stop.sh` at turn end and request at most one continuation, resetting the loop guard on new user input;
  - preserve subprocess exit/output semantics rather than reimplementing hook policy.
- `workflow/client/pi/settings.json` — trusted stack-project configuration, with an exact verified `pi-subagents` package pin and positive project-agent discovery rooted only at `.pi/agents`. Do not let legacy discovery recurse through `.agents/skills`.
- `generic/.pi/settings.json` — generic Pi configuration without `pi-subagents`; load only the local safety extension.
- `scripts/render-client-surfaces.sh` — render:
  - commands to `.pi/prompts/<name>.md`;
  - roles to `.pi/agents/<name>.md` and optional roles to `.pi/agents/optional/`;
  - `shared/pi/agentic-hooks.ts` to `.pi/extensions/`;
  - the stack Pi settings.
  Keep `.agents/skills/` unchanged so Pi uses the existing Agent Skills catalog rather than receiving a third copy.
- `workflow/roles/*.md`, `workflow/roles/optional/*.md` — remain the role authority; change only if needed to make client-neutral role requirements explicit. The renderer should map their permissions to verified Pi tool names rather than copying Claude frontmatter blindly.
- `workflow/commands/{security,performance,eval}.md` — add Pi optional-agent preflight/copy paths. Review other command sources for two-client-only wording, but retain their phase boundaries and `$ARGUMENTS` behavior.

### Bootstrap and lifecycle management

- `scripts/bootstrap-stack.sh` — add Pi across the complete lifecycle:
  - `PI_SETTINGS_HASH` state and known-stock matching;
  - checksum-protected `.pi/settings.json`;
  - managed extension, prompt, and selected-role installation;
  - minimal/core/full membership and checksum-safe shrink pruning;
  - optional Pi roles excluded by default;
  - strict/default/no-stop state consumed by the extension;
  - generic-to-custom migration for both older three-config generic state and new Pi-aware state;
  - warnings when customized Pi settings prevent package/extension activation.
- `generic/bootstrap.sh` — install/update the Pi settings and extension, hash-protect settings, preserve customizations, and include Pi state in generic-to-custom migration.
- `scripts/acceptance-pi-live.sh` — add an opt-in, token-confirmed fresh-project Medium-workflow harness, parallel to the existing live acceptance scripts. It should prove prompt invocation, named subagent use, project trust/reload, and lifecycle behavior without claiming CI coverage.
- `AGENTS.md` — update validation commands, source-boundary description, current state, and the remaining live-evidence gap when implementation closes.

### Documentation

- `workflow/docs/pi.md` — Pi startup guide covering project trust, package/extension loading, reload behavior, prompt syntax, built-in skill discovery, subagents, optional roles, client switching, and the lack of sandbox parity.
- `generic/docs/pi.md` — generic-specific guide: safety wiring only, with no workflow prompts, roles, formatter, or gate.
- `workflow/{WORKFLOW.md,README.md.template,project-contract.md}` — change “both clients” language and entry-point explanations to cover Pi while keeping `AGENTS.md` authoritative.
- `workflow/docs/{project-types.md,workflow-diagram.md,plugin-packaging.md,evals.md}` — extend capability/profile tables, diagrams, packaging distinctions, optional-role instructions, and client-switch guidance.
- `workflow/docs/codex-cli.md` and `generic/docs/codex-cli.md` — keep Codex-specific content, but cross-link the Pi guide and remove statements implying only two supported clients.
- `stacks/{python,typescript,custom}/README.md` — document the rendered `.pi` inventory, profile behavior, trust/reload steps, and three-adapter optional-role copies.
- `generic/README.md`, `README.md`, `new-project-checklist.md` — update public install/setup language and the identical founding prompt where applicable; add `pi` as an entry point without overstating guardrail equivalence.
- `docs/pi-portability.md` — record the explicit gap analysis: authenticated workflow evidence, trusted-load testing, extension/package limitations, tool-allowlist limitations, and absent OS-level containment.
- `docs/influences.md` — add Pi and `pi-subagents` provenance in the same change. Pin URL, retrieval date, and license near externally defined schemas/tool names in the adapter source or an adjacent source note; do not copy upstream text.
- `docs/pi-agent-support.md` — record the approved plan, implementation notes, validation evidence, and remaining gaps in this document.

### Validation and generated output

- `scripts/validate-pi-adapters.sh` — statically verify:
  - JSON/settings validity and exact package pin;
  - complete prompt and role inventories with no orphans;
  - role body/description fidelity;
  - minimal Pi tool allowlists, especially no write/edit tools for read-only roles;
  - optional-role placement;
  - extension targets exist and use documented event names;
  - subagent discovery cannot traverse `.agents/skills`;
  - every `SKILL.md` remains a skill, never a subagent;
  - lifecycle mode and one-continuation fixtures.
- `scripts/validate-codex-adapters.sh` — retain Codex checks; only adjust shared tri-client assumptions or reusable inventory helpers.
- `scripts/smoke-test.sh` — add Pi file-set assertions for every profile, prompt/role transitions, protected settings, strict/no-stop behavior, and customized-file preservation.
- `scripts/smoke-test-{typescript,custom,generic}.sh` — cover Pi installation per flavor, generic’s absence of workflow surfaces, custom’s inactive/active runner behavior, settings preservation, and generic-to-custom migration.
- `.github/workflows/ci.yml` — install pinned validation-time Pi dependencies where required and run the Pi validator; keep authenticated acceptance manual.
- `python/`, `typescript/`, `custom/` — regenerate whole with `scripts/render-client-surfaces.sh`; never edit these trees directly. Review and commit the resulting `.pi`, prompt, role, and documentation outputs together.

## Order of operations

1. Re-fetch the declared Pi and `pi-subagents` references in-session. Select compatible exact versions and confirm settings keys, project trust, prompt arguments, skills path, extension events, cancellation, continuation, reload, and role frontmatter/tool names.
2. Add failing static and smoke fixtures for inventories, discovery isolation, lifecycle translation, profiles, protected settings, and migration.
3. Implement the shared Pi extension and stack/generic settings.
4. Extend the renderer and render all stack flavors.
5. Extend stack and generic bootstraps, including hashes, transitions, pruning, and migration.
6. Add Pi documentation, provenance, and the explicit parity-gap record.
7. Add the opt-in live harness and CI/static validation wiring.
8. Re-render once more, confirm idempotence, run the complete validation matrix, then perform spec/dashboard/current-state close-out.

## Risks / open decisions

- **Version/API drift:** no Pi schema or event name should be reconstructed from memory. Pin versions only after the declared sources and installed binaries agree.
- **Discovery collision:** prefer a positive `.pi/agents` allowlist over a broad ignore glob. A runtime inventory check must prove `.agents/skills/*/SKILL.md` never appears as an agent.
- **Role safety:** Pi tool allowlists are not an OS sandbox. Read-only roles should omit write/edit tools and, where feasible, shell access; commands should pass status/diff artifacts into reviewers. Documentation must state that allowlists and hooks are guardrails only.
- **Turn-end semantics:** the extension must own an explicit one-retry state machine; blindly replaying the existing Stop JSON could loop because Pi does not necessarily emit `stop_hook_active`.
- **Protected configuration:** a customized `.pi/settings.json` may omit the required package or extension. Preserve it, warn clearly, and provide manual reconciliation rather than overwriting it.
- **Trust:** untrusted project settings, packages, or extensions may be skipped. Bootstrap output and docs must require trust and reload verification, not imply protection is already active.
- **JSON provenance:** settings files cannot carry comments. Keep external-interface provenance in the adjacent adapter source/documentation and test the configuration against the pinned implementation.

## Validation

Run, at minimum:

```bash
bash scripts/render-client-surfaces.sh
bash -n scripts/*.sh generic/bootstrap.sh shared/hooks/*.sh workflow/hooks/*.sh stacks/*/toolchain.sh stacks/*/stack.sh
shellcheck --severity=warning scripts/*.sh generic/bootstrap.sh shared/hooks/*.sh workflow/hooks/*.sh stacks/*/toolchain.sh stacks/*/stack.sh python/bootstrap.sh typescript/bootstrap.sh custom/bootstrap.sh
bash scripts/validate-codex-adapters.sh
bash scripts/validate-pi-adapters.sh
bash scripts/smoke-test-generic.sh
bash scripts/smoke-test.sh minimal
bash scripts/smoke-test.sh core
bash scripts/smoke-test.sh full
bash scripts/smoke-test.sh core --strict-hooks
bash scripts/smoke-test.sh core --no-stop-gate
bash scripts/smoke-test-typescript.sh
bash scripts/smoke-test-typescript.sh --strict-hooks
bash scripts/smoke-test-custom.sh
```

Then run the authenticated Pi harness manually with its explicit token-use flag and retain any trust/reload limitations in the gap analysis.

## Out of scope

- A Pi-specific workflow authority, linter, language server, or state machine.
- Copying skills into `.pi` or treating them as subagents.
- Giving the generic flavor the spec loop, formatter, roles, or gate.
- Weakening Claude/Codex adapters.
- Claiming extension hooks or role allowlists provide OS containment.
- Claiming full parity before the documented fresh-project live Pi run succeeds.

## Implementation Notes

Implemented the Pi adapter additively without removing or replacing any Claude
Code or Codex files:

- `workflow/commands/` now renders byte-identical Pi project prompts, while
  `.agents/skills/` remains the portable skill authority.
- Shared roles render as Pi Markdown agents with fresh context, inherited
  project context, `model: inherit`, strict model scope, and minimal tool
  lists. Every child loads sensitive-read guards; read-only roles still omit
  Bash and mutation tools.
- `shared/pi/agentic-hooks.ts` translates Pi session, tool, direct-shell,
  edit/write, settlement, and TUI status events to the existing shell hooks.
  `agentic-child-hooks.ts` reuses only its safety and post-edit handlers in
  child sessions. The parent adapter owns a one-continuation guard and
  deliberately does not claim a default-compaction integration Pi cannot
  provide.
- Stack and generic bootstraps install checksum-protected Pi settings and the
  appropriate managed surfaces. Profile transitions, customized settings,
  no-stop/strict state, current Pi-aware migration, and legacy pre-Pi
  three-hash migration are covered by smoke fixtures.
- `pi-subagents@0.76.1` is exact-pinned in extension-only mode with bundled
  prompts, skills, and roles disabled. Discovery excludes legacy `.agents`
  agent scanning, so portable skills are not reinterpreted as subagents.
- Public docs, provenance, CI, the live acceptance harness, and the explicit
  gap analysis in `docs/pi-portability.md` were added. Pi remains provider and
  model neutral; no hosted or local model is selected by repository config.

Validation completed on 2026-10-06:

- renderer idempotence;
- Bash syntax and ShellCheck;
- Codex adapter validation;
- Pi adapter validation against Pi 1.0.4, including exact settings/package
  shape, token-free RPC prompt/skill/role discovery, role fidelity, lifecycle
  fixtures, strict and no-stop modes, destructive/sensitive guards, and
  one-retry semantics;
- generic and custom smoke tests;
- Python minimal/core/full, strict-hooks, and no-stop smoke tests;
- TypeScript default and strict-hooks smoke tests.

Independent review found five implementation blockers and two coverage gaps;
the Stop retry path, live-harness scope, Pi activation reporting, validator
coverage, generic contract, writer-child lifecycle, pinned Pi CI baseline, and
legacy migration fixture were corrected before that review pass. A subsequent
Claude/Codex review found that read-only children lacked sensitive-read guards,
writer children still inherited settlement enforcement, an optional-role
extension path broke after promotion, and the live harness under-checked the
red phase. Those issues were corrected with a child-only lifecycle entry point,
`grep` result protection, promoted-path validation, completed-outcome gating,
and full non-test workspace/focused-red assertions. Final review then moved
the validation baseline to current Pi 1.0.4 and `pi-subagents` 0.76.1 and
strengthened the live harness to prove planner/reviewer immutability,
implementation path scope, and spec/dashboard closeout before its pass can
count as parity evidence.

The opt-in authenticated harness was not executed because this conversation
did not separately confirm model-token use. Normal interactive trust and
`/reload`, a complete hosted-model run, and a capable local-model repeat remain
required evidence. The spec therefore remains `shipping`; this implementation
must not be described as full behavioral or sandbox parity.

## Phase handoff

**As of:** 2026-10-06, after implementation, full local validation, follow-up
review corrections, current-baseline validation, and top-level documentation
reconciliation.

**State:** First-class Pi support is implemented on local branch
`pi-agent-support` as an additive adapter beside the existing Claude Code and
Codex surfaces. The working tree is intentionally uncommitted. Authoritative
changes are under `workflow/`, `shared/pi/`, `generic/`, `stacks/`, and
`scripts/`; `python/`, `typescript/`, and `custom/` are rendered outputs.
Follow-up review corrections are applied. The repository keeps its historical
unnumbered design-record convention: this file is `docs/pi-agent-support.md`,
and no top-level `docs/specs/` directory remains. `README.md` and
`new-project-checklist.md` now distinguish loop-enabled product specs from the
generic flavor and keep their founding prompts identical. Local validation
passed: renderer idempotence, Bash syntax, ShellCheck, Codex and pinned-Pi
adapter validators, generic/custom smoke tests, all Python profile and
hook-mode smoke tests, and TypeScript default/strict smoke tests.
`docs/pi-portability.md` records the remaining parity gaps. The strengthened
authenticated Medium-workflow harness exists at
`scripts/acceptance-pi-live.sh` but was not run because token use was not
separately confirmed, so full behavioral parity is not claimed.

**Next phase:** Human review, an explicitly authorized authenticated Pi run if
required before merge, and an explicit commit decision.

**Entry conditions:** Resume from the repository root on branch
`pi-agent-support`. Read this implementation record, `AGENTS.md`, `README.md`,
`workflow/docs/pi-agent.md`, and `docs/pi-portability.md`. Inspect
`git status --short`, the tracked diff, and every untracked path—especially
new `.pi/` trees—because `git diff` alone omits them. Verify generated files
against `workflow/`, `shared/`, and `stacks/`; do not edit rendered flavor
files directly. Do not run the token-spending live harness without explicit
authorization, and do not commit or push without a separate explicit request.
