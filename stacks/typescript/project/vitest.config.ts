import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["tests/**/*.test.ts"],
    // Shared fixtures and setup go here; the test-first phase may edit
    // these files and tests/, nothing else (AGENTS.md -> Test-first).
    setupFiles: [],
  },
});
