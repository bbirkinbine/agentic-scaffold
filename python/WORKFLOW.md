# Workflow — how to use this scaffolding

> Companion to `CLAUDE.md`. `CLAUDE.md` is the standing instructions the
> agent reads every turn — the rules. This file is the human-facing
> walkthrough — the loop, what each step is for, and where it goes wrong
> if you skip a checkpoint.

The scaffolding implements the agentic loop
`Spec → Plan → Test-first → Implement → Verify`. The slash commands and
subagents are checkpoints: the agent stops at each transition and surfaces
output rather than rolling forward. The human is the loop driver.

## Day zero (once per project)

```bash
mkdir ~/Downloads/src/myproj && cd ~/Downloads/src/myproj
git init
bash ~/Downloads/src/agentic-scaffold/python/bootstrap.sh
```

Then, in order:

1. **Walk placeholders.** `rg '\{\{' .` — fill in `CLAUDE.md` and
   `pyproject.toml`. A `CLAUDE.md` that still says `{{PROJECT_NAME}}`
   actively misleads the agent on every turn.
2. **Walk the new-project checklist.** See
   `~/Downloads/src/agentic-scaffold/new-project-checklist.md` — README
   AI acknowledgement line, GitHub About sidebar, identity check. The
   identity check is load-bearing: `git config user.email` is baked into
   the first commit forever, and a wrong value leaks once the repo flips
   public.
3. **Decide opt-in subagents up front, not retroactively.**
   - Network surface, auth, untrusted input, secrets, or external
     deserialization → copy `security-reviewer`.
   - Hot path, async, DB queries on user-sized data, or a latency SLO →
     copy `performance-reviewer`.
   - Add a one-line mention of each enabled subagent to the "Subagents"
     section of `CLAUDE.md` so the agent knows when to route to it.
   - **Large or long-lived codebase you'll revisit across many sessions**
     (not a fresh small repo) → enable the `serena` MCP for symbol-level
     navigation. Skip it on small single-language repos — see
     `CLAUDE.md` → "Code navigation" for the when/whether (and the
     skip-by-default rule), and `docs/serena-setup.md` for the install
     and verification steps.
4. **Install the dev environment.**
   ```bash
   uv sync
   uv run pre-commit install
   ```
   Verify the PostToolUse hook works by making a trivial edit; you should
   see `ruff format`, `ruff check`, and `mypy` run.

   `pre-commit install` also activates the `no-commit-to-branch`
   guardrail. The initial scaffolding commit lands on `main` — that is
   the one expected commit there; make it before `pre-commit install`,
   or with `git commit --no-verify`. Every change after that goes on a
   branch.

## Per-feature loop

Each step is a separate turn. The slash commands enforce that — every
subagent stops and surfaces output rather than continuing into the next
phase on its own. You decide whether to advance.

```text
/scope-check add user authentication   # OPTIONAL — only when goal/scope is ambiguous.
                                       # Five forcing questions. Output goes into the
                                       # spec's ## Goal and ## Non-goals.
        ↓
/spec add user authentication      # scaffolds docs/specs/NNNN-add-user-authentication.md
        ↓
[edit the spec]                    # goal, success criteria, non-goals;
                                   # one paragraph minimum
        ↓
/clarify                           # OPTIONAL — on features with real unknowns.
                                   # Interrogates the draft spec for underspecified
                                   # areas (max 5 questions) and writes the answers
                                   # back into the spec. Skip when the spec is tight.
        ↓
[create the branch]                # <issue#>-<slug> for issue-tracked work; else
                                   # <type>/<slug>. The agent branches itself —
                                   # never run the loop on main.
        ↓
/plan                              # planner subagent reads spec + codebase
        ↓
[review the plan]                  # files to touch, order, risks;
                                   # reviewable in < 5 minutes.
                                   # if the plan is wrong, fix the spec
                                   # or push back — don't proceed
        ↓
       (/clear if multi-day — see "Phase handoff" below)
        ↓
/test-first                        # writes failing pytest tests from the spec
        ↓
[confirm the failure mode]         # tests should fail with AttributeError /
                                   # NotImplementedError / AssertionError —
                                   # NOT ImportError on a typo. Wrong failure
                                   # mode = the test isn't pinning down behavior.
        ↓
/analyze                           # OPTIONAL — cross-checks spec ↔ tests before
                                   # implementation: every success criterion covered,
                                   # no test pinning undeclared scope. A coverage
                                   # hole is cheapest to fix right here.
        ↓
[main session implements]          # CLAUDE.md tells it: minimum code to
                                   # pass tests, one concept per file,
                                   # ≤ 300 lines, type hints required
        ↓
/review-check                      # local gate: ruff lint + format + mypy + pytest;
                                   # refuses to pass on any failure
        ↓
       (/clear if multi-day — see "Phase handoff" below)
        ↓
/review                            # independent reviewer against spec + diff
/review-adversarial                # same diff, adversarial framing — argues against
                                   # the change. Run on meaningful features and read
                                   # both review outputs side-by-side.
   /security                       # if installed AND the diff trips a security trigger
   /performance                    # if installed AND the diff trips a performance trigger
        ↓
[commit, explicitly]               # CLAUDE.md forbids agent-initiated commits;
                                   # you write the commit message
        ↓
[append ## Implementation Notes    # OPTIONAL — capture decisions that surfaced
 to the spec, post-merge]          # during build but weren't in the original spec.
```

