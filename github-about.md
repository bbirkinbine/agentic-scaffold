# GitHub "About" sidebar checklist

The right-side sidebar on a GitHub repo page (Settings cog next to "About")
needs three things filled in. Defaults are unhelpful; fill these in
deliberately when the repo is created.

## Description

One sentence, sentence-cased, ending in a period. Match the first sentence
of `README.md` so the description and the landing page stay in sync.

## Website

If the repo has a deployed surface (GitHub Pages, hosted docs, demo),
link it. Otherwise leave blank — don't link the GitHub repo itself, that
gives the sidebar a circular link.

## Topics (tags)

Always include:

- `ai-assisted` — signals that AI tools were involved in authoring. This
  matches the Acknowledgements line at the bottom of `README.md`.

Then add 2–5 domain tags that describe what the repo is. Pick from
GitHub's suggested topic list where possible so the repo shows up under
those topic indexes.

Common tags for my repos:

- `homelab` / `proxmox` / `packer` / `opentofu` / `ansible` — infra
- `apple-silicon` / `arm64` / `tart` / `qemu` — mac-vms-shaped repos
- `python` / `cli` / `mcp` / `rag` / `obsidian` — tool repos
- `vulnerability-management` / `ghostwriter` / `cwe` — findings-foundry-shaped

## Why `ai-assisted` matters

It's the same disclosure as the Acknowledgements line in `README.md`, just
in a place where someone browsing GitHub by topic can find it. Consistency
across both surfaces makes the disclosure self-evident — no one has to
click into the README to learn AI tools were used.
