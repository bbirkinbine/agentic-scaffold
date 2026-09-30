# Does the language still matter? Evidence for the multi-stack plan

**Status:** research note, 2026-09-26, revised the same day after a
refutation pass (see *Verification record*). Companion to
[`multi-stack-scaffold.md`](multi-stack-scaffold.md), which holds the plan.
This note holds the evidence the plan rests on and what could not be
established.

> **How to read this note.** Prose is clean; evidence sits in footnotes.
> Hover or jump for the source, its tier, and how solid it is. Numbers this
> note computed rather than found are marked `~` inside the cell. What could
> not be verified is in *Verification record*, and the gaps a decision rests
> on are also stated in the body where they bite.

## The question

Agentic coding lowers the cost of writing in any mainstream language to
near zero. Does that make the language choice irrelevant, and if not, what
does the scaffold owe a non-Python project?

## Findings

### 1. In 2025, agents resolved far fewer issues outside Python, and the two multilingual benchmarks disagreed on which languages were hard

On Multi-SWE-bench (ByteDance, NeurIPS 2025), the best 2025 configuration
resolved 52% of the SWE-bench Python comparison set but far fewer in every
Multi-SWE-bench language[^mswe]:

| Language | Best resolved rate, 2025 | Type |
| --- | --- | --- |
| Python (SWE-bench comparison set) | 52.2% | measured |
| Java | 23.4% | measured |
| Rust | 15.9% | measured |
| C++ | 14.7% | measured |
| TypeScript | 11.6% | measured |
| C | 8.6% | measured |
| Go | 7.5% | measured |
| JavaScript | 5.1% | measured |

The authors write that TypeScript and JavaScript "consistently yield the
lowest resolved rates, highlighting the difficulty LLMs face in handling
their event-driven, asynchronous programming paradigms"[^mswe].

SWE-bench Multilingual (300 tasks, 9 languages, no Python) reports a
different ordering for a different harness on the same model
family[^swebm]:

| Language | Resolved, Claude 3.7 Sonnet + SWE-agent | Type |
| --- | --- | --- |
| Rust | 58.1% (25/43) | measured |
| Java | 53.5% (23/43) | measured |
| PHP | 48.8% (21/43) | measured |
| Ruby | 43.2% (19/44) | measured |
| JavaScript / TypeScript | 34.9% (15/43) | measured |
| Go | 31.0% (13/42) | measured |
| C / C++ | 28.6% (12/42) | measured |

The two benchmarks agree only that JavaScript and TypeScript sit in the
bottom half. They disagree on Go and Rust by a factor of two or more, and
the second has no Python row at all. Task selection and harness explain
more of the spread than the language does, so neither table is a ranking to
steer a language choice by.

### 2. In 2026 the per-language picture is model-specific, and Python no longer leads

The one 2026 paper found with per-language rates for current models is
SWE-Bench ProMax (COLM 2026), a refactoring benchmark of 170 instances
across seven languages, evaluated under the OpenHands scaffold[^promax]:

| Model | Python | Java | TypeScript | Go | C | C++ | Rust |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GPT-5.2 | 48.3 | 19.2 | 35.7 | 26.1 | 75.0 | 36.4 | 54.5 |
| Claude Sonnet 4.6 | 17.2 | 30.8 | 53.6 | 26.1 | 50.0 | 36.4 | 63.6 |
| GLM-5 | 20.7 | 34.6 | 28.6 | 34.8 | 65.0 | 45.5 | 36.4 |
| Qwen3.5 | 37.9 | 26.9 | 17.9 | 39.1 | 65.0 | 54.5 | 22.7 |
| Kimi-K2.5 | 24.1 | 30.8 | 10.7 | 43.5 | 70.0 | 45.5 | 18.2 |
| Gemini-3-Pro | 13.8 | 19.2 | 0.0 | 8.7 | 45.0 | 36.4 | 22.7 |

