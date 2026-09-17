import { describe, it, expect, afterEach, vi } from "vitest"
import ReactiveRendererController from "reactive_component/controllers/reactive_renderer_controller"

// The controller is exercised without Stimulus: these are plain methods, and
// wiring up an application would test Stimulus rather than the gem.
function build(attributes = {}) {
  const element = document.createElement("div")
  Object.entries(attributes).forEach(([name, value]) => element.setAttribute(name, value))
  // Stimulus reads element off the context it is constructed with.
  return new ReactiveRendererController({ scope: { element } })
}

afterEach(() => vi.restoreAllMocks())

describe("log", () => {
  it("says nothing on a wrapper the server did not mark for debugging", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {})

    build().log("render", "message_1")

    expect(spy).not.toHaveBeenCalled()
  })

  it("logs when ReactiveComponent.debug marked the wrapper", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {})

    build({ "data-reactive-debug": "Message row #message_1" }).log("render", "message_1")

    expect(spy).toHaveBeenCalledWith("[reactive-renderer]", "render", "message_1")
  })
})
