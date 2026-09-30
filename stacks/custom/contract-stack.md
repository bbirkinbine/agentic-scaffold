## Stack

- {{LANGUAGES_AND_RUNTIME — e.g. Verilog on an ECP5 FPGA; Go 1.25; Terraform + shell. Write "not chosen yet; spec NNNN chooses it" when that is the truth}}
- {{TOOLS_BEHIND_EACH_GATE_STEP — formatter, linter, type/compile check, test runner; "none" for a step this stack has no tool for}}
- {{ADD_PROJECT_SPECIFIC_LIBS_OR_VENDORED_SOURCES}}

## How to run things

`.agentic/toolchain.sh` is the one place the gate's tools are named; the
hooks, `/review-check`, and CI call its subcommands. Use them too, so a
tool swap changes one file.

The scaffold has no adapter for this stack, so the runner starts as a
template and this project owns it. Until every step is filled, `ready`
fails: the Stop gate, the edit hook, and CI's quality job stay quiet,
`/review-check` reports that the gate is not defined, and `/review` is the
verification. Fill the runner in the first spec that adds code to check.
Never fill a step with a command that cannot fail.

- Install: `.agentic/toolchain.sh install`
- Run it: {{HOW_TO_RUN_OR_BUILD — or "nothing runs yet"}}
- Run tests: `.agentic/toolchain.sh test`
- Single test: `.agentic/toolchain.sh test <target>`
- Lint / format / type-check: `.agentic/toolchain.sh lint | format | typecheck`
- The whole gate: `.agentic/toolchain.sh gate`

## Code conventions

{{CONVENTIONS_A_REVIEWER_CAN_CHECK — file-size limit, naming, error handling, layout. "None yet" is a valid answer before there is code}}

### Test-first

- Runner: {{TEST_RUNNER}} through `.agentic/toolchain.sh test [target]`; a
  focused target is {{WHAT_A_TARGET_IS — a file path, a test name}}.
- Shared fixtures live in {{FIXTURE_PATHS}}; the test-first phase may edit
  those and the test directories, nothing else.
- An expected red is {{WHAT_A_MISSING_BEHAVIOR_LOOKS_LIKE — a failed
  assertion, a missing symbol, a not-implemented stub}}. A syntax error in
  the test itself or a broken fixture is not a red; it is a broken test.
- Work that produces no code to test (research, documentation, measurements)
  skips `/test-first`. Its spec names the evidence each success criterion
  will be checked against, and `/review` checks that evidence.