## Where this goes wrong if you skip steps

- **Skipping the spec.** `/plan` becomes guess-the-feature; `/review`
  has no anchor to compare against. The reviewer's first check is "does
  the diff match the spec?" — with no spec, it can't run that check.
- **Implementing on `main`.** Skip the branch step and the whole loop
  runs on `main`. The `no-commit-to-branch` guardrail then blocks the
  commit at the *end* — after the work is done, which is the worst time
  to discover it. Branch right after the spec exists; the SessionStart
  hook warning is the early reminder.
- **Skipping `test-first`.** You'll write the implementation first and
  then "tests" that match what you happened to build, not what the spec
  says. Tautological tests pass everything, including the bugs.
- **Running `/spec → /plan → /test-first → implement` in one shot
  without checkpoints.** The checkpoints exist so a wrong turn at the
  spec doesn't propagate through the plan and tests before you notice.
  Cost of catching it at the spec phase: edit a paragraph. Cost of
  catching it at review: redo the work.
- **Skipping `/review-check` before `/review`.** The reviewer's first
  action is `uv run pytest`; if tests fail, the review is wasted on
  broken code. Run the gate first.
- **Forgetting the opt-in subagent install.** `/security` and
  `/performance` print install instructions and stop if the subagent
  isn't in `.claude/agents/`. The check doesn't run. If you decided at
  day zero that the project warrants the opt-in, install it then —
  don't defer.
- **Fabricating external reference data.** When the spec depends on a
  registry, RFC, vendor table, or any other external authority, the
  values must be either fetched in-session (URL + date pinned above the
  table in code) or declared as empirical / original in the spec's
  `## External references` section. The failure mode is the one the
  spec template warns against: the agent writes the table from
  training, names a source it never fetched, then writes fixtures that
  match its own assumptions. Every test passes and every value is
  wrong, because the round-trip never touched reality. If no source has
  been found, the spec must say so — push back at spec time rather than
  invent provenance later.

## Phase handoff (multi-day features)

Single-session features run the loop end-to-end — the common case the
diagram covers.

For a feature that spans multiple sessions — a real architectural
change, a multi-package refactor, anything where the main session would
end the day past 50% context — running the whole loop in one session
degrades review quality. By the time `/review` fires, the main session
has accumulated spec discussion, plan iteration, test-writing, and
implementation context. That's the context-degradation U-curve: a
session reviews best when it's neither empty of context nor drowning
in its own history.

The discipline: at each phase boundary, append a `## Phase handoff`
section to the spec capturing the current state and entry conditions
for the next phase. Then run `/clear` and resume in a fresh session.
The fresh session re-reads `CLAUDE.md`, the spec (with the handoff
section), and the diff — it has all it needs to pick up where the
previous session left off.

Where the boundaries are worth a `/clear`:

- After `/plan` is reviewed and accepted, before `/test-first`.
- After implementation passes `/review-check`, before `/review`.

Skip the handoff on single-session features — it's overhead the loop
doesn't need until the session itself is the bottleneck.

See `docs/specs/README.md` for the `## Phase handoff` and
`## Implementation Notes` section shapes.

## The completion ladder

"The agent declared done and it wasn't" has a layered fix; each rung
catches what the one below misses. Use more rungs the longer nobody is
watching.

1. **In-prompt check** — phrase the spec's success criteria as a
   runnable command. Cheapest; a long session can drift past it.
2. **`/goal`** — a completion condition checked by a separate evaluator
   every turn. Survives drift because the evaluator is outside the
   conversation.
3. **Stop hook** — `gate-on-stop.sh` blocks ending a turn on a red
   gate, mechanically. Capped: Claude Code overrides a Stop hook after
   8 consecutive blocks, so it is a strong nudge, not a guarantee.
4. **Fresh-context verification** — `/review` + `/review-adversarial`:
   a context that never saw the implementation reasoning judges the
   result. The only rung that catches "gate is green but the feature is
   wrong."

Demand evidence, not assertions: an agent claiming an outcome should
show the command output that proves it. That expectation is in
`CLAUDE.md` ("Verify before you report"); the ladder is what enforces
it when the claim is "done."

