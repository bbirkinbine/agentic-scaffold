---
description: Print a status table of all specs under docs/specs/, aggregating the **Status:** line from each spec file. Read-only — does not modify any spec.
argument-hint: [status filter — e.g. "draft", "shipped", "abandoned"]
---

Print a status table for every spec under `docs/specs/`.

Procedure:

1. Find all `.md` files under `docs/specs/` excluding `README.md`.
2. For each file, extract:
   - The H1 title (the first line that starts with `#`).
   - The `**Status:**` value (the line that begins with `**Status:**`).
   - The `**Last updated:**` value.
3. If `$ARGUMENTS` is non-empty, filter rows to specs whose status matches `$ARGUMENTS` (case-insensitive).
4. Group rows by status and print as a markdown table with columns: `Status` | `Spec` | `Last updated`. Within each group, sort by the 4-digit spec number ascending.
5. Order the groups: `draft`, `shipping`, `shipped`, `paused`, `abandoned`, then any `superseded-by-NNNN`, then any unrecognized status. This puts "what's in flight" at the top and the design log of "decided not to do this" at the bottom.
6. Below the table, print a one-line count per status. Example: `7 shipped · 1 shipping · 2 draft · 1 abandoned`.
7. Flag specs missing the `**Status:**` field as a separate "Needs attention" list. Do not guess their status; surface the filename and stop short of editing.

Suggested one-shot extraction (use this or equivalent):

```bash
# NOTE: avoid the variable name `status` — it's a read-only built-in in zsh.
for spec in docs/specs/*.md; do
  [ "$(basename "$spec")" = "README.md" ] && continue
  title=$(awk 'NR==1 && /^# / { sub(/^# */,""); print; exit }' "$spec")
  spec_status=$(awk '/^\*\*Status:\*\*/ { sub(/^\*\*Status:\*\* */,""); print; exit }' "$spec")
  updated=$(awk '/^\*\*Last updated:\*\*/ { sub(/^\*\*Last updated:\*\* */,""); print; exit }' "$spec")
  printf '%s|%s|%s|%s\n' "${spec_status:-MISSING}" "$spec" "${updated:-?}" "$title"
done
```

This command is read-only. Do not edit any spec to "fix" a missing status — that's the human's call. Surface the gaps; let them adjudicate.
