# Pi agent — generic flavor

Pi reads the canonical `AGENTS.md` and loads the trusted project extension from
`.pi/extensions/agentic-hooks.ts`. Review the project trust prompt, then
restart Pi or run `/reload` after bootstrap.

The generic flavor supplies only stack-neutral behavior: branch warning,
destructive-command and sensitive-file guards, context status, and the shared
commit-message hook. It intentionally installs no workflow prompts, subagent
roles, formatter, Stop gate, or language-specific validation. Fill the real
validation commands in `AGENTS.md`, or migrate to the custom flavor when the
repository needs the full Spec → Plan → Test-first → Implement → Verify loop.

Pi project trust is not a sandbox. Pi tools and extensions retain the operating
system permissions of the Pi process; use an isolated environment for
unattended work.
