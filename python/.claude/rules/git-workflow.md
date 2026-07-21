# Git workflow

The standing rule: **every change happens on its own branch — never
write feature or fix code on `main`.** Create the branch yourself, as
soon as there is a spec or an issue to work. Do not wait to be asked;
branching is not an optional courtesy step.

## Branch naming

- Spec work (default local mode) → `spec-NNNN-<slug>`, e.g.
  `spec-0007-add-user-prefs`, where `NNNN` is the spec's number under
  `docs/specs/`. The spec number and the branch number are the same
  number; that shared id ties spec ↔ branch ↔ PR together, and the
  specs themselves are the cross-session persistence layer.
- Untracked tiny work with no spec — XS fixes, chores, hotfixes →
  `<type>/<slug>`, where `<type>` is one of `feat` `fix` `chore` `docs`
  `refactor`, e.g. `chore/bump-ruff`. Do not invent a fake spec
  number.
- Issue mode (opt-in — for team repos or when the backlog should live
  as GitHub issues; record the choice in `CLAUDE.md`): anything past XS
  gets a GitHub issue first, the spec is numbered by the issue, and the
  branch is `<issue-number>-<slug>`, e.g. `42-add-user-prefs`. Create
  it with `gh issue develop <N> --name <N>-<slug> --checkout`, which
  links the branch to the issue in GitHub's UI (plain
  `git switch -c <N>-<slug>` works but loses that linkage). In this
  mode issues are the cross-session persistence layer and
  spec ↔ issue ↔ branch ↔ PR all share one id.
- Either mode: the number is an identifier, not an execution order —
  gaps in `docs/specs/` are expected (in issue mode, numbers are also
  consumed by bugs and questions), and specs ship in whatever order
  triage dictates. See `docs/specs/README.md` → "Numbering".

One branch per spec / unit of work.

## Before the Implement phase

Check `git branch --show-current`. If it returns `main` or `master`,
stop and create the branch first. Two guardrails back this up — the
`no-commit-to-branch` pre-commit hook blocks commits on `main`, and a
SessionStart hook warns when a session opens on `main` — but a guardrail
firing means the branch was created too late. Branch at the right time;
treat the guardrails as a backstop.

## Commits and pushes

Never commit or push on your own. Each commit needs an explicit
"commit" instruction from the human in the current conversation; never
push without being explicitly asked, and never use `--force` without a
direct ask. Workflow: make the change, show `git status` and
`git diff`, then wait.

## Pull requests

Open with `gh pr create --fill --web`. In issue mode, the PR body must
contain a closing keyword line — `Closes #<issue-number>` — so the
merge auto-closes the issue. Closing keywords work in the PR body, not in
feature-branch commit messages. In the default local mode, omit the
closing keyword. Run `/review` before opening the PR.

### Close-tasks ride in the PR they belong to

A change's own bookkeeping — flipping the spec's `**Status:**` to
`shipped`, regenerating the `docs/specs/README.md` dashboard, updating the
`CLAUDE.md` "current state" block, ticking a todo/checklist item — belongs
**in the feature branch itself**, committed before the PR is opened (or
pushed to the same branch before it merges), so one merge completes the
work. `shipped` in an open PR means "ships when this PR merges" — that is
the intended reading, not a lie about current state.

**Do not open a separate follow-up PR after merge** just to mark the spec
shipped or do small post-merge cleanup — that is a wasted PR and a wasted
review. If such cleanup was missed and its feature PR is already merged,
fold it into the next PR that touches the same area rather than spawning a
standalone one; a standalone cleanup PR is justified only when it carries
real standing value on its own (e.g. it also changes a rule or doc that
outlives the cleanup).
