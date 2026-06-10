# Plugin packaging — the forward path for distribution

**Status: documented, not yet adopted.** `bootstrap.sh` (copy +
`--update` sync) remains the canonical distribution mechanism for this
scaffolding. This doc records the migration path to Claude Code's
plugin system so the move is a decision, not a research project, when
the copy model starts to chafe.

## Why plugins would replace `--update`

A Claude Code plugin bundles skills, commands, agents, hooks, and MCP
config into one versioned, installable unit, distributed through a
git-based marketplace:

```
/plugin marketplace add bbirkinbine/agentic-scaffold
/plugin install python-agentic-workflow
```

That is the sanctioned equivalent of what `bootstrap.sh --update` does
by copying MANAGED files — with version pinning, update notification,
and per-project enable/disable for free. Plugin-provided skills are
invocable as `/plugin-name:skill-name`, so collisions with project-local
commands resolve cleanly.

## What maps and what doesn't

| Scaffolding piece | Plugin home |
| --- | --- |
| `.claude/agents/*` (incl. optional) | plugin `agents/` — optional ones become install-time choices |
| `.claude/commands/*` | plugin `commands/` (or skills) |
| `.claude/skills/*` | plugin `skills/` |
| `.claude/hooks/*` + settings.json wiring | plugin `hooks/` |
| `WORKFLOW.md`, `docs/*`, `.github/*`, `pyproject.toml`, `.pre-commit-config.yaml` | **stay with bootstrap.sh** — plugins ship agent surface, not repo files |

The split matters: a plugin cannot deliver the CI workflow, pre-commit
config, or docs tree. The likely end state is hybrid — plugin for the
`.claude/` surface, a slimmer `bootstrap.sh` for repo files.

## The manifests (verified against current docs)

`.claude-plugin/plugin.json` — required fields only:

```json
{
  "name": "python-agentic-workflow",
  "description": "Spec -> Plan -> Test-first -> Implement -> Verify scaffolding for Python projects",
  "version": "1.0.0"
}
```

`.claude-plugin/marketplace.json` at the repo root makes this repo
itself the marketplace:

```json
{
  "version": 1,
  "metadata": { "description": "agentic-scaffold plugins" },
  "plugins": [
    {
      "name": "python-agentic-workflow",
      "description": "Python agentic-workflow scaffolding",
      "source": "./python"
    }
  ]
}
```

## When to actually do this

Trigger conditions — any one is enough:

- More than ~3 active projects consuming the scaffolding, making
  `--update` walks tedious.
- A second consumer besides this machine (the plugin gives them a
  version they can pin).
- The `.claude/` surface starts changing faster than the repo-file
  surface.

Until then, the copy model's one real advantage holds: every consuming
project carries the full scaffolding in its own tree, readable and
hackable with no indirection.
