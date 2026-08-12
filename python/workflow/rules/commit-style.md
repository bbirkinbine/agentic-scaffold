# Code / commit style

- **No AI `Co-Authored-By` trailers** in
  commit messages. The top-level `README.md` already acknowledges AI
  tooling — that is the single source of attribution.
- **No generated-by-client footers** in commits or PR
  descriptions for the same reason.
- AI assistance is acknowledged **once**, at the top of `README.md`. Do
  not sprinkle AI-assist notices into individual files, commit
  messages, or comments.
- Match the existing log style: short imperative subject, body
  explaining the *why* when non-obvious. No conventional-commits
  prefixes (`feat:`, `fix:`, `chore:`) unless the existing log already
  uses them.
- Reference the spec under `docs/specs/` when applicable.
- Avoid emojis in repo files.
- Avoid the words *genuinely*, *straightforward*, *actually* in prose.
- Direct, technical tone.

## Mistakes feed back into the rules

When the human corrects a recurring agent mistake — a convention you
keep missing, a tool you keep misusing, a path you keep touching — the
fix is not just the correction in-session: add a line to `AGENTS.md` in
the same change, so the next
session doesn't repeat it. Standing instructions are the error log that
compounds; a correction that lives only in chat history is lost at
session reset.
