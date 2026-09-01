# Code / commit style

- No AI `Co-Authored-By`, generated-by-client, or other AI-attribution text in
  files, comments, commits, or PRs; the top-level README is the sole notice.
- Match the log: short imperative subject and a why-focused body when needed.
  Do not introduce conventional-commit prefixes unless the log uses them.
- Reference the spec under `docs/specs/` when applicable.
- Avoid emojis in repo files.
- Avoid the words *genuinely*, *straightforward*, *actually* in prose.
- Direct, technical tone.

## Mistakes feed back into the rules

Encode a human correction to a recurring agent mistake in `AGENTS.md` in the
same change. Review findings count: when `/review` or `/review-adversarial`
raises the same finding on a second feature, add the missing rule while fixing
it. One occurrence is a mistake; two indicate a missing rule.