All values are measured resolve rates in percent; per-language n is 20 to
29, so a single instance moves a cell by 3 to 5 points. Python is the best
language for one model of six. Claude Sonnet 4.6 resolves three times as
much Rust and TypeScript as Python. The ordering of languages changes with
every model row.

Aggregate SWE-bench Multilingual scores for the newest models are above 0.9
on a public aggregator, against 0.43 for the 2025 baseline[^agg]. Other
2026 multilingual papers report aggregates only[^open].

**Two things this does not establish.** ProMax measures refactoring, not
issue resolution, with early-2026 models; a per-language breakdown of the
current frontier class on either issue-resolution benchmark was not found
(see *Verification record*). What would settle it: per-language rates for
a current model on SWE-bench Multilingual or Multi-SWE-bench, which either
leaderboard could publish from data it already has.

What the evidence does support: the 2025 "Python first, web languages last"
pattern was an artifact of two models and two harnesses. Per-language
capability in 2026 is uneven in a way that depends on the model and the
task, not on the language in any stable order.

### 3. Strict static checking helps agent-written code, by mechanism and by one controlled measurement; the repository-scale evidence is weak

Type-constrained decoding, which rejects tokens that cannot type-check,
"reduces compilation errors by more than half and significantly increases
functional correctness" on TypeScript translations of HumanEval and
MBPP[^tcg]. That is a decoding technique, not a workflow, so it supports the
mechanism (type information caught errors the model would have emitted)
rather than the specific claim that running `tsc` in a hook helps.

The large-scale repository evidence that typed languages have fewer defects
is contested. The 2014 GitHub study itself described the effect as small,
and the 2019 reproduction could mostly replicate one of its four research
questions, found the second's results "meaningless" after fixing
classification errors, could not repeat the other two, and on reanalysis
cut the languages with a significant defect association from eleven to four
with an "exceedingly small" effect and the conclusion that "causation is not
supported by the data at hand"[^ray]. Do not cite "typed languages have
fewer bugs" as a finding.

The claim the plan makes is narrower and is reasoning, not measurement: a
strict compiler and type checker in the Stop gate is a reviewer that runs on
every turn, costs nothing, and produces localized errors the agent can act
on. Finding 2 adds a second reason to make that gate uniform across stacks:
since no one can predict from the language alone where a given model will
be weak, the verification layer cannot be allowed to vary by language.

### 4. The TypeScript toolchain moved under the plan while it was being written

Three facts change the TypeScript defaults, all months-old and decaying at
software speed:

- **TypeScript 7.0 shipped 2026-07-08** as the standard `typescript`
  package, on a native Go compiler that Microsoft reports at 8x to 12x
  faster on full builds, with `strict` on by default. It "does not yet
  expose a stable programmatic API"; Microsoft expects 7.1 "to ship with a
  new (and different) API"[^ts7].
- **typescript-eslint supports `>=4.8.4 <6.1.0`**[^tseslint], so ESLint's
  type-aware rules cannot run against TypeScript 7 until 7.1 exposes the
  API; Microsoft's stated workaround is the `@typescript/typescript6`
  compatibility package side by side[^ts7].
- **Biome v2.5 (2026-06-05)** passed 500 rules, its type-aware rules use its
  own inference engine rather than the TypeScript compiler, and it added
  `--reporter concise` with the stated purpose "If you use a coding agent,
  this is the perfect reporter because it will save you tokens"[^biome].

Together these make Biome the workable default for a project starting on
TypeScript 7 today, on top of the single-tool argument the plan already
made. The trade is explicit: Biome's own v2 announcement says its
type-aware floating-promise detection catches "about 75% of the cases"
typescript-eslint would[^biome], so choosing Biome trades a version-support
gap for a rule-coverage gap. `tsc --noEmit` in the same gate covers what a
linter's partial inference misses at the type level, which is why the plan
runs both. Falsifier: when 7.1 ships its API and typescript-eslint adds
support, the ESLint alternative reopens on equal footing and the coverage
gap argues for it; Biome then wins only on the single-tool argument.

Pinned runtime facts for the starter[^node][^vitest]:

