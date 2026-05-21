import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Tests mutate Bun.$ cwd and rely on sequential file ordering.
    fileParallelism: false,
    testTimeout: 60_000,
    hookTimeout: 60_000,
  },
});
