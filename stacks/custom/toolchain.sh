#!/usr/bin/env bash
# Toolchain runner — the one place this project's quality gate names its
# tools. Every consumer of the gate (the Stop hook, the edit hook,
# /review-check, CI) calls a subcommand here instead of a tool, so the
# stack behind the workflow can change without touching a hook, a command,
# or a role prompt.
#
# Usage: .agentic/toolchain.sh <subcommand> [args]
#
#   install               install the toolchain and dependencies
#   format                format in place
#   format-check          fail if formatting would change anything
#   lint                  lint
#   typecheck             type-check, compile, or elaborate the source tree
#   test [target ...]     run the suite, or one focused target verbosely
#   gate [--quiet]        lint + format-check + typecheck + test; keeps going
#                         after a failure so every red step is reported.
#                         --quiet swallows tool output and prints only
#                         "failed: <steps>" on red (nothing on green).
#   ready                 exit 0 once every step is filled and the source
#                         and test dirs exist
#   source-dirs           print the source directories the gate guards
#
# Custom stack: the scaffold ships no adapter for this project's tools, so
# this file starts as a template and is PROJECT-OWNED; `bootstrap.sh
# --update` never overwrites it. Fill the two FILL blocks below when the
# project has code to check:
#   - set TC_SOURCE_DIRS and TC_TEST_DIRS;
#   - replace each `unfilled <step>` with the project's real command;
#   - write `no_tool` for a step this stack has no tool for, and say so in
#     AGENTS.md -> "Stack".
# Until then `ready` fails, which keeps the Stop hook, the edit hook, and
# CI's quality job quiet; /review is the verification in that period. Never
# fill a step with a command that cannot fail in order to turn the gate on.

set -uo pipefail

# .agentic/ sits one level below the project root.
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

unfilled() {
  echo "toolchain: '$1' is not defined yet; fill it in .agentic/toolchain.sh" >&2
  return 1
}
no_tool() { return 0; }

# ---- FILL: the directories the gate guards (space-separated) -------------
TC_SOURCE_DIRS="" # e.g. "src" | "rtl" | "cmd internal" | "modules"
TC_TEST_DIRS=""   # e.g. "tests" | "sim"; empty only when tc_test is no_tool

# ---- FILL: one command per step -------------------------------------------
# Examples are for orientation (Go, then Verilog); use this project's tools.
tc_install() { unfilled install; }           # go mod download | no_tool
tc_format() { unfilled format; }             # gofmt -w . | verible-verilog-format --inplace rtl/*.v
tc_format_check() { unfilled format-check; } # test -z "$(gofmt -l .)"
tc_lint() { unfilled lint; }                 # go vet ./... | verilator --lint-only -Wall rtl/top.v
tc_typecheck() { unfilled typecheck; }       # go build ./... | yosys -q -p 'read_verilog rtl/*.v; hierarchy -check'
# "$@" is an optional focused target (a file, a test name). Run the whole
# suite when it is empty, and only the target when it is not.
tc_test() { unfilled test; }                 # go test "${@:-./...}" | make -C sim "${@:-all}"
# ---- end of FILL -----------------------------------------------------------

usage() {
  sed -n '2,35p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Ready means the gate is defined and has something to guard. A step still
# calling `unfilled` makes the whole runner not ready, so a half-filled gate
# never blocks a turn or turns CI red on a step nobody chose yet.
ready() {
  local step dir
  for step in install format format_check lint typecheck test; do
    case "$(declare -f "tc_${step}")" in
      *unfilled*) return 1 ;;
    esac
  done
  [[ -n "$TC_SOURCE_DIRS" ]] || return 1
  for dir in $TC_SOURCE_DIRS $TC_TEST_DIRS; do
    [[ -d "$dir" ]] || return 1
  done
  return 0
}

gate() {
  local quiet=0 step failed=""
  [[ "${1:-}" == "--quiet" ]] && quiet=1

  for step in lint format-check typecheck test; do
    if [[ "$quiet" == 1 ]]; then
      run_step "$step" >/dev/null 2>&1 || failed="${failed} ${step}"
    else
      echo "gate: ${step}"
      run_step "$step" || failed="${failed} ${step}"
    fi
  done

  if [[ -n "$failed" ]]; then
    echo "failed:${failed}"
    return 1
  fi
  [[ "$quiet" == 1 ]] || echo "gate: green"
  return 0
}

run_step() {
  case "$1" in
    install) tc_install ;;
    format) tc_format ;;
    format-check) tc_format_check ;;
    lint) tc_lint ;;
    typecheck) tc_typecheck ;;
    test) shift; tc_test "$@" ;;
    *) return 1 ;;
  esac
}

case "${1:-}" in
  install | format | format-check | lint | typecheck | test)
    run_step "$@"
    ;;
  gate)
    shift
    gate "$@"
    ;;
  ready)
    ready
    ;;
  source-dirs)
    printf '%s\n' "$TC_SOURCE_DIRS"
    ;;
  -h | --help | "")
    usage
    [[ -n "${1:-}" ]]
    ;;
  *)
    echo "toolchain: unknown subcommand: $1 (run with --help)" >&2
    exit 2
    ;;
esac
