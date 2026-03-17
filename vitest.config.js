import { defineConfig } from "vitest/config"
import path from "path"

export default defineConfig({
  test: {
    environment: "jsdom",
    include: ["test/javascript/**/*.test.js"],
  },
  resolve: {
    alias: {
      "reactive_component": path.resolve(import.meta.dirname, "app/javascript/reactive_component"),
    },
  },
})
