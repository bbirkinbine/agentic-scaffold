---
paths:
  - "src/**/*.py"
  - "tests/**/*.py"
---

# Python code conventions

- **Files ≤ 300 lines.** Split aggressively; one concept per file. The
  `python-module-split` skill auto-invokes when a file approaches this.
- **Type hints required** on every function signature. `Any` requires a
  comment justifying it.
- **No bare `except:`**. Catch specific exceptions or `Exception` with a
  re-raise/log.
- **Docstrings:** Google-style. One-liner for trivial helpers; full
  args/returns/raises for public functions.
- **Imports:** absolute imports inside the package; relative only inside
  `__init__.py`.
- **Logging:** follow the project choice in `AGENTS.md` / `pyproject.toml`.
  `structlog` is a good default for services; stdlib `logging` is fine for
  small libraries and CLIs. Avoid `print` for non-CLI diagnostics.

## Test-first

- Runner: pytest, through `.agentic/toolchain.sh test [target]`; a focused
  target is `tests/test_x.py::test_name`.
- Shared fixtures live in `conftest.py` at the repository root and in
  `tests/conftest.py`; the test-first phase may edit those and `tests/`, nothing
  else.
- An expected red is `AttributeError` or `ImportError` on the missing symbol,
  `NotImplementedError` from a stub, or a behavior-level `AssertionError`.
  For a module the approved plan creates, `ModuleNotFoundError` naming that
  planned module is also an expected red, even though pytest reports it at
  collection: it fails for exactly the missing implementation, so do not
  create empty module shells to avoid it. A `SyntaxError`, a fixture error,
  or any other collection error (including an import of a module the plan
  does not create) is not a red; it is a broken test.
