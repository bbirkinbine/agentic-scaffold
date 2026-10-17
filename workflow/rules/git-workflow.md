# Git workflow

**Every change gets its own branch; never edit feature or fix code on `main`.**
Create it as soon as a spec or issue exists, without waiting to be asked.

## Branch naming

- Local spec mode: `spec-NNNN-<slug>`, where `NNNN` is the spec number.
- XS work without a spec: `<type>/<slug>`, where type is `feat`, `fix`,
  `chore`, `docs`, or `refactor`; never invent a spec number.
- Opt-in issue mode (record it in `AGENTS.md`): work beyond XS gets an issue,
  matching spec number, and `<issue-number>-<slug>` branch. Prefer
  `gh issue develop <N> --name <N>-<slug> --checkout` to preserve GitHub
  linkage.
- In either mode, the shared number links the work item, branch, and PR. It is
  an identity, not execution order; gaps are expected. See
  `docs/specs/README.md` → "Numbering".

One branch per spec / unit of work.

## One writing agent per checkout

A checkout has one session editing it. A second agent that will edit files
starts in its own worktree on its own branch (`git worktree add
../<repo>-<branch> -b <branch>`; see `docs/parallel-agents.md` where installed)
and removes it after the PR merges. If a session starts with uncommitted changes
it did not make, ask before editing; the SessionStart warning flags them.

## Before the Implement phase

Run `git branch --show-current`; on `main` or `master`, stop and branch. The
SessionStart warning and `no-commit-to-branch` hook are only backstops.

## Commits and pushes

Commit and push only as `AGENTS.md` → **Approval matrix** allows: make the
change, show `git status` and `git diff`, then wait.

## Pull requests

Run `/review`, then open with `gh pr create --fill --web`. In issue mode, put
`Closes #<issue-number>` in the PR body; omit it in local mode.

### Close-tasks ride in the PR they belong to

Finish bookkeeping on the feature branch before opening or merging its PR:
mark the spec `shipped`, regenerate `docs/specs/README.md`, update the
`AGENTS.md` current-state block, and tick related items. In an open PR,
`shipped` means "ships when merged."

Run `.agentic/hooks/closeout-check.sh` before opening the PR. CI rejects
numbered feature branches whose spec remains `draft`/`shipping` or dashboard
is stale; it does not verify the current-state prose.

Do not open a cleanup-only PR after merge. Fold missed bookkeeping into the
next related PR unless the cleanup adds independent standing value.
