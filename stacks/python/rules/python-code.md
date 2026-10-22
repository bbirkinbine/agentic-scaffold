---
paths:
  - "src/**/*.py"
  - "tests/**/*.py"
---

# Python code conventions

- **The gate is the convention spec.** `pyproject.toml` configures ruff and
  mypy; what they enforce (type hints on every signature, no bare or blind
  `except`, absolute imports, Google-style docstrings on public symbols) is
  not repeated here. Fix the finding, never the config.
- **Files ≤ 300 lines.** Split aggressively; one concept per file. The
  `python-module-split` skill auto-invokes when a file approaches this.
- **`Any`** requires a comment justifying it.
- **Docstrings** say what the signature does not: units, invariants,
  side effects, and what is raised when. A one-liner is right for a trivial
  helper; a docstring that restates the name is worse than none.
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
