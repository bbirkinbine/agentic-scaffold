---
description: Invoke the performance-reviewer subagent on the current diff. Requires the opt-in subagent to be installed in this project.
argument-hint: [<base>..<head> or blank for HEAD vs merge-base with main]
---

Invoke the `performance-reviewer` subagent.

Preflight: confirm `.claude/agents/performance-reviewer.md` exists in this project. If not, this project hasn't opted into performance review. Tell the user:

```
Performance-reviewer is not installed in this project. To enable:

  cp path/to/agentic-scaffold/python/.claude/agents/optional/performance-reviewer.md \
     .claude/agents/performance-reviewer.md

Then add a one-line mention under "Subagents" in CLAUDE.md so the agent knows when to invoke it.
```

And stop.

If installed, proceed.

Diff selection:

- If `$ARGUMENTS` matches `<ref>..<ref>`, use that range.
- Otherwise, use `$(git merge-base HEAD main)..HEAD`.

The performance-reviewer produces a Ghostwriter-style finding list (severity, category, location, evidence, impact, suggested fix, verification command per finding). It recommends profiling / measurement commands (`py-spy`, `scalene`, `pytest-benchmark`, `EXPLAIN ANALYZE`) — it does NOT run them. Surface the findings verbatim and surface the recommended commands clearly so the human can choose to run them.
