# Generic multi-client scaffold

Use this flavor for repositories that will not run the stack flavors'
prescribed Spec → Plan → Test-first workflow: dotfiles, a notes or
documentation repository, a one-script utility. The founding session picks
it when the stack rubric in `workflow/docs/project-types.md` lands here.

A project that wants the loop but has no `stacks/<name>/` adapter (Go,
Rust, FPGA/HDL, infrastructure code) takes the **custom** flavor instead:
`custom/bootstrap.sh` installs the whole workflow with a gate runner the
project fills in. Running it in an existing generic project migrates the
state and unchanged client configs. Customized configs and the project
contract are preserved with merge candidates under
`.agentic/generic-migration/`; reconcile those, restart the clients, and
verify hook loading before using the loop. After migration, update with
`custom/bootstrap.sh --update`. This flavor installs no `WORKFLOW.md`, no spec
convention, and no workflow commands; do not hand-write them here.

```bash
cd your-project
bash path/to/agentic-scaffold/generic/bootstrap.sh
```

The bootstrap installs:

- a complete canonical `AGENTS.md` contract plus a `CLAUDE.md` import shim;
- `.claude/settings.json`, trusted-project `.codex/` configuration, and
  `.pi/settings.json` plus its local safety extension;
- stack-neutral branch, destructive-command, compaction, and status-line
  hooks under `.agentic/hooks/`;
- Codex secret-read permissions and command-execution rules;
- `docs/codex-cli.md` and `docs/pi-agent.md`.

It does not install a formatter, test runner, Stop gate, workflow skills,
custom agents, CI, or pre-commit configuration because those choices depend
on the repository's actual stack. Fill the contract's validation section and
add repository enforcement deliberately.

## After bootstrap

This is the generic flavor's day zero; there is no `WORKFLOW.md` to walk.

1. Fill every `{{PLACEHOLDER}}` in `AGENTS.md` and `README.md`
   (`rg '\{\{' .`). Read and cut every line of the contract before
   committing it. Leave `CLAUDE.md` as the one-line `@AGENTS.md` import.
2. Replace the sample validation block with this repository's real
   commands. If it has none yet, say so in one line and name what will
   define them. Checks of the scaffold's own hooks are not the project's
   validation.
3. Confirm `git config user.email` is the GitHub noreply address before the
   first commit.
4. Restart the client so its hooks load. On `main`, including before the
   first commit, the session-start hook hands the agent a branch warning;
   asking the agent whether it received one is the quick check that hooks
   loaded. In Codex, trust the project `.codex/`
   layer and review the hooks with `/hooks` (`docs/codex-cli.md`). In Pi,
   approve project trust, restart or `/reload`, and verify the local extension
   (`docs/pi-agent.md`). A sandboxed founding session may need approval to write `.codex/` and
   `.git/hooks/`; re-running the bootstrap after approval is safe.
5. Make the one scaffolding commit on `main`, then branch for real work.

Re-run with `--update` to refresh managed client configuration and hooks.
The bootstrap records hashes under `.agentic/scaffold-state/`; if a client
configuration file changed locally, update preserves it and prints a manual
merge warning instead of overwriting it. Project-owned contracts and
`README.md` are preserved. A recognizable legacy
`AGENTS.md` pointer, byte-identical contract pair, or Claude-only contract is
migrated to canonical `AGENTS.md` plus `CLAUDE.md`'s `@AGENTS.md` import, so
all clients load the same existing policy without duplicate maintenance.
