#!/usr/bin/env bash
# Stack manifest, sourced by scripts/bootstrap-stack.sh. Everything the
# bootstrap needs to know about this stack that is not a file to copy.
# shellcheck disable=SC2034  # variables are consumed by the sourcing script

STACK_NAME="typescript"
STACK_LABEL="TypeScript"
# Tools behind .agentic/toolchain.sh, for the bootstrap's closing summary.
STACK_TOOLS_SUMMARY="biome, tsc, vitest"
# PROJECT-OWNED files copied once from the rendered flavor root and never
# overwritten: the manifest, tool configs, and ignore rules the project
# customizes.
STACK_PROJECT_FILES=(package.json tsconfig.json biome.json vitest.config.ts .nvmrc .gitignore)
# One-line hint printed after bootstrap for wiring the local commit guard.
# pre-commit is a Python tool; uv, pipx, or Homebrew all provide it.
STACK_DEV_INSTALL_HINT="pre-commit install   (pre-commit via: uv tool install pre-commit | pipx install pre-commit | brew install pre-commit)"
