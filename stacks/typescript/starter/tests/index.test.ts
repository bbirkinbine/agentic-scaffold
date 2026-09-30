import { describe, expect, it } from "vitest";

import { greet } from "../src/index.js";

// Placeholder so the suite is green; delete once you have real tests.
describe("greet", () => {
  it("greets by name", () => {
    expect(greet("world")).toBe("Hello, world!");
  });

  it("rejects an empty name with a message naming the expectation", () => {
    expect(() => greet("")).toThrow("non-empty name");
  });
});
