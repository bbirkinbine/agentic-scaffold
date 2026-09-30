# New project checklist

This is the authoritative version of the new-project checklist — it
carries the latest conventions and is updated first.

## At repo creation

- [ ] `git init` (or clone from GitHub if the repo was created on the
      web first).
- [ ] Verify the active git identity:
      ```
      git config user.name        # → Brian Birkinbine
      git config user.email       # → 585281+bbirkinbine@users.noreply.github.com
      ```
      If `user.email` is anything else, fix it before the first commit.
      The global default lives in `~/.gitconfig`; a wrong value means
      either the global got overridden or a per-repo `.git/config` is
      shadowing it.

- [ ] **Start the founding conversation.** Open Claude Code or Codex in
      the empty repo and describe the project, however roughly; the agent
      interviews you with the product-spec questions when the description
      is thin, applies the rubric in the scaffold's
      `workflow/docs/project-types.md` → "Choosing the stack from a project
      description", states the deciding question, runs the matching
      bootstrap, writes the interview answers as `docs/specs/0000-product.md`,
      and pre-fills the templates. Everything below
      is what that session does, kept here so you can check its work or do
      it by hand. The prompt:
      ```
      The agentic-scaffold checkout is at ~/src/agentic-scaffold. I want to
      build: <what it does, where it runs, who uses it, what it talks to; a rough
      idea is fine>. If that is too thin to decide anything, interview me first
      using workflow/commands/product-spec.md from the checkout, one question at
      a time. Then apply the stack rubric in workflow/docs/project-types.md,
      section 1, asking me rather than guessing where my answers do not decide
      it; tell me the deciding question; run that flavor's bootstrap.sh here;
      write the interview answers to docs/specs/0000-product.md; fill the
      placeholders from what I told you, writing "not decided yet" where that
      is the truth instead of guessing; and walk me through day zero
      (WORKFLOW.md, or the "After bootstrap" list in generic/README.md for the
      generic flavor).
      ```

### If the project will run the loop — use the agentic-workflow scaffolding

- [ ] Run the stack's bootstrap (the founding session normally does this).
      Python or TypeScript when the project is one; custom for any other
      stack (Go, Rust, FPGA/HDL, infra), where the gate runner is a
      template the project fills:
      ```
      bash path/to/agentic-scaffold/python/bootstrap.sh
      bash path/to/agentic-scaffold/typescript/bootstrap.sh
      bash path/to/agentic-scaffold/custom/bootstrap.sh
      ```
      This installs canonical `AGENTS.md` plus a `CLAUDE.md` import,
      `WORKFLOW.md`, the stack's tool configs and the `.agentic/toolchain.sh`
      gate runner, shared hooks under `.agentic/`, Claude commands/agents
      under `.claude/`, Codex skills under `.agents/`, Codex project
      configuration/agents/rules under `.codex/`, and the specs/CI surface.
      Optional specialist agents remain opt-in; see the flavor's
      `README.md`. Existing project-owned files are preserved.
