---
description: Create a new spec at docs/specs/NNNN-<slug>.md with goal / success / non-goals scaffolding.
argument-hint: <feature name>
---

Create a new spec file under `docs/specs/`.

Procedure:

1. Determine `NNNN` — the GitHub issue number for this work, zero-padded
   to four digits (spec number = issue number = branch number; see
   `.claude/rules/git-workflow.md`):
   - If the conversation already references the issue, use that number.
   - Otherwise run `gh issue list -s open` and ask the human which issue
     this spec belongs to.
   - If no issue exists yet, stop and say so — anything past XS gets an
     issue before a spec. Offer to draft `gh issue create` for the human
     to approve.
   - Only in a repo that doesn't use GitHub issues: fall back to the
     highest existing 4-digit prefix in `docs/specs/` + 1.
   - Never reuse an existing prefix, and never use `0000` — it is
     reserved for the product spec (`docs/specs/0000-product.md`).
2. Derive a slug from `$ARGUMENTS` (lowercase, hyphen-separated, no punctuation).
3. Title-case `$ARGUMENTS` for the H1.
4. Determine today's date in `YYYY-MM-DD` (UTC or local, consistent with prior specs).
5. Write the file at `docs/specs/NNNN-<slug>.md` using this skeleton (substitute `NNNN`, the title-cased name, and today's date):

```markdown
# NNNN — <Title-cased feature name>

**Status:** draft
**Last updated:** YYYY-MM-DD

## Goal

<one paragraph: what we're building and why>

## Success criteria

- <observable, testable outcome>
- <observable, testable outcome>

## Non-goals

- <thing we are explicitly not doing>

## Notes

- <optional: known risks, dependencies, open questions>
```

The `**Status:**` and `**Last updated:**` fields are load-bearing — `/specs-status` reads them to print the status table. Don't omit them.

If the work is blocked on other specs shipping first, add a
`**Depends on:** NNNN` line directly under `**Last updated:**` —
ordering lives there, never in the spec number itself.

Stop after writing the file. Do NOT proceed to planning or implementation. The human reviews and edits the spec before any other phase. Surface the path of the file you wrote.
