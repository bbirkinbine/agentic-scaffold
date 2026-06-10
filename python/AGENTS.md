# AGENTS.md

This project uses `CLAUDE.md` as the source of project context for AI
coding agents. See [`CLAUDE.md`](CLAUDE.md) in this directory for:

- Stack and conventions
- Workflow expectations (Spec → Plan → Test-first → Implement → Verify)
- Available subagents, skills, and slash commands
- Don't-touch list
- Code / commit style rules
- Public-repo hygiene rules

`AGENTS.md` exists as a portable fallback for non-Claude agents (Codex,
Cursor, Gemini, etc.) that look for this filename by convention. The
authoritative content lives in `CLAUDE.md`; keep them in sync by editing
`CLAUDE.md` and leaving this file as a pointer.