| Item | Value on 2026-09-26 | Decay |
| --- | --- | --- |
| Node Active LTS | 24.x; 26.x becomes LTS in October 2026 | months |
| Node schedule from 27 | one major per year in April, LTS in October, 30 months of LTS | years |
| Vitest | 5.0 (2026-09-03) | months |
| TypeScript | 7.0 (2026-07-08), 7.1 expected on a 3–4 month cadence | months |
| Biome | 2.5 (2026-06-05) | months |

### 5. Go and Rust have first-party gates that map onto the runner's subcommands directly

| Subcommand | Go | Rust |
| --- | --- | --- |
| format | `gofmt -l` / `goimports` | `cargo fmt --check` |
| lint | `go vet ./...` + golangci-lint v2 (`errcheck`, `staticcheck` at minimum) | `cargo clippy -- -D warnings` |
| typecheck | the compiler: `go build ./...` | `cargo check` |
| test | `go test ./...` | `cargo test` |
| audit | `govulncheck ./...`, which filters advisories to reachable calls | `cargo audit` on `Cargo.lock`; `cargo deny` adds license and source policy |

golangci-lint v2.14.0 is current (2026-09-24) and Go 1.27 is the current
major (2026-08-19), with each major supported until two newer ones
exist[^go]. govulncheck is Go-team maintained and "reduces noise by
prioritizing vulnerabilities in functions that your code is actually
calling"[^govuln]. cargo-audit lives in the RustSec organization and
cargo-deny in Embark Studios'[^rustsec]. These are documented facts about
stable tools, not benchmarks; the rows exist to show every subcommand the
runner needs has a first-party or de facto standard answer in both
languages.

## What this means for the scaffold

1. **The scaffold today steers toward Python for the wrong reason.** A
   non-Python project gets no Stop gate, no test-first roles, and no CI, so
   the workflow, not the project, decides the language. Nothing in the
   evidence supports Python as a safer default for agent work in 2026;
   finding 2 shows the opposite for some models.
2. **Parity is the yardstick, and the Python flavor defines it.** The
   maturity matrix in the plan lists what the Python flavor has, item by
   item. A stack is "done" when every row has an answer that the smoke test
   exercises.
3. **Choose the language for the project, and let the gate carry the
   difference.** The agent's per-language strength is real but
   model-specific and unstable (findings 1 and 2), the compiler is the
   cheapest reviewer available (finding 3, as reasoning), and every
   candidate stack has the tools to fill the runner (findings 4 and 5).

This direction rests on workflow parity, not on any language being
harder for agents. Falsifier for the plan itself: a consumer project on a
second stack where the parity gate catches nothing the language's own
tooling would not have caught unprompted. That would mean the runner seam
is bookkeeping, and a thinner `generic/`-plus-CI answer would do.

## Verification record

A refutation pass on the first draft fetched every cited source and
reported back. Its findings, and what changed:

- **Reversed: "no per-language breakdown for 2026 models exists".** The
  first draft said every 2026 source reported aggregates and told the plan
  to assume a smaller-but-nonzero Python advantage. SWE-Bench ProMax
  Table 3 has per-language rates for six early-2026 models; its abstract
  does not, which is what the first draft had checked. The table is now
  finding 2, and the "gate matters most where the agent is weakest" claim
  that rested on the gap was removed from this note and from the plan.
- **Reversed: "the two 2025 benchmarks agree that Python leads".**
  SWE-bench Multilingual has no Python tasks, so it could not agree to
  that. Finding 1 now claims only the JavaScript/TypeScript agreement.
- **Downgraded: the Berger reproduction summary.** "Replicated two of four
  research questions" counted a question whose results the authors called
  meaningless. Rewritten to the authors' own account, and the reanalysis
  result (eleven languages down to four, effect "exceedingly small") added.
  "Weak association", presented as the original authors' words, was a
  paraphrase; replaced with their "the effect is small".
- **Added: the Biome coverage caveat.** Biome's v2 post states its
  type-aware floating-promise rule catches about 75% of typescript-eslint's
  cases. The first draft called Biome "lower-risk" without it.
