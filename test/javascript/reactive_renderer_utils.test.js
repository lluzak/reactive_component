import { describe, it, expect, beforeEach, vi } from "vitest"
import {
  isBase64,
  compileTemplate,
  clearTemplateCache,
  routeMessage,
  buildActionBody,
  morphElement,
} from "reactive_component/lib/reactive_renderer_utils"

describe("isBase64", () => {
  it("returns true for valid base64 strings", () => {
    expect(isBase64(btoa("hello world"))).toBe(true)
    expect(isBase64("SGVsbG8=")).toBe(true)
    expect(isBase64("YWJj")).toBe(true)
  })

  it("returns true for multiline base64", () => {
    expect(isBase64("SGVs\nbG8=")).toBe(true)
  })

  it("returns false for raw JS code", () => {
    expect(isBase64('return "<div>" + data.name + "</div>"')).toBe(false)
  })

  it("returns false for HTML", () => {
    expect(isBase64("<div>hello</div>")).toBe(false)
  })

  it("returns false for strings with special characters", () => {
    expect(isBase64("hello world!")).toBe(false)
    expect(isBase64("foo@bar")).toBe(false)
  })
})

describe("compileTemplate", () => {
  beforeEach(() => {
    clearTemplateCache()
  })

  it("compiles a raw JS function body string", () => {
    const fn = compileTemplate('return "<p>" + data.name + "</p>"')
    expect(fn({ name: "Alice" })).toBe("<p>Alice</p>")
  })

  it("compiles a base64-encoded template", () => {
    const source = btoa('return "<span>" + data.count + "</span>"')
    const fn = compileTemplate(source)
    expect(fn({ count: 42 })).toBe("<span>42</span>")
  })

  it("returns cached function on second call with same source", () => {
    const source = 'return data.x'
    const fn1 = compileTemplate(source)
    const fn2 = compileTemplate(source)
    expect(fn1).toBe(fn2)
  })

  it("returns null for invalid JS syntax", () => {
    const fn = compileTemplate('return {{{invalid}}}')
    expect(fn).toBeNull()
  })

  it("clears cache via clearTemplateCache", () => {
    const source = 'return data.x'
    const fn1 = compileTemplate(source)
    clearTemplateCache()
    const fn2 = compileTemplate(source)
    expect(fn1).not.toBe(fn2)
    expect(fn1(({ x: 1 }))).toBe(fn2({ x: 1 }))
  })
})

describe("routeMessage", () => {
  const elementId = "message_1"

  it("routes render with matching dom_id", () => {
    const message = { action: "render", data: { dom_id: "message_1", name: "test" } }
    expect(routeMessage(message, elementId, "push")).toEqual({
      type: "render",
      data: { dom_id: "message_1", name: "test" },
    })
  })

  it("ignores render with non-matching dom_id", () => {
    const message = { action: "render", data: { dom_id: "message_2" } }
    expect(routeMessage(message, elementId, "push")).toEqual({ type: "ignore" })
  })

  it("routes update with matching dom_id", () => {
    const message = { action: "update", data: { dom_id: "message_1", starred: true } }
    expect(routeMessage(message, elementId, "push")).toEqual({
      type: "update",
      data: { dom_id: "message_1", starred: true },
    })
  })

  it("routes update with notify strategy to request_update", () => {
    const message = { action: "update", data: { dom_id: "message_1" } }
    expect(routeMessage(message, elementId, "notify")).toEqual({ type: "request_update" })
  })

  it("routes remove with matching dom_id in data", () => {
    const message = { action: "remove", data: { dom_id: "message_1" } }
    expect(routeMessage(message, elementId, "push")).toEqual({ type: "remove" })
  })

  it("routes remove with matching dom_id at top level", () => {
    const message = { action: "remove", dom_id: "message_1", data: {} }
    expect(routeMessage(message, elementId, "push")).toEqual({ type: "remove" })
  })

  it("routes destroy with matching dom_id", () => {
    const message = { action: "destroy", data: { dom_id: "message_1" } }
    expect(routeMessage(message, elementId, "push")).toEqual({ type: "destroy" })
  })

  it("routes destroy with notify strategy to request_update", () => {
    const message = { action: "destroy", data: { dom_id: "message_1" } }
    expect(routeMessage(message, elementId, "notify")).toEqual({ type: "request_update" })
  })

  it("ignores unknown actions", () => {
    const message = { action: "something_else", data: {} }
    expect(routeMessage(message, elementId, "push")).toEqual({ type: "ignore" })
  })

  it("ignores update with non-matching dom_id in push strategy", () => {
    const message = { action: "update", data: { dom_id: "message_99" } }
    expect(routeMessage(message, elementId, "push")).toEqual({ type: "ignore" })
  })
})

describe("buildActionBody", () => {
  it("includes token and action_name", () => {
    const { body } = buildActionBody("toggle_star", "abc123", {}, null)
    expect(body.get("token")).toBe("abc123")
    expect(body.get("action_name")).toBe("toggle_star")
  })

  it("converts camelCase params to snake_case", () => {
    const { body } = buildActionBody("update", "tok", { labelId: "5", isActive: "true" }, null)
    expect(body.get("params[label_id]")).toBe("5")
    expect(body.get("params[is_active]")).toBe("true")
  })

  it("strips action param from stimulus params", () => {
    const { body } = buildActionBody("test", "tok", { action: "test", color: "red" }, null)
    expect(body.has("params[action]")).toBe(false)
    expect(body.get("params[color]")).toBe("red")
  })

  it("extracts redirect and returns it separately", () => {
    const { body, redirect } = buildActionBody("test", "tok", { redirect: "/inbox" }, null)
    expect(redirect).toBe("/inbox")
    expect(body.has("params[redirect]")).toBe(false)
  })

  it("returns undefined redirect when not provided", () => {
    const { redirect } = buildActionBody("test", "tok", {}, null)
    expect(redirect).toBeUndefined()
  })

  it("merges FormData entries", () => {
    const formData = new FormData()
    formData.append("name", "Alice")
    formData.append("email", "alice@example.com")

    const { body } = buildActionBody("submit", "tok", {}, formData)
    expect(body.get("params[name]")).toBe("Alice")
    expect(body.get("params[email]")).toBe("alice@example.com")
  })
})

describe("morphElement", () => {
  let element

  beforeEach(() => {
    element = document.createElement("div")
    element.id = "target"
    element.innerHTML = "<p>old content</p>"
    document.body.appendChild(element)
  })

  it("replaces innerHTML when Idiomorph is not available", () => {
    morphElement(element, "<p>new content</p>")
    expect(element.innerHTML).toBe("<p>new content</p>")
  })

  it("calls Idiomorph.morph when global is present", () => {
    const morphMock = vi.fn()
    globalThis.Idiomorph = { morph: morphMock }

    morphElement(element, "<p>morphed</p>")

    expect(morphMock).toHaveBeenCalledOnce()
    expect(morphMock.mock.calls[0][0]).toBe(element)
    expect(morphMock.mock.calls[0][2]).toEqual({
      morphStyle: "innerHTML",
      ignoreActiveValue: true,
    })

    delete globalThis.Idiomorph
  })

  it("adds reactive-morph-flash class after morph", () => {
    morphElement(element, "<p>flash</p>")
    expect(element.classList.contains("reactive-morph-flash")).toBe(true)
  })

  it("removes and re-adds flash class to retrigger animation", () => {
    element.classList.add("reactive-morph-flash")
    morphElement(element, "<p>flash again</p>")
    expect(element.classList.contains("reactive-morph-flash")).toBe(true)
  })
})