How many rungs to activate is a function of how attended the run is —
at the default attended tier your two checkpoints are the completion
mechanism and `/goal` is redundant; set `/goal` at checkpoint 1 when
the implement stretch will run long or unattended; `/loop` is for
post-PR babysitting and maintenance, never for feature work. The tier
table is in `docs/parallel-agents.md` → "Degrees of autonomy"; the
full loop taxonomy (the six loops this workflow is made of) is in
`docs/workflow-diagram.md` → "Loops within loops."

## When NOT to use the full loop

The scaffolding is sized for projects you intend to maintain. For a
throwaway one-off script (a `~/Downloads/scratch/` analysis, a
dead-by-Friday spike), the loop is overhead. Skip `bootstrap.sh`
entirely; just write the code. The judgment has to be honest about
which projects are which — most "throwaways" turn out not to be.

A reasonable middle path for small-but-real projects: bootstrap, write a
one-paragraph spec at `docs/specs/0001-<feature>.md`, skip `/plan` (the
codebase is too small to need it), use `/test-first` and `/review-check`,
skip `/review` if you're the only reviewer. Scale the loop to the work.

## Things that aren't obvious from the docs

- **`CLAUDE.md` is re-read every turn**, not just at session start. Edits
  to it take effect on the next prompt — use this to course-correct
  mid-feature ("add to don't-touch: `src/foo/legacy/`").
- **Subagents don't share memory with the main session.** That's the
  point — the reviewer hasn't seen the implementation reasoning, so it
  reads the code fresh. Don't try to "tell the reviewer" something via
  the main session; put it in the spec.
- **The PostToolUse hook can be loud.** If `ruff format` keeps fighting
  your editor, your editor is configured with different settings. Align
  them — `pyproject.toml` is the source of truth.
- **`docs/specs/` is permanent.** Specs aren't deleted after the feature
  ships — they're the project's design log. Future you, and `/review` on
  the next feature, will read them.
- **The opt-in subagents only invoke when you call them.** They are not
  auto-invoked even after you install them; the slash command is the
  trigger. Treat `/security` and `/performance` as a deliberate gate per
  PR, not a passive background check.
- **The Stop hook enforces the gate automatically — with a cap.** Once
  `src/` has pending changes, the session can't end a turn while
  ruff/mypy/pytest are red — `.claude/hooks/gate-on-stop.sh` returns
  `decision: block`. This is the `/review-check` discipline made
  mechanical, so "I forgot to run the gate" stops being a failure mode.
  It does not run on a clean tree and steps aside rather than looping
  when a gate can't pass. Know the limit: Claude Code overrides a Stop
  hook after 8 consecutive blocks without progress, so the hook is one
  rung of the completion ladder above, not the whole answer.
- **Standing rules live in two places.** `CLAUDE.md` plus
  `.claude/rules/` — rules without `paths` frontmatter load every
  session; path-scoped rules (Python conventions, agent-legible code)
  load when matching files are touched. When the agent repeats a
  mistake, the durable fix is a line in one of these files, made in the
  same change as the correction — standing instructions are the error
  log that compounds across sessions.
- **Two memory layers, different owners.** `CLAUDE.md` and
  `.claude/rules/` are human-authored and committed. Claude Code's auto
  memory is agent-authored and lives outside the repo
  (`~/.claude/projects/<project>/memory/`), shared across worktrees —
  nothing to commit or ignore. Local-only files (`CLAUDE.local.md`,
  `.claude/settings.local.json`) are gitignored; everything else under
  `.claude/` is committed and shared.
- **CI is the non-skippable gate.** `bootstrap.sh` installs
  `.github/workflows/ci.yml` — ruff + mypy + pytest on every PR. Local
  hooks and `/review-check` can be bypassed; CI cannot. Red CI means the
  PR is not done, whatever the local gate said.

## Reference

- `CLAUDE.md` + `.claude/rules/` — the rules the agent follows every turn
- `docs/workflow-diagram.md` — the same loop as a rendered visual map
  (Mermaid): the per-feature loop, the automation/guardrail layer, and
  the subagent-delegation model
- `docs/specs/README.md` — spec numbering + minimum shape
- `docs/parallel-agents.md` — worktree parallelism, agent teams, the
  completion ladder, unattended runs
- `docs/plugin-packaging.md` — the (not-yet-adopted) plugin/marketplace
  distribution path; `bootstrap.sh` remains canonical
- `.github/workflows/claude-review.yml.example` — opt-in Claude PR
  review in CI; rename to enable, needs `ANTHROPIC_API_KEY` secret
- `~/Downloads/src/agentic-scaffold/new-project-checklist.md` —
  pre-flight checklist for the day-zero setup
- Where the backlog *outside* the feature loop lives — GitHub Issues:
  the labels the issue forms reference (`feature`, `bug`, `spec-needed`,
  `triage`) and the issue ↔ spec ↔ branch ↔ PR chain.
