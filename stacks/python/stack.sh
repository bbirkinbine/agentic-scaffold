#!/usr/bin/env bash
# Stack manifest, sourced by scripts/bootstrap-stack.sh. Everything the
# bootstrap needs to know about this stack that is not a file to copy.
# shellcheck disable=SC2034  # variables are consumed by the sourcing script

STACK_NAME="python"
STACK_LABEL="Python"
# Tools behind .agentic/toolchain.sh, for the bootstrap's closing summary.
STACK_TOOLS_SUMMARY="ruff, mypy, pytest"
# PROJECT-OWNED files copied once from the rendered flavor root and never
# overwritten: the manifest and ignore rules the project customizes.
STACK_PROJECT_FILES=(pyproject.toml .gitignore)
# One-line hint printed after bootstrap for wiring the local commit guard.
STACK_DEV_INSTALL_HINT="uv run pre-commit install"
