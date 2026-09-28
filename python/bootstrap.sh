#!/usr/bin/env bash
# Rendered entry point for the python flavor. The body is
# scripts/bootstrap-stack.sh; edit that script or stacks/python/ and re-run
# scripts/render-client-surfaces.sh. Usage is documented in the body:
#   bash path/to/agentic-scaffold/python/bootstrap.sh --help
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$REPO_DIR/scripts/bootstrap-stack.sh" --stack python "$@"
