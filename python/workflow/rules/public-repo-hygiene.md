# Secrets and public-repo hygiene

Treat the repository as public from commit #1, even while private. These rules
cover files and diffs; commits and tags; branch names; PRs and reviews; issues,
Discussions, wikis, and releases; CI logs; and author/committer identities.
Commit identities must use the public GitHub identity, never a work address.

**Never commit:**

- Credentials: tokens, passwords, private/signing keys, OAuth secrets,
  cookies, or JWTs. Rotate immediately if committed; assume compromise.
- `.env*` except value-free `.env.*.example`; ignore `.env.*` and explicitly
  allow only the examples.
- Internal hostnames, IPs, subnets, or URLs; VPN endpoints; private chat links.
- Non-consenting coworker, manager, or customer names.
- Private tracker IDs or internal document links.
- Employer references, identity-leaking paths, or personal information.

Before making a private repo public, audit its entire history and all surfaces:

- Inspect `git log -p` and `git log --format='%an <%ae>'`.
- Inspect branches, tags, PRs, issues, and CI logs.
- Run `gitleaks detect`; confirm only value-free `.env.*.example` files are
  tracked.

Do not change visibility until clean. History rewrites change every SHA and
cannot retract copies already held by forks, caches, or clones.

## Secrets must not enter the context window either

Tool output enters the transcript. Client policy denies `.env`/`.env.*`,
`*.pem`, and `*.key` reads anywhere in the tree, including example env files.
Never bypass it with `cat`, `env`, `printenv`, sourcing, or echoing credential
variables. The human can paste a value-free example file when needed. If
output could expose a credential, ask the human to run the command outside
the session.