- [ ] Read [`python/WORKFLOW.md`](python/WORKFLOW.md) (copied
      into the new project's root as `WORKFLOW.md`) — the human-facing
      walkthrough: day-zero setup and the per-feature loop, step by step.
- [ ] Replace every `{{PLACEHOLDER}}` in the copied files:
      ```
      rg '\{\{' .
      ```
      No `{{` markers should be left after this pass. Own the root-contract
      `AGENTS.md` content (description, don't-touch list, conventions).
      Leave `CLAUDE.md` as the `@AGENTS.md` compatibility import. Draft the
      contract by hand or with the agent, your call, but read and cut every
      line rather than committing a generated file unread. The study
      measured agent-generated context files at 0.5–2% below no context
      file and developer-written ones at 2.4% above; neither difference
      was statistically significant. It did find 20–23% higher inference
      cost for agent-generated files and up to 19% for developer-written
      files. Keep the contract short for that recurring cost and Codex's
      finite combined instruction budget, not because the study found
      short files more successful — file length itself had no significant
      effect on success. The rule is ownership, not authorship (see
      `python/README.md` → "Don't" for the study and the numbers).
      Mechanical fills like the project name in the manifest are fine
      to delegate. Fill the bootstrapped `README.md` too, preserving its
      Acknowledgements section.
- [ ] If using Codex, start it from the repository root, trust the project
      `.codex/` layer, and review the checked-in hooks with `/hooks`.
- [ ] Install dev environment:
      ```
      .agentic/toolchain.sh install
      pre-commit install        # the bootstrap prints the stack's install line
      ```
      Custom stack: skip the first line until `.agentic/toolchain.sh` is
      filled in, which happens in the first spec that adds code to check.
- [ ] Write your first spec: `docs/specs/0001-<feature>.md`. See
      `docs/specs/README.md` (copied by bootstrap) for the convention.
- [ ] Fill in `docs/agent-handoff.md` (dropped by bootstrap as a
      project-owned stub). It's the operational runbook companion to
      the root agent contract — known risks, accepted commands, rollback playbook,
      "when X breaks." Mostly empty on day zero; populated as the
      project collects landmines. Delete sections that don't apply yet
      rather than leave them as stub placeholders. Don't mirror the
      contract's "Open work / current state" here — the handoff points back
      to it.

### If the repo will not run the loop (dotfiles, notes, a one-script utility)

- [ ] Run the generic bootstrap:
      ```
      bash path/to/agentic-scaffold/generic/bootstrap.sh
      ```
      It installs canonical `AGENTS.md` plus a Claude import, Claude and Codex
      project configuration, stack-neutral safety hooks, Codex command
      rules, and `docs/codex-cli.md`.
- [ ] Replace every `{{PLACEHOLDER}}` in `AGENTS.md` and `README.md`;
      leave `CLAUDE.md` as `@AGENTS.md`. Replace the sample validation block with
      this repository's real commands; do not leave checks for a stack the
      repository does not use. Preserve the README Acknowledgements. The
      full day-zero list is `generic/README.md` → "After bootstrap".
- [ ] If using Codex, trust the project `.codex/` layer and review hooks
      with `/hooks`.

### Every flavor

- [ ] Add a `LICENSE` file (MIT for personal projects unless there's a
      reason otherwise).
- [ ] Add `.gitignore` — start from `~/.gitignore_global` (covered by
      `core.excludesfile`) and add per-language patterns. Whitelist any
      `.env.*.example` files explicitly (`!.env.*.example`).
- [ ] Gitignore client-local overlays — `CLAUDE.local.md` and
      `.claude/settings.local.json`. Personal preferences (pace,
      verbosity, machine-local paths) stay out of the shared contracts
      and checked-in client settings. The stack flavors' `.gitignore`
      already covers the Claude files; generic repos add them by hand.

## On GitHub (after `git push`)

- [ ] Fill in the **About** sidebar — see
      [`github-about.md`](github-about.md). The `ai-assisted` topic tag
      is required; it mirrors the Acknowledgements line in `README.md`.
- [ ] Description sentence in the About sidebar matches the first line of
      `README.md`.
- [ ] Repo visibility is correct (public unless there's a reason).
- [ ] Enable auto-delete of merged PR branches, so a merge on GitHub
      prunes the head branch instead of leaving stale branches to pile
      up:
      ```
      gh repo edit --delete-branch-on-merge
      ```
      Run from inside the repo (resolves owner/repo from the remote).
      This is GitHub's "Automatically delete head branches" toggle
      (Settings → General → Pull Requests). It prunes only the *remote*
      branch on merge — deleting the local branch and pruning stale
      remote-tracking refs (`git fetch --prune`) are separate. GitHub-
      backed repos only; a local-only repo has nothing to set.
      `protect-main.sh` (next step) applies this toggle too, so running
      the helper covers this box.
- [ ] Protect `main`, so "CI is the gate you can't skip" is enforced
      rather than aspirational. Run the helper from inside the repo:
      ```
      bash path/to/agentic-scaffold/scripts/protect-main.sh
      ```
      It reads the repo's shape and applies a ruleset scaled to it —
      require a PR, require the repo's own CI checks, block force pushes;
      solo repos get 0 required approvals and non-strict checks, teams get
      1 approval and strict up-to-date. Preview with `--dry-run` first.
      It **skips local-only repos** (nothing on a server to protect) and,
      when there is no CI, applies PR + no-force-push only. Without this,
      nothing stops a direct push to `main` from a plain terminal — the
      `no-commit-to-branch` pre-commit hook is local and bypassable by
      design. On the Free plan, rules on a **private** repo are not
      enforced — the helper still creates the ruleset (it warns) and it
      takes effect at the public flip (re-check it then; see below).
      Manual fallback: Settings → Rules → Rulesets → New branch ruleset
      targeting the default branch.

## First commit hygiene

- [ ] Commit message has no AI `Co-Authored-By:` trailer.
- [ ] Commit message has no generated-by-client footer.
- [ ] Diff has no real secrets, internal hostnames, or work-related
      identifiers.

## When to revisit this checklist

- New machine: re-verify `git config user.email` globally before the first
  commit on that machine.
- New shared/collab repo: identity rules still apply; AI acknowledgement
  may need a collaborator conversation.
- Forking someone else's repo: don't add the AI acknowledgement unless
  you're going to substantially rewrite — small contributions to upstream
  follow upstream's conventions.
- First installable artifact (PyPI package, CLI, container image): define
  the release story then — tags, changelog, publish workflow. The
  scaffolding deliberately ships none; add one when something ships, not
  before.

## Before flipping a private repo to public

Many of my repos start private and flip to public after the first
feature lands. The flip is irreversible in practice — rewriting history
after the fact changes every commit SHA, breaks existing clones, and the
old state may already be archived by forks, GitHub's network view, or
anyone who pulled before the rewrite. **Pre-flip scrubbing is cheap;
post-flip scrubbing is expensive and incomplete.**

The right habit is to treat the repo as public from commit #1 so this
checklist is just a final verification. If lax habits crept in during
the private phase, this is the moment to catch and fix them.

- [ ] **Author/committer emails across all branches.**
      ```
      git log --all --pretty=fuller | grep -E 'Author|Commit' | sort -u
      ```
      Every line should show the GitHub noreply address. Any other
      address (personal email, work email, an unconfigured `@local`)
      means stop — decide whether to rewrite history with
      `git filter-repo` or accept the leak.
- [ ] **Commit message audit.**
      ```
      git log --all --oneline
      git log --all --pretty=full | less
      ```
      Read every subject and body. Look for: coworker names, manager
      names, customer names, employer references, private ticket IDs
      (`PROJ-1234`, `ENG-456`), internal URLs, embarrassments.
- [ ] **Branch and tag names.**
      ```
      git branch -a
      git tag --list
      ```
      Branch named after an internal Jira ticket? Tag with an
      employer-name prefix? Rename now (`git branch -m`, `git tag <new>
      <old> && git tag -d <old>`).
- [ ] **Secret sweep across history.**
      ```
      git log --all -p | rg -i 'api[_-]?key|secret|token|password|bearer|aws_|sk-|ghp_|xox[bp]-'
      ```
      Anything that looks like a live credential gets rotated *and*
      removed from history. If you have `gitleaks` installed, run it:
      `gitleaks detect --no-banner` (and `gitleaks detect --log-opts="--all"`
      to scan history).
- [ ] **`.env*` and config files.**
      ```
      find . -name '.env*' -not -name '*.example' -not -path './.git/*'
      git ls-files | rg '\.env'
      ```
      Confirm no real env files are tracked. If one is, remove with
      `git rm --cached` and rotate everything it referenced.
- [ ] **Internal-hostname / employer / coworker sweep.**
      ```
      git log --all -p | rg -i '<employer-name>|<coworker-firstname>|\.internal|\.corp|<internal-domain>'
      ```
      Fill in the patterns from memory — the names of people, employers,
      and internal services you've worked with. Aim for false positives
      over false negatives; it's faster to skim hits than to miss one.
- [ ] **Local-path sweep.** Committed tool output (build, test, and
      synthesis logs, captured terminal sessions) prints absolute paths,
      which carry your username and directory layout.
      ```
      git log --all -p | rg -n '/(Users|home)/[A-Za-z]'
      ```
      Replace hits with `~/` or a relative path; a hit in history means
      the usual rewrite-or-start-fresh decision.
- [ ] **Issues, PRs, Discussions, Wiki on the GitHub side.**
      Flipping public exposes every issue and comment, including ones
      from collaborators. If anyone else has commented, ask them before
      flipping. If issues exist, walk each one and scrub identifying
      details from titles + bodies + comments.
- [ ] **CI workflow logs.** GitHub Actions logs become public when the
      repo does. Either delete old workflow runs (Settings → Actions →
      Caches and artifacts, plus the workflow's "Delete all logs"
      action) or audit them for echoed env vars and paths.
- [ ] **Screenshots, recordings, attached files** in `docs/`, PRs, and
      issue bodies. Crop or blur file pickers, terminal prompts, editor
      title bars. A screenshot of VS Code with `/Users/firstname.lastname/Work/<Employer>/`
      visible in the title bar is a full identity disclosure.
- [ ] **README + agent contract.** Confirm:
      - README has the AI-assisted Acknowledgements section.
      - AGENTS.md has the no-coauthor and public-hygiene rules from the
        template, and CLAUDE.md still imports it.
      - Neither contract nor README references private collaborators, employers, or
        internal context that was OK to mention privately.
- [ ] **GitHub "About" sidebar.** Once flipped, fill in description +
      `ai-assisted` topic tag — see [`github-about.md`](github-about.md).

### After flipping

- GitHub's secret scanning runs automatically on public repos and emails
  alerts for known token formats. Treat any alert as a real compromise
  and rotate. Don't dismiss alerts as false positives without checking.
- Branch protection isn't applied automatically, and rulesets created
  while the repo was private on the Free plan only start enforcing now —
  verify the `main` ruleset from the "On GitHub" section above is
  present and active (required PR, the repo's required CI checks, force
  pushes blocked). If you never ran it while private, run
  `scripts/protect-main.sh` now; if you did, re-run with `--force` to
  refresh it against the now-public shape (e.g. solo → team).
- If anything sensitive slipped through and you discover it later, your
  options are: (1) rewrite history with `git filter-repo` and force-push
  (still leaks to anyone who already cloned, but at least removes from
  HEAD), or (2) rotate the credential and move on. There is no full
  "undo" once the public version has been fetched even once.
