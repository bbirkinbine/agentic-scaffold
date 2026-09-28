---
paths:
  - "src/**/*.ts"
  - "tests/**/*.ts"
---

# TypeScript code conventions

- **Files ≤ 300 lines.** Split aggressively; one concept per file.
- **ESM only.** `import`/`export`; no `require`. Named exports; a default
  export only where a framework demands one.
- **Explicit return types on exported functions.** Inferred types are fine
  inside a module; the public surface states its contract.
- **No `any` and no `!` non-null assertion without a comment** on the same
  line saying why the type system cannot express it. Prefer `unknown` plus a
  narrowing check.
- **Handle `noUncheckedIndexedAccess`.** Index reads are `T | undefined`;
  narrow them, do not assert them away.
- **Errors carry the input and the expectation.** Throw `Error` subclasses
  with a message that names what was received and what was required; never
  throw strings.
- **Async:** every promise is awaited or explicitly `void`ed with a comment;
  Biome's floating-promise rule is the backstop, `tsc` is not.
- **Logging:** follow the project choice in `AGENTS.md`. `console.log` only
  in CLIs; a structured logger for services.

## Test-first

- Runner: Vitest, through `.agentic/toolchain.sh test [target]`; a focused
  target is a test file path, or `-t "<test name>"`.
- Shared fixtures live in `tests/helpers/` and in `setupFiles` named by
  `vitest.config.ts`; the test-first phase may edit those and `tests/`,
  nothing else.
- An expected red is `TypeError: ... is not a function` or a `ReferenceError`
  for the missing export (Vitest transpiles without type checking, so a
  missing export arrives as `undefined`), a not-implemented stub throwing,
  or a behavior-level `expect` failure. `tsc --noEmit` failing on the same
  missing export is also expected at this phase. A syntax error in the test
  file, a failed import of the test file itself, or a setup-file error is
  not a red; it is a broken test.
