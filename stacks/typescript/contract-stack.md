## Stack

- TypeScript 7 on Node 24 LTS (pinned in `.nvmrc` and `package.json` → `engines`)
- {{ADD_PROJECT_SPECIFIC_LIBS — e.g., Hono / Fastify / Zod / Drizzle / logging choice}}
- Vitest
- Biome (lint + format) + `tsc --noEmit` (strict, `noUncheckedIndexedAccess`)

## How to run things

`.agentic/toolchain.sh` is the one place the gate's tools are named; the
hooks, `/review-check`, and CI call its subcommands. Use them too, so a
tool swap changes one file.

- Install: `.agentic/toolchain.sh install` (`npm ci`, or `npm install` before a lockfile exists)
- Run app: `node --experimental-strip-types src/index.ts` (or `npm run start` once defined)
- Run tests: `.agentic/toolchain.sh test` (`vitest run`)
- Single test: `.agentic/toolchain.sh test tests/index.test.ts` (or `-t "test name"`)
- Lint / format / type-check: `.agentic/toolchain.sh lint | format | typecheck`
  (biome lint, biome format, tsc on the whole project)
- The whole gate: `.agentic/toolchain.sh gate`
