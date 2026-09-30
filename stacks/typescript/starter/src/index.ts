/**
 * {{PROJECT_NAME}} entry module. Replace this with the project's real
 * surface; the starter exists so the gate is green from the first run.
 */
export function greet(name: string): string {
  if (name.length === 0) {
    throw new Error("greet: expected a non-empty name, received an empty string");
  }
  return `Hello, ${name}!`;
}
