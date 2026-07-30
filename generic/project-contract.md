# Project: {{REPO_NAME}}

> **Purpose.** Persistent project context for coding agents working in this
> repository. `AGENTS.md` is the canonical contract; the one-line
> `CLAUDE.md` imports it so Codex and Claude Code load the same instructions
> without maintaining duplicate policy. Read this before suggesting changes.
> `README.md` is for humans landing on the GitHub page; these files are for
> the agent that opens the repo and starts working.
>
> Personal, machine-local preferences do not belong in this file — put
> them in `CLAUDE.local.md` (instructions) or
> `.claude/settings.local.json` for Claude Code, or in the user's Codex
> configuration. Keep local overlays gitignored. The root contracts and
> checked-in client configuration are team-shared.

---

## What this repo is

{{ONE_PARAGRAPH_DESCRIPTION}}

This repo is **public** on GitHub (`github.com/bbirkinbine/{{REPO_NAME}}`).
Treat every change as world-readable: file contents, commit messages,
branch names, PR descriptions, and issue text are all indexed by search
engines. No secrets, no internal hostnames, no work-related context.

---

## Stack / scope

{{LIST_THE_PRIMARY_TOOLS_AND_LANGUAGES — e.g. Python 3.12 + uv + pytest, or Packer + Tart + qemu, or Ansible + OpenTofu}}

{{WHAT_THIS_REPO_DOES_NOT_DO — explicit out-of-scope items, especially adjacent things someone might assume belong here}}

---

## Code / commit style

- **No AI `Co-Authored-By:` trailers** in commit
  messages. The top-level `README.md` already acknowledges AI tooling —
  that is the single source of attribution.
- **No generated-by-client footers** in commits or PR
  descriptions for the same reason.
- AI assistance is acknowledged **once**, at the top of `README.md`. Do
  not sprinkle AI-assist notices into individual files, commit messages,
  or comments.
- Match the existing log style: short imperative subject, body explaining
  the *why* when non-obvious. No conventional-commits prefixes
  (`feat:`, `fix:`, `chore:`) unless the existing log already uses them.
- Avoid emojis in repo files.
- Avoid the words *genuinely*, *straightforward*, *actually* in prose.
- Direct, technical tone.

---

## Secrets and public-repo hygiene

**Treat this repo as public from commit #1, even if it is currently (or
was recently) private.** Many of my repos start private and flip to
public after a feature lands. Rewriting history after that flip is
destructive — every commit SHA changes, existing clones break, and the
old state may already be archived by forks, GitHub's network view, or
anyone who cloned before the rewrite. The cheapest fix is to never commit
the thing in the first place.

The rules below apply across every public surface, not just file
contents:

- File contents and diffs
- Commit messages (subject + body) and tag annotations
- Branch names and tag names
- PR titles, descriptions, review comments
- Issue titles, bodies, comments; Discussions; wiki pages; release notes
- CI workflow logs (echoed env vars, full paths, stack traces are all
  public for public repos)
- Author + committer email on every commit — history is forever

**Never commit:**

- Live credentials of any kind — API tokens, passwords, private keys,
  signing keys, OAuth secrets, session cookies, JWTs. If one ever lands
  in a commit, **rotate it immediately**; assume any value that touched
  history is compromised the moment it lands.
- `.env*` files other than `.env.*.example` (which must contain no real
  values). Gitignore `.env.*` with an explicit `!.env.*.example` whitelist.
- Internal hostnames, IPs, subnets, internal URLs, VPN endpoints,
  private Slack/Discord links, IRC channels.
- Names of coworkers, managers, customers, or anyone else who hasn't
  opted in to having their name attached to this repo. "Alice asked me
  to fix this" → "fix the foo bug."
- Private-tracker identifiers — Linear/Jira/Asana ticket IDs, internal
  doc URLs, Notion share links. They look anonymous but reveal both the
  tool in use and the existence/structure of internal work.
- Employer references in commit messages, comments, or repo metadata,
  unless the work was deliberately published with the employer's
  awareness.
