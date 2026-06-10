# Parallel agents and unattended runs

The default for this scaffolding is one session driving the loop with
the human at two checkpoints. This doc covers the patterns past that
default: several agents at once, and runs with nobody watching. Both
are additive — the loop itself (Spec → Plan → Test-first → Implement →
Verify) does not change; what changes is how many copies of it run and
who is watching the checkpoints.

## Degrees of autonomy

The loop is identical at every tier; what changes is what substitutes
for your attention. Pick the tier deliberately — `/goal` is redundant
at tier 1 and load-bearing at tier 3. The tier decides which rungs of
the completion ladder you activate, not which phases you run.

| Tier | Your role | Completion mechanism | Setup |
| --- | --- | --- | --- |
| **1 · Attended** (default) | Both checkpoints, adjudicate `[ask-user]` findings live | You — the checkpoints *are* the completion mechanism | Nothing; this is the loop as shipped |
| **2 · Long autodrive** (one feature, you're nearby) | Same checkpoints; the implement-to-green stretch runs long without you | **`/goal`** set at checkpoint 1, right after approving the plan — phrase it from the spec's success criteria ("done when `/review-check` passes and every criterion in spec NNNN has a passing test"). The separate evaluator keeps a long session from stopping early or drifting where an in-prompt instruction fades | One `/goal` command per feature |
| **3 · Unattended** ("just ship it" / overnight) | Standing consent given up front; checkpoints collapse into the spec | `/goal` is the primary finish line (ladder rung 2), Stop hook behind it (rung 3, capped), fresh-context review behind that (rung 4) | `/goal` + `/sandbox` + scoped permissions; tight spec with runnable success criteria |
| **4 · Babysitting / recurring** (no feature in flight) | None per-iteration | **`/loop`** re-runs a prompt on an interval — poll CI after the PR opens, re-check a flaky deploy, periodic maintenance. Not part of the feature loop at all; it lives after checkpoint 2 or entirely outside feature work | `/loop <interval> <prompt>`; cap iterations or cost |

**The unattended ceiling is "ready-to-merge," not "merged."** Standing
consent covers resolving `[ask-user]` findings, but the git-workflow
rule still requires an explicit commit instruction — so a tier-3 run
ends at "branch green, review clean, awaiting commit" unless the
kickoff instruction explicitly granted the commit too. The last
irreversible act stays human by default.

## When to parallelize (and when not to)

Parallel agents buy *volume*, not quality. The published numbers cut
both ways: high-adoption multi-agent workflows correlate with far more
merged PRs, but also with much larger PRs and much longer review times.
Parallelism converts to real throughput only with the same discipline
the single-session loop enforces — small PRs, real review, partitioned
ownership.

Parallelize when:

- Two or more features are independent at the *file* level — disjoint
  modules, disjoint specs.
- One stream is long and unattended-safe (a migration sweep, a
  documentation pass) and would otherwise block interactive work.
- You want independent attempts at the same problem to compare (write
  two, merge the survivor).

Don't parallelize when the tasks share files (merge conflicts eat the
gain), when the work is exploratory (you'd be reviewing two wrong
directions instead of one), or when you can't give each stream its own
spec.

## Worktrees: one agent, one branch, one directory

Git worktrees give each agent an isolated checkout of its own branch —
no stepping on each other's working tree, no shared dirty state:

```bash
git worktree add ../myproj-42-user-prefs 42-add-user-prefs
cd ../myproj-42-user-prefs && claude
```

Conventions that keep this sane:

- **One worktree per spec/branch**, named after the branch. Remove it
  when the PR merges (`git worktree remove ../myproj-42-user-prefs`).
- **Partition file ownership in the specs.** Each spec's `## Non-goals`
  should exclude the files the other stream owns. Two agents editing
  one module is a merge conflict you scheduled on purpose.
- **Each worktree gets the full scaffolding for free** — `.claude/`,
  hooks, and pre-commit travel with the checkout. Run `uv sync` per
  worktree; `.venv/` is per-directory.
- A terminal multiplexer (tmux pane per worktree) keeps the sessions
  glanceable; that's an ergonomic choice, not a requirement.

Claude Code's auto-memory is shared across all worktrees of one repo,
so a lesson learned in one stream carries to the others.

## Agent teams (experimental)

Claude Code's agent teams put a lead session and several teammates on a
shared task list with inter-agent messaging. Experimental — enable with
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (v2.1.32+).

What maps directly onto this scaffolding:

- **The subagent definitions in `.claude/agents/` double as teammate
  roles** — "spawn a teammate using the reviewer agent type" reuses the
  same tools allowlist and instructions the single-session loop uses.
- Start with research/review topologies (parallel reviewers over one
  diff, parallel investigators over one codebase) before parallel
  *implementation* — review parallelizes safely because it doesn't
  write.
- Keep teams small (3–5 teammates) and partition file ownership exactly
  as with worktrees.
- Quality gates extend to task granularity via the `TaskCompleted` /
  `TeammateIdle` hook events (exit 2 blocks a task from completing) —
  the same gate-on-stop idea, per task instead of per turn.

## The completion ladder

"How do I stop the agent from declaring victory early?" has a layered
answer; each rung catches what the one below it misses:

1. **In-prompt check** — the spec's success criteria phrased as a
   runnable check ("done when `uv run pytest tests/test_x.py` passes").
   Cheapest; easiest for a long session to drift past.
2. **`/goal`** — a hard completion condition checked by a separate
   evaluator every turn (v2.1.139+). Survives context drift because the
   evaluator is outside the conversation.
3. **Stop hook** — `gate-on-stop.sh` mechanically blocks ending a turn
   on a red gate. Note the cap: Claude Code overrides a Stop hook after
   8 consecutive blocks without progress, so this is a strong nudge,
   not an unbounded guarantee.
4. **Fresh-context verification** — `/review` + `/review-adversarial`
   (or a verification teammate): a context that has not seen the
   implementation reasoning judges the result. This is the only rung
   that catches "the gate is green but the feature is wrong."

Use the ladder top-down when configuring an unattended run: the longer
nobody is watching, the more rungs you want active.

## Unattended runs

These are the tier 3–4 mechanics from the table above. For long
autonomous work — a PRD with many items, a repo-wide sweep — the
working pattern is a *loop with externalized state*: progress
accumulates in files and git (specs, `## Phase handoff` sections,
commits on a branch), never only in the conversation, so each iteration
can start with a fresh context and pick up from disk.

- **`/loop`** re-runs a prompt or command on an interval — fits
  babysitting jobs (re-check CI, retry a flaky migration step).
- **The Ralph-loop pattern** (official `ralph-wiggum` plugin) re-feeds
  one prompt until a completion sentinel or max-iterations — fits
  "work through this PRD item by item." Known failure modes: drift
  without a tight spec, and uncapped cost — set max-iterations.
- **`/goal` + autodrive** covers the common middle: one feature, end to
  end, with the evaluator holding the finish line.

Safety posture for unattended runs is different from interactive ones:
prefer OS-level sandboxing (`/sandbox`) and a scoped permission mode
over `--dangerously-skip-permissions`; the `block-destructive.sh` hook
remains as a narrow backstop, not the primary containment. Checkpoints
mean `/rewind` can restore both code and conversation if a run goes
sideways — recovery, not prevention.

## What this scaffolding deliberately does not do

No orchestration framework, no agent-to-agent message bus, no custom
runner. Practitioner experience is consistent that elaborate
multi-agent setups underperform simple ones — plain worktrees, plain
specs, plain hooks — until the simple version is saturated. Saturate it
first.
