# Generic dual-client scaffold

Use this flavor for repositories that do not need the Python scaffold's
prescribed Spec → Plan → Test-first workflow: infrastructure, shell, FPGA,
documentation, or another language with its own toolchain.

```bash
cd your-project
bash path/to/agentic-scaffold/generic/bootstrap.sh
```

The bootstrap installs:

- a complete canonical `AGENTS.md` contract plus a `CLAUDE.md` import shim;
- `.claude/settings.json` and trusted-project `.codex/` configuration;
- stack-neutral branch, destructive-command, compaction, and status-line
  hooks under `.agentic/hooks/`;
- Codex secret-read permissions and command-execution rules;
- `docs/codex-cli.md`.

It does not install a formatter, test runner, Stop gate, workflow skills,
custom agents, CI, or pre-commit configuration because those choices depend
on the repository's actual stack. Fill the contract's validation section and
add repository enforcement deliberately.

Re-run with `--update` to refresh managed client configuration and hooks.
The bootstrap records hashes under `.agentic/scaffold-state/`; if a client
configuration file changed locally, update preserves it and prints a manual
merge warning instead of overwriting it. Project-owned contracts and
`README.md` are preserved. A recognizable legacy
`AGENTS.md` pointer, byte-identical contract pair, or Claude-only contract is
migrated to canonical `AGENTS.md` plus `CLAUDE.md`'s `@AGENTS.md` import, so
both clients load the same existing policy without duplicate maintenance.