- **Citation fixed:** rustsec.org names the advisory database's maintainer,
  not cargo-audit's or cargo-deny's; the footnote now points at the
  repositories.
- **Softened:** TypeScript 7.1's API is "expected", not "promised".
- **Still not found: per-language rates for the current frontier class on
  an issue-resolution benchmark.** Searched SWE-bench Multilingual (site
  and aggregator), Multi-SWE-bench (paper, repo, and a site that renders no
  leaderboard content), SWE-PolyBench (README and abstract; its leaderboard
  page was not fetched), Aider polyglot (aggregate only by design),
  Open-SWE-Traces (aggregate only, body checked). Two leads were judged
  unusable: Anthropic's Claude Opus 4.5 announcement (2025-11-24) has a
  per-language SWE-bench Multilingual chart as an image only, and a
  tier-5 blog with own-run Multi-SWE-bench numbers gives no harness or n.
- **The two 2025 tables are not comparable to each other.** Different task
  sets, different harnesses (MopenHands / MSWE-agent vs SWE-agent), and
  Multi-SWE-bench's Python row is its SWE-bench comparison. They are
  presented side by side to show the disagreement, not to average.
- **The 2026 aggregator numbers are tier-5 evidence.** The aggregator page
  describes the benchmark's languages with Multi-SWE-bench's list rather
  than SWE-bench Multilingual's, so it may be mixing benchmarks. The
  direction (a large aggregate rise) is corroborated by vendor system-card
  figures quoted secondhand; the numbers are used for direction only.
- **TypeScript 7.0 date conflict resolved.** InfoQ reported 2026-08-03; the
  Microsoft announcement is dated 2026-07-08. The primary source wins.
- **TypeScript 7.1 dates.** "Beta 2026-10-06, stable 2026-11-24" appeared
  only in secondary blogs; the Microsoft post commits only to a 3–4 month
  cadence, which is what this note states.
- **Node 26 LTS date.** The Node.js announcement fetch mislabeled 26 as
  already LTS; endoflife.date shows it released 2026-05-05 with the LTS
  promotion in October 2026. The latter is used.
- **A single-developer case study** claiming typed languages surface defects
  inside the agent loop turned up in search; its abstract does not contain
  that claim, and n=1 would not carry it anyway. Not cited.

## Grounding notes

[^mswe]: Zan et al., "Multi-SWE-bench: A Multilingual Benchmark for Issue
    Resolving", [arXiv:2504.02605](https://arxiv.org/abs/2504.02605),
    NeurIPS 2025 Datasets and Benchmarks (acceptance per the project
    README). Table 4, maximum per language across all 27 model/framework
    rows; every maximum is a Claude 3.5 or 3.7 Sonnet row with MopenHands
    or MSWE-agent. 1,632 instances, 7 languages; the Python row is the
    paper's SWE-bench comparison. Quote verbatim from the paper. Retrieved
    2026-09-26. Measured, single benchmark; models are two generations old.
[^swebm]: SWE-bench Multilingual,
    <https://www.swebench.com/multilingual.html>, 300 tasks, 42
    repositories, 9 languages, no Python. Per-language rates for Claude 3.7
    Sonnet with SWE-agent, 128/300 = 43% overall. Retrieved 2026-09-26.
    Measured, n=1 model and harness.
[^promax]: "SWE-Bench ProMax: Benchmarking Agents on Large-Scale
    Multilingual Code Refactoring", [arXiv:2608.09802](https://arxiv.org/abs/2608.09802)
    (2026-08-10), COLM 2026. Table 3 (OpenHands scaffold), reproduced
    exactly; per-language instance counts from Table 5: Python 29, Java 26,
    TypeScript 28, Go 23, C 20, C++ 22, Rust 22. Retrieved 2026-09-26.
    Measured; refactoring tasks, small n per language.
