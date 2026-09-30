## Stack

- Python 3.12 (managed by `uv`)
- {{ADD_PROJECT_SPECIFIC_LIBS — e.g., FastAPI / Pydantic v2 / SQLAlchemy 2.0 / httpx / lxml / logging choice}}
- pytest + pytest-asyncio
- ruff (lint + format) + mypy (strict)

## How to run things

`.agentic/toolchain.sh` is the one place the gate's tools are named; the
hooks, `/review-check`, and CI call its subcommands. Use them too, so a
tool swap changes one file.

- Install: `.agentic/toolchain.sh install` (`uv sync`)
- Run app: `uv run python -m {{PACKAGE_NAME}}.main` (or `uv run {{ENTRY_POINT}}`)
- Run tests: `.agentic/toolchain.sh test` (`uv run pytest`)
- Single test: `.agentic/toolchain.sh test path/to/test.py::test_name`
- Lint / format / type-check: `.agentic/toolchain.sh lint | format | typecheck`
  (ruff check, ruff format, mypy on `src/`)
- The whole gate: `.agentic/toolchain.sh gate`
