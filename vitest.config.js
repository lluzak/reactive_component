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
      // Peer dependencies, deliberately not installed. Stubbed so the Stimulus
      // controllers are reachable from tests at all.
      "@hotwired/stimulus": path.resolve(import.meta.dirname, "test/javascript/stubs/stimulus.js"),
      "@rails/actioncable": path.resolve(import.meta.dirname, "test/javascript/stubs/actioncable.js"),
    },
  },
})