[^agg]: [llm-stats SWE-bench Multilingual
    leaderboard](https://llm-stats.com/benchmarks/swe-bench-multilingual),
    "last updated 2026-09-26": Claude Opus 5.5 at 0.939, ten models above
    0.77. Tier-5 aggregation, harness unknown, possible benchmark mixing
    (see *Verification record*). Used for direction only.
[^open]: "Open-SWE-Traces", [arXiv:2606.16038](https://arxiv.org/abs/2606.16038),
    2026-06-14; nine languages, overall percentages only in Tables 3 and 4.
[^tcg]: Mündler et al., "Type-Constrained Code Generation with Language
    Models", [arXiv:2504.09246](https://arxiv.org/abs/2504.09246), PLDI
    2025 (DOI 10.1145/3729274). TypeScript; models of various sizes
    including >30B open-weight. Quote verbatim from the abstract.
    Measured; a decoding method, not a workflow.
[^ray]: Ray et al., "A Large Scale Study of Programming Languages and Code
    Quality in GitHub", FSE 2014 (RQ1 as quoted by Berger et al.: "Some
    languages have a greater association with defects than others, although
    the effect is small"); Berger et al., "On the Impact of Programming
    Languages on Code Quality: A Reproduction Study",
    [TOPLAS 2019](https://dl.acm.org/doi/10.1145/3340571), open copy at
    <https://janvitek.org/pubs/toplas19.pdf>. Quotes verbatim from the
    reproduction. Contested; cited only to warn.
[^ts7]: Microsoft, "Announcing TypeScript 7.0",
    <https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/>,
    2026-07-08. Speedups are Microsoft-reported on named codebases
    (VS Code 11.9x, Sentry 8.9x, Bluesky 8.7x). Names
    `@typescript/typescript6` for tools such as typescript-eslint.
    Retrieved 2026-09-26. Documented; decays in months.
[^tseslint]: typescript-eslint, "Dependency Versions",
    <https://typescript-eslint.io/users/dependency-versions/>, supported
    TypeScript range `>=4.8.4 <6.1.0`. The page says nothing about
    TypeScript 7; the incompatibility inference comes from the Microsoft
    post. Retrieved 2026-09-26. Documented; decays in months.
[^biome]: Biome, "Biome v2.5" (2026-06-05)
    <https://biomejs.dev/blog/biome-v2-5/>; "Roadmap 2026" (2026-01-21)
    <https://biomejs.dev/blog/roadmap-2026/>; "Biome v2, codename Biotype"
    (2025-06-17) <https://biomejs.dev/blog/biome-v2/>. The concise-reporter
    quote is from the v2.5 post; the "about 75% of the cases" figure for
    `noFloatingPromises` and the "doesn't rely on the TypeScript compiler"
    statement are from the v2 post. Retrieved 2026-09-26. Documented.
[^node]: Node.js, "Evolving the Node.js Release Schedule"
    <https://nodejs.org/en/blog/announcements/evolving-the-nodejs-release-schedule>
    (2026-03-10), and <https://endoflife.date/nodejs>. Retrieved
    2026-09-26. Documented.
[^vitest]: Vitest blog, "Announcing Vitest 5.0", 2026-09-03,
    <https://vitest.dev/blog/>. Retrieved 2026-09-26. Documented.
[^go]: golangci-lint releases
    <https://github.com/golangci/golangci-lint/releases> (v2.14.0,
    2026-09-24); Go release history <https://go.dev/doc/devel/release>
    (Go 1.27.0, 2026-08-19). Retrieved 2026-09-26. Documented.
[^govuln]: Go blog, "Govulncheck v1.0.0 is released",
    <https://go.dev/blog/govulncheck>, 2023-07-13. Quote verbatim.
    Documented; the reachability claim is the tool's own.
[^rustsec]: cargo-audit: <https://github.com/rustsec/rustsec> (RustSec
    organization; <https://rustsec.org/> states the advisory database is
    maintained by the Rust Secure Code Working Group). cargo-deny:
    <https://github.com/EmbarkStudios/cargo-deny>. Retrieved 2026-09-26.
    Documented.
