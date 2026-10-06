# Pi portability and remaining gaps

Status: adapter implemented and statically/smoke validated (2026-10-05);
authenticated full-loop, normal trust/reload, and local-model evidence remain
open. The implementation record is in
[`pi-agent-support.md`](pi-agent-support.md).

## Implemented target

Pi consumes the canonical `AGENTS.md`, portable `.agents/skills/`, shared
workflow commands and roles, `.agentic` shell hooks, and stack toolchain runner.
Every child role explicitly loads the child-only lifecycle entry point, so
sensitive reads remain guarded in read-only roles and writer roles retain
Bash/edit/write guards without inheriting the parent settlement gate.
Token-free Pi 1.0.4 RPC validation confirms the minimal profile exposes five
project prompts, five project skills, and three project roles, with zero
package roles competing with them.
The adapter is provider-neutral: it never names or selects an LLM. Pi may use a
hosted Claude or Codex-family model, another supported provider, or a local
model; capability and tool-use quality vary by model, but the repository
contract and executable gate do not.

## Known gaps

- No authenticated fresh-project Medium workflow has yet demonstrated the
  complete Spec → Plan → Test-first → Implement → Verify sequence in Pi.
- Pi project trust controls resource loading, not tool permissions. The local
  extension and child-role allowlists are guardrails, not an OS sandbox.
- Pi's built-in compaction lifecycle permits replacement compaction but does
  not let this adapter append the existing context reminder to the default
  summarizer. Durable phase handoffs remain the portable control.
- Test-first file-boundary enforcement remains a parent-side fingerprint audit;
  Pi has no test-directory-only child sandbox.
- Read-only roles omit shell access to prevent shell-mediated writes. The
  parent must pass resolved diffs, status, and gate evidence into reviewers.
  Pi has no built-in web-search tool, so the planner also lacks Claude's
  `WebSearch` capability unless the operator installs a separately trusted
  extension.
- Lifecycle guards observe Pi's built-in tool events and guarded direct `!`
  shell commands. They cannot intercept arbitrary filesystem writes performed
  inside an opaque custom tool, MCP server, or child process that bypasses
  Pi's nested tool API.
- Project settings do not disable operator-installed global packages or
  extensions; global configuration remains an operator trust boundary.
- A model that cannot reliably follow tools, skills, and stop conditions is not
  made capable by the adapter. Model-agnostic means no provider coupling, not
  equal behavior across models.
- Project-local package filtering and resource discovery are verified under a
  token-free `--approve` RPC session. The normal interactive trust prompt and
  `/reload` behavior still need a live acceptance pass.

## Evidence required before claiming parity

1. Bootstrap each profile into a fresh temporary repository and approve it
   through Pi's normal project-trust flow.
2. Confirm prompts, skills, extension, and named roles load without treating
   `.agents/skills/**/SKILL.md` as agents.
3. Demonstrate plan and review children cannot modify the worktree.
4. Demonstrate test-first changes only allowed test paths and produces a
   cause-specific red result.
5. Demonstrate destructive commands and sensitive reads are blocked.
6. Demonstrate default, strict, and no-stop modes, including the one-retry cap.
7. Complete a Medium feature with a path-scoped implementation, green runner
   gate, fresh review whose before/after workspace snapshots match, docs/spec
   closeout, and no agent commit.
8. Repeat with at least one hosted model and one local model judged capable of
   the required tool protocol. This tests model portability without making
   either model part of the scaffold contract.
