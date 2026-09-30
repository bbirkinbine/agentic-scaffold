#!/usr/bin/env bash
# SessionStart hook — warns when a coding session opens on main/master.
#
# Feature and fix code must be written on a dedicated branch, never on
# main. This hook is the early reminder; where the flavor installs
# pre-commit, its no-commit-to-branch hook is the hard backstop. See
# AGENTS.md -> "Git workflow".
#
# Hook output is surfaced to the agent at session start.

# symbolic-ref, not `rev-parse --abbrev-ref HEAD`: a repository with no
# commits yet has a branch but no revision, and rev-parse answers "HEAD"
# there. That is the founding session, where this warning is also the
# first evidence that the client loaded its hooks. Detached HEAD prints
# nothing and stays silent.
branch="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"

case "$branch" in
  main | master)
    echo "Git: this session started on '$branch'. Per AGENTS.md -> Git workflow,"
    echo "do not write feature or fix code on '$branch'. Create a branch first:"
    echo "  - issue-tracked work:  gh issue develop <N> --name <N>-<slug> --checkout"
    echo "  - untracked tiny work: git switch -c <type>/<slug>"
    ;;
esac
