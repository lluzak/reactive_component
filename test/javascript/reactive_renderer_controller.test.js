import { describe, it, expect, afterEach, vi } from "vitest"
import ReactiveRendererController from "reactive_component/controllers/reactive_renderer_controller"

// The controller is exercised without Stimulus: these are plain methods, and
// wiring up an application would test Stimulus rather than the gem.
function build(attributes = {}, props = {}) {
  const element = document.createElement("div")
  Object.entries(attributes).forEach(([name, value]) => element.setAttribute(name, value))
  // Stimulus reads element off the context it is constructed with.
  const controller = new ReactiveRendererController({ scope: { element } })
  // Stimulus value readers are prototype getters, so stand them up as own
  // properties rather than wiring a whole application to hold the data.
  Object.entries(props).forEach(([name, value]) => {
    Object.defineProperty(controller, name, { value, writable: true })
  })
  return controller
}

const frame = () => new Promise(resolve => requestAnimationFrame(resolve))

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

describe("rerender", () => {
  it("renders a push component from the data it already holds", async () => {
    const render = vi.fn()
    const controller = build({}, {
      lastServerData: { count: 2 }, renderFn: () => "", clientState: { open: true }, render, strategyValue: ""
    })

    controller.rerender()
    await frame()

    expect(render).toHaveBeenCalledWith({ count: 2, open: true })
  })

  it("asks the server when a notify component has no data yet", () => {
    const requestUpdate = vi.fn()
    const controller = build({}, {
      lastServerData: null, renderFn: () => "", clientState: { open: true }, requestUpdate, strategyValue: "notify"
    })

    controller.rerender()

    expect(requestUpdate).toHaveBeenCalled()
  })

  it("leaves a push component alone until its data arrives", async () => {
    const render = vi.fn()
    const requestUpdate = vi.fn()
    const controller = build({}, {
      lastServerData: null, renderFn: () => "", clientState: {}, render, requestUpdate, strategyValue: ""
    })

    controller.rerender()
    await frame()

    expect(render).not.toHaveBeenCalled()
    expect(requestUpdate).not.toHaveBeenCalled()
  })
})
