#!/usr/bin/env bash
# Stack manifest, sourced by scripts/bootstrap-stack.sh. Everything the
# bootstrap needs to know about this stack that is not a file to copy.
# shellcheck disable=SC2034  # variables are consumed by the sourcing script

STACK_NAME="custom"
STACK_LABEL="custom-stack"
# Tools behind .agentic/toolchain.sh, for the bootstrap's closing summary.
STACK_TOOLS_SUMMARY="the commands this project fills into the runner"
# PROJECT-OWNED files copied once from the rendered flavor root and never
# overwritten. This stack has no adapter, so the gate runner and the CI
# workflow are the project's to write: both are MANAGED in the other stacks
# and project-owned here, which is why they are listed.
STACK_PROJECT_FILES=(.gitignore .agentic/toolchain.sh .github/workflows/ci.yml)
# One-line hint printed after bootstrap for wiring the local commit guard.
# pre-commit is a Python tool; uv, pipx, or Homebrew all provide it.
STACK_DEV_INSTALL_HINT="pre-commit install   (pre-commit via: uv tool install pre-commit | pipx install pre-commit | brew install pre-commit)"
# Printed after a first bootstrap, before the WORKFLOW.md pointer.
STACK_BOOTSTRAP_NOTE="The gate runner is a template. It stays quiet (no Stop gate, no CI quality
steps) until you fill .agentic/toolchain.sh; its header says how. Fill it
when the project has code to check, not before."
