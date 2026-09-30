#!/usr/bin/env bash
# Rendered entry point for the custom flavor. The body is
# scripts/bootstrap-stack.sh; edit that script or stacks/custom/ and re-run
# scripts/render-client-surfaces.sh. Usage is documented in the body:
#   bash path/to/agentic-scaffold/custom/bootstrap.sh --help
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$REPO_DIR/scripts/bootstrap-stack.sh" --stack custom "$@"
