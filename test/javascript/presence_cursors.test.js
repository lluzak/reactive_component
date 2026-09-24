import { describe, it, expect, vi, afterEach } from "vitest"
import { toAnchorPoint, fromAnchorPoint, findAnchor, coalesce } from "reactive_component/lib/presence_cursors"

afterEach(() => vi.useRealTimers())

// A stand-in for an element at a known place on screen. jsdom reports every
// rect as zero, so geometry has to be handed in.
function box({ left = 0, top = 0, width, height, anchor = "board_1" }) {
  return {
    dataset: { presenceAnchor: anchor },
    getBoundingClientRect: () => ({ left, top, width, height })
  }
}

describe("toAnchorPoint", () => {
  it("measures a fraction of the anchor, not a pixel", () => {
    const anchor = box({ left: 100, top: 50, width: 400, height: 200 })

    expect(toAnchorPoint({ clientX: 300, clientY: 150 }, anchor))
      .toEqual({ a: "board_1", x: 0.5, y: 0.5 })
  })

  it("gives up on an anchor with no area rather than dividing by zero", () => {
    expect(toAnchorPoint({ clientX: 1, clientY: 1 }, box({ width: 0, height: 0 }))).toBeNull()
  })
})

describe("round trip", () => {
  it("lands on the same spot when the receiver's anchor is a different size", () => {
    const sender = box({ left: 0, top: 0, width: 400, height: 200 })
    const receiver = box({ left: 700, top: 30, width: 200, height: 100 })
    const layer = box({ left: 700, top: 30, width: 200, height: 100 })

    // Sender's pointer is a quarter across and half down its own box.
    const point = toAnchorPoint({ clientX: 100, clientY: 100 }, sender)

    expect(fromAnchorPoint(point, receiver, layer)).toEqual({ x: 50, y: 50 })
  })

  it("offsets against the layer when the anchor sits inside it", () => {
    const anchor = box({ left: 120, top: 80, width: 100, height: 100 })
    const layer = box({ left: 100, top: 50, width: 300, height: 300 })

    expect(fromAnchorPoint({ a: "board_1", x: 0, y: 0 }, anchor, layer)).toEqual({ x: 20, y: 30 })
  })
})

describe("findAnchor", () => {
  it("finds the root itself", () => {
    const root = document.createElement("div")
    root.dataset.presenceAnchor = "board_1"

    expect(findAnchor(root, "board_1")).toBe(root)
  })

  it("finds a descendant", () => {
    const root = document.createElement("div")
    root.innerHTML = '<div data-presence-anchor="board_1"></div>'

    expect(findAnchor(root, "board_1")).toBe(root.firstElementChild)
  })

  it("returns nothing for an anchor this page does not have", () => {
    expect(findAnchor(document.createElement("div"), "elsewhere")).toBeNull()
  })
})

describe("coalesce", () => {
  it("sends the newest point once per interval, not every point", () => {
    vi.useFakeTimers()
    const send = vi.fn()
    const push = coalesce(send, { every: 50 })

    push({ x: 0.1, y: 0.1 })
    push({ x: 0.2, y: 0.2 })
    push({ x: 0.3, y: 0.3 })

    expect(send).not.toHaveBeenCalled()

    vi.advanceTimersByTime(50)

    expect(send).toHaveBeenCalledTimes(1)
    expect(send).toHaveBeenCalledWith({ x: 0.3, y: 0.3 })
  })

  it("drops a move too small to see", () => {
    vi.useFakeTimers()
    const send = vi.fn()
    const push = coalesce(send, { every: 50, deadband: 0.01 })

    push({ x: 0.5, y: 0.5 })
    vi.advanceTimersByTime(50)
    push({ x: 0.502, y: 0.5 })
    vi.advanceTimersByTime(50)

    expect(send).toHaveBeenCalledTimes(1)
  })

  it("sends a move past the deadband", () => {
    vi.useFakeTimers()
    const send = vi.fn()
    const push = coalesce(send, { every: 50, deadband: 0.01 })

    push({ x: 0.5, y: 0.5 })
    vi.advanceTimersByTime(50)
    push({ x: 0.6, y: 0.5 })
    vi.advanceTimersByTime(50)

    expect(send).toHaveBeenCalledTimes(2)
  })
})
