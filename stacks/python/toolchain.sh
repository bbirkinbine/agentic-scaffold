#!/usr/bin/env bash
# Toolchain runner — the one place this project's quality gate names its
# tools. Every consumer of the gate (the Stop hook, the edit hook,
# /review-check, CI, the scaffold smoke test) calls a subcommand here
# instead of a tool, so the stack behind the workflow can change without
# touching a hook, a command, or a role prompt.
#
# Usage: .agentic/toolchain.sh <subcommand> [args]
#
#   install               install the toolchain and dependencies
#   format [path ...]     format the given paths in place, or the whole
#                         project when none are given
#   format-check          fail if formatting would change anything
#   lint                  lint
#   typecheck             type-check the source tree
#   deps                  dependency check: undeclared imports, unused and
#                         transitive dependencies
#   test [target ...]     run the suite, or one focused target verbosely
#   gate [--quiet]        lint + format-check + typecheck + deps + test; keeps going
#                         after a failure so every red step is reported.
#                         --quiet swallows tool output and prints only
#                         "failed: <steps>" on red (nothing on green).
#   ready                 exit 0 once the project has source and test dirs
#   source-dirs           print the source directories the gate guards
#
# Python stack: uv, ruff, mypy, deptry, pytest. Tool configuration lives in
# pyproject.toml, which is project-owned; this runner is scaffold-managed.

set -uo pipefail

# .agentic/ sits one level below the project root.
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

TC_SOURCE_DIRS="src"
TC_TEST_DIRS="tests"

usage() {
  sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Exit 3 is the shared consumer protocol for an uninitialized project;
# other failures must not be interpreted as permission to skip the gate.
ready() {
  local dir
  for dir in $TC_SOURCE_DIRS $TC_TEST_DIRS; do
    [[ -d "$dir" ]] || return 3
  done
  return 0
}

tc_install() { uv sync; }
# ruff formats any file it is named, so a .json comes back as a Python dict
# (trailing commas included) and a .sh fails the hook. Keep only the
# extensions ruff's own discovery covers, which format-check enforces;
# Markdown joined that set (its Python code blocks) in ruff 0.16, the floor
# in pyproject.toml. Directories pass through, since ruff filters what it
# finds there; with no paths, format the whole tree.
tc_format() {
  (($#)) || set -- .
  local path paths=()
  for path in "$@"; do
    if [[ -d "$path" ]]; then
      paths+=("$path")
      continue
    fi
    case "$path" in
      *.py | *.pyi | *.ipynb | *.md) paths+=("$path") ;;
    esac
  done
  ((${#paths[@]})) || return 0
  uv run ruff format --force-exclude "${paths[@]}"
}
tc_format_check() { uv run ruff format --check .; }
tc_lint() { uv run ruff check .; }
tc_typecheck() { uv run mypy $TC_SOURCE_DIRS; }
tc_deps() { uv run deptry .; }
tc_test() {
  if (($#)); then
    uv run pytest -xvs "$@"
  else
    uv run pytest -x --tb=short
  fi
}

gate() {
  local quiet=0 step failed=""
  [[ "${1:-}" == "--quiet" ]] && quiet=1

  for step in lint format-check typecheck deps test; do
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
    format) shift; tc_format "$@" ;;
    format-check) tc_format_check ;;
    lint) tc_lint ;;
    typecheck) tc_typecheck ;;
    deps) tc_deps ;;
    test) shift; tc_test "$@" ;;
    *) return 1 ;;
  esac
}

case "${1:-}" in
  install | format | format-check | lint | typecheck | deps | test)
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
