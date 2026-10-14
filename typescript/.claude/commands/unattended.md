---
description: Prepare a feature to run unattended — overnight, or while you are away for the day (ask every foreseeable decision up front and record standing consent), or reconcile the decisions an unattended run made on the human's behalf.
argument-hint: "start [spec-path] | reconcile [spec-path]"
---

Unattended mode lets a feature run to "ready to merge" with nobody watching,
for a night or a day away: the human answers everything foreseeable before
leaving, the orchestrator answers the rest on their behalf and logs each
answer, and the human reconciles the log on return. See `docs/parallel-agents.md` →
"One feature while you are away" when installed.

Resolve the active spec under `AGENTS.md` → **Shared workflow protocols** →
**Active-spec resolution** (or use the path in `$ARGUMENTS`). Ambiguity
stops.

## `start` — before the human leaves

Run after the plan is approved and persisted, before test-first.

1. Read the spec, its `## Approved implementation plan`, `AGENTS.md`, and
   any earlier `## Standing decisions`. List every decision the run is
   likely to hit, highest leverage first:
   - success criteria or plan steps that admit more than one reasonable
     reading, and behavior the tests will not pin;
   - choices the plan defers ("assume", "TBD", "if needed") or leaves to
     taste: names, layout, messages, defaults;
   - look and feel, for anything a person will see: what it should look
     like and how it should play or read, as measurably as the human can
     put it, since nobody will see it until the run ends;
   - scope edges: adjacent work the plan neither claims nor excludes;
   - baseline: which existing branch, config, or scaffold changes are
     already accepted and must not be redone or reviewed as new;
   - verification the run cannot do itself (manual or browser checks):
     defer it to the morning or skip it;
   - failure handling: if a step stays red or local delegation fails,
     fall back to the frontier model or stop.
2. Ask them in one batch, each naming the spec or plan line it affects and
   offering your best-guess default so "defaults are fine" is a complete
   answer. Ask only what the spec, plan, and `AGENTS.md` do not already
   settle; say so if nothing needs asking.
3. Record the answers in the spec under `## Standing decisions`, one bullet
   each (`<decision>: <answer> (asked <date>)`), and add `## Overnight
   decisions` with the line `None yet.` The run treats standing decisions
   as the human's answers.
4. Ask for standing consent explicitly and record it under `## Standing
   decisions` as one line: unattended shipping authorized through
   "ready to merge" (branch green, review clean, uncommitted), or through
   commits on the feature branch if the human grants that. Never push or
   merge.
5. Print the kickoff instruction the human can leave running, then stop.

## During the run — auto-answering

With standing consent recorded, an `[ask-user]` finding or question that a
standing decision does not settle no longer stops the run. The orchestrator:

1. picks the answer the human would most likely choose, judged from the
   spec, the plan, `AGENTS.md`, and the standing decisions, preferring the
   smallest change that keeps the approved plan intact;
2. appends an entry under `## Unattended decisions`: the question, the
   choice, the alternatives considered, why, the files it affected, and how
   to reverse it;
3. keeps that decision's changes separable — its own commit when commits
   were granted, otherwise a list of the exact hunks — and continues.

It still stops, and leaves the run at its last green state, for anything
irreversible or outside the approved plan: deleting or rewriting history,
new dependencies, changes to `.agentic/`, CI, or security-relevant
configuration, files outside the plan, or a spec the run has shown to be
wrong. Those wait for the human.

## `reconcile` — when the human is back

1. Read `## Unattended decisions`. For each entry, show the human the
   question, the choice, and its diff, and ask: keep or override (with the
   preferred answer).
2. Apply every override as a normal change: edit, gate, and a fresh focused
   review of the delta, then mark the entry `kept` or `overridden → <new
   answer>`. Move decisions worth keeping for future runs into
   `## Standing decisions`.
3. Report what changed, then stop for commit authorization as usual.
