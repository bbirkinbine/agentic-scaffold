# Secrets and public-repo hygiene

**Treat this repo as public from commit #1, even if it is currently (or
was recently) private.** Many of my repos start private and flip to
public after a feature lands. Rewriting history after that flip is
destructive — every commit SHA changes, existing clones break, and the
old state may already be archived by forks, GitHub's network view, or
anyone who cloned before the rewrite. The cheapest fix is to never
commit the thing in the first place.

The rules below apply across every public surface, not just file
contents:

- File contents and diffs
- Commit messages (subject + body) and tag annotations
- Branch names and tag names
- PR titles, descriptions, review comments
- Issue titles, bodies, comments; Discussions; wiki pages; release notes
- CI workflow logs (echoed env vars, full paths, stack traces are all
  public for public repos)
- Author + committer email on every commit — history is forever

**Never commit:**

- Live credentials of any kind — API tokens, passwords, private keys,
  signing keys, OAuth secrets, session cookies, JWTs. If one ever lands
  in a commit, **rotate it immediately**; assume any value that touched
  history is compromised the moment it lands.
- `.env*` files other than `.env.*.example` (which must contain no real
  values). Gitignore `.env.*` with an explicit `!.env.*.example`
  whitelist.
- Internal hostnames, IPs, subnets, internal URLs, VPN endpoints,
  private Slack/Discord links, IRC channels.
- Names of coworkers, managers, customers, or anyone else who hasn't
  opted in to having their name attached to this repo.
- Private-tracker identifiers — Linear/Jira/Asana ticket IDs, internal
  doc URLs, Notion share links.
- Employer references in commit messages, comments, or repo metadata.
- File paths that leak identity or employer.
- Personal info — home address, phone, personal email, ID numbers.

If the repo is currently private and a flip to public is on the table,
walk the pre-flip checklist in
`~/Downloads/src/agentic-scaffold/new-project-checklist.md` before
clicking "Change visibility."
