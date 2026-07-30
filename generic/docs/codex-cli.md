# Codex CLI for a generic repository

The generic scaffold installs Claude Code and Codex support together.
`AGENTS.md` is the complete canonical contract and `CLAUDE.md` imports it
with `@AGENTS.md`. Both clients call the same safety hooks under
`.agentic/hooks/`. Claude Code may ask for one-time approval when it first
encounters the checked-in import.

Unlike the Python flavor, this scaffold does not prescribe a
Spec → Plan → Test-first workflow or language-specific quality gate. Fill
the contract's validation section with the real commands for this repository.
Capability parity here means both clients receive the same project policy,
secret-read boundary, branch warning, destructive-command backstop, and
compaction state reminder.

## Start Codex

From the repository root:

```bash
codex
```

Review the normal project trust prompt. Codex ignores project `.codex/`
configuration, hooks, and rules until the project is trusted. Run `/hooks`
to review and trust the checked-in hook definitions.

See the official Codex documentation for
[AGENTS.md discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md),
[project hooks](https://learn.chatgpt.com/docs/hooks), and
[command rules](https://learn.chatgpt.com/docs/agent-configuration/rules).

The project permission profile denies reads of `.env*`, `*.pem`, and `*.key`
material. `.codex/rules/safety.rules` prompts for commit and push and forbids
a narrow set of destructive commands. These are guardrails, not a substitute
for the behavioral contract, client sandboxing, repository validation, or
human review.

## Switch clients

Before switching, write durable state into the repository: current branch,
changed files, validation status, and unresolved decisions. The PreCompact
hook reminds both clients to preserve that state. The next client reads the
same root contract and working tree; conversation history and client UI state
do not transfer.

## Existing projects

Run:

```bash
bash path/to/agentic-scaffold/generic/bootstrap.sh --update
```

The update installs or refreshes managed client configuration and shared
hooks without overwriting project-owned contracts or the README. Recorded
hashes under `.agentic/scaffold-state/` let it update untouched client
configuration while preserving locally customized config with a warning. If
`AGENTS.md` is still the old unmodified pointer template, bootstrap replaces
the pointer with the customized `CLAUDE.md` content, then makes `CLAUDE.md`
import the canonical `AGENTS.md`. Existing duplicate contracts are migrated
the same way. A Claude-only project is preserved by moving that policy into
`AGENTS.md`; a dangling `@AGENTS.md` import is repaired with the scaffold
contract. If the two files contain different project-owned policy, the
bootstrap preserves both and prints manual reconciliation instructions.
Then merge any useful client-neutral wording from the current template by
hand.

## Client differences

- Both clients show branch, model, and context state in their configured
  project status line.
- The generic scaffold has no edit-time formatter or Stop gate because it
  cannot infer correct validation commands for an arbitrary stack.
- Codex project hooks require trust and are skipped while untrusted.
- Runtime permission overrides can replace project defaults.
