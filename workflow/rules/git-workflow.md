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

Run `/review` and `.agentic/hooks/closeout-check.sh`. Before the first PR in a
GitHub-backed repo, check `gh repo view --json deleteBranchOnMergeEnabled`. If
it is false, run `gh repo edit --delete-branch-on-merge` and say so.

Open the PR from the terminal: `gh pr create --base <base> --title "<subject>"
--body-file -`. Do not open a browser draft (`--web`), and do not show the
title or body for approval first; the reviewed commits are the draft. In issue
mode, put `Closes #<issue-number>` in the PR body; omit it in local mode.

Then watch CI with `gh pr checks <number> --watch`. On a failing check, fix the
cause on the branch, rerun the gate, push, and watch again. Report to the human
only when every check passes, and give the PR URL. Merging stays theirs.

### After the merge

When the human reports a merge, verify it first:
`gh pr view <number> --json state` must return `MERGED`. Then clean up:

```bash
git switch <default-branch> && git pull --ff-only
git branch -d <branch>   # -d refuses an unmerged branch; never -D here
git fetch --prune
git worktree remove ../<repo>-<branch>   # only if the branch had a worktree
```

With delete-branch-on-merge on, GitHub has already removed the remote branch.

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