- File paths that leak identity or employer —
  `/Users/firstname.lastname/Work/<EmployerName>/...`. Use `~/` or
  relative paths in docs; sanitize screenshots that show file pickers,
  terminal prompts, or editor title bars before pasting into PRs.
- Personal info — home address, phone, personal email, ID numbers.

**Things that quietly slip through:**

- `Co-Authored-By:` trailers naming real people. If a private-phase
  commit attaches a coworker's email as a co-author, flipping public
  exposes that forever. Treat the no-AI-coauthor rule from the §Code /
  commit style section as part of the same hygiene: no co-author
  trailers, period, unless the named person has explicitly signed off.
- Author email on early commits. If a clone on a different machine had
  the wrong global `user.email`, every commit before the fix carries
  it. Verify before the first commit — see
  [`new-project-checklist.md`](https://github.com/bbirkinbine/agentic-scaffold/blob/main/new-project-checklist.md).
- CI logs. Echoed env vars, full filesystem paths, and stack traces are
  all visible to anyone the moment the repo is public.
- Screenshots embedded in PRs or `docs/`. Crop or blur anything showing
  real data, real hostnames, or filesystem layout.

If the repo is currently private and a flip to public is on the table,
walk the pre-flip checklist in
[`new-project-checklist.md`](https://github.com/bbirkinbine/agentic-scaffold/blob/main/new-project-checklist.md)
before clicking "Change visibility." Pre-flip scrubbing is cheap; post-flip
scrubbing is expensive and incomplete.

---

## Validation gates before claiming done

{{LANGUAGE_SPECIFIC_VALIDATION_COMMANDS — fill in for this repo, e.g.:}}

> **Template owner:** replace this entire example block during bootstrap.
> The command families below are mutually exclusive examples, not a
> prescribed Python gate. Until this section is filled, the agent must ask
> for the repository's real validation commands rather than choosing one.

```bash
# Python (uv-managed)
uv run ruff check .
uv run ruff format --check .
uv run mypy src/
uv run pytest

# Or shell scripts
bash -n scripts/*.sh
shellcheck scripts/*.sh

# Or Packer
packer init .
packer fmt -check .
packer validate .
```

Don't claim a change is "ready" without at least:

1. A clean run of the gates above for the affected file(s).
2. A sweep of `docs/` (if the repo has one) for statements the change
   made false — reference docs must match the code they describe.
3. An updated README if the change affects how the project builds,
   runs, or presents itself. The README is deliberately high-level;
   don't churn it on internal changes.

---

## Git workflow and agent authority

- Use a dedicated branch for feature and fix work. Do not write those
  changes directly on `main` or `master`.
- Do not run `git commit` or `git push` without an explicit instruction
  from the human in the current conversation.
- Treat hooks and command rules as guardrails, not as authorization for an
  action the human did not request.
- Before reporting completion, show the validation evidence and summarize
  the changed files. Stop before commit unless the human explicitly asked
  for one.

---

## Hooks and guardrails

- Claude Code reads `.claude/settings.json`; Codex reads the trusted
  `.codex/` project layer. Both call shared scripts under `.agentic/hooks/`.
- Client permissions deny reads of `.env*`, `*.pem`, and `*.key` material.
  The behavioral secrets rule still applies because runtime overrides can
  replace client defaults.
- The SessionStart hook warns when a coding session opens on `main` or
  `master`.
- The PreToolUse hook blocks a narrow set of unrecoverable shell commands.
  It is a backstop, not a substitute for the client's sandbox.
- The PreCompact hook preserves branch, changed-file, validation, and
  unresolved-decision state.
- Both clients show branch, model, and context state in their configured
  status line.
- Codex command rules prompt for commit and push and forbid a small set of
  destructive commands. Repository validation and human review remain the
  enforcement boundary.

---

## Don't touch

{{LIST_OF_FILES_OR_DIRS_THAT_ARE_LOAD_BEARING — e.g. vendored upstream
files, generated artifacts, lockfile-adjacent config sections. Empty list
is fine if there's nothing special.}}

---

## Open work / current state (updated {{YYYY-MM-DD}})

{{WHAT'S_DONE, WHAT'S_NEXT, WHAT'S_BLOCKED — keep this section short and
prune it as state changes.}}
