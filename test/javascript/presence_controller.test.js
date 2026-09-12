import { describe, it, expect, vi, beforeEach } from "vitest"

// Stimulus and ActionCable are peer dependencies and are not installed, which
// is why this controller had no tests and kept regressing. They are aliased to
// stubs in vitest.config.js; the cable registry is mocked here so a test can
// see what was performed.
const performed = []
let connected = true

const subscription = {
  perform(action, data) { performed.push({ action, data }) }
}

vi.mock("reactive_component/lib/cable_subscriptions", () => ({
  subscribe: (_stream, handler) => { if (connected) handler.subscriptionConnected() },
  unsubscribe: () => {},
  findSubscription: () => subscription
}))

const { default: PresenceController } = await import(
  "reactive_component/controllers/presence_controller"
)

const ana = { id: 1, name: "Ana" }
const tom = { id: 2, name: "Tom" }

function build({ cursors = false, autoConnect = true } = {}) {
  performed.length = 0
  connected = autoConnect

  const element = document.createElement("div")
  element.dataset.presenceAnchor = "board"
  document.body.replaceChildren(element)

  const controller = new PresenceController()
  controller.element = element
  controller.streamValue = "signed-stream"
  controller.hasStreamValue = true
  controller.ttlValue = 90000
  controller.cursorsValue = cursors
  controller.connect()

  return controller
}

const announces = () => performed.filter(p => p.action === "announce")
const lastState = () => announces().at(-1)?.data.state

describe("announcing", () => {
  it("waits for the subscription rather than performing on connect", () => {
    const controller = build({ autoConnect: false })

    expect(performed).toHaveLength(0)

    controller.subscriptionConnected()

    expect(announces()).toHaveLength(1)
  })

  it("carries the sharing and watching flags", () => {
    build()

    expect(lastState()).toEqual({ sharing: false, watching: null })
  })
})

describe("learning who you are", () => {
  it("repaints once, not on every repeat of the same identity", () => {
    const controller = build()
    let changes = 0
    controller.element.addEventListener("reactive-presence:changed", () => changes++)

    controller.handleMessage({ action: "presence_self", user: ana })
    controller.handleMessage({ action: "presence_self", user: ana })
    controller.handleMessage({ action: "presence_self", user: ana })

    expect(changes).toBe(1)
    expect(controller.roster.selfId).toBe(ana.id)
  })

  it("keeps a controller that joined late out of its own roster", () => {
    const controller = build()

    // The echo of its own announce, then the identity the server now sends on
    // every announce rather than only on a subscription's first.
    controller.handleMessage({ action: "presence", user: ana, state: {} })
    controller.handleMessage({ action: "presence_self", user: ana })

    expect(controller.roster.others()).toHaveLength(0)
    expect(controller.element.hasAttribute("data-presence-here")).toBe(false)
  })
})

describe("the same person in two tabs", () => {
  it("answers at once when its own user leaves from another tab", () => {
    const controller = build()
    controller.handleMessage({ action: "presence_self", user: ana })
    performed.length = 0

    controller.handleMessage({ action: "presence_leave", user: ana })

    expect(announces()).toHaveLength(1)
  })

  it("only removes somebody else on their leave", () => {
    const controller = build()
    controller.handleMessage({ action: "presence_self", user: ana })
    controller.handleMessage({ action: "presence", user: tom, state: {} })
    performed.length = 0

    controller.handleMessage({ action: "presence_leave", user: tom })

    expect(announces()).toHaveLength(0)
    expect(controller.roster.others()).toHaveLength(0)
  })
})

describe("a component that mounts late", () => {
  it("gets the roster as it stands when it asks", () => {
    const controller = build()
    controller.handleMessage({ action: "presence_self", user: ana })
    controller.handleMessage({ action: "presence", user: tom, state: {} })

    const late = document.createElement("div")
    controller.element.append(late)
    const answers = []
    controller.element.addEventListener("reactive-presence:changed", (e) => answers.push(e.detail.others))

    late.dispatchEvent(new CustomEvent("reactive-presence:request", { bubbles: true }))

    expect(answers).toHaveLength(1)
    expect(answers[0].map(entry => entry.user.id)).toEqual([tom.id])
  })
})

describe("state", () => {
  it("keeps other facts when a field is claimed", () => {
    const controller = build()
    controller.update({ over: "archive" })

    const field = document.createElement("input")
    field.dataset.presenceField = "body"
    controller.claim({ target: field })

    expect(lastState()).toMatchObject({ over: "archive", field: "body" })
  })

  it("releases only the field", () => {
    const controller = build()
    controller.update({ over: "archive" })

    const field = document.createElement("input")
    field.dataset.presenceField = "body"
    controller.claim({ target: field })
    controller.release()

    expect(lastState()).toMatchObject({ over: "archive" })
    expect(lastState().field).toBeUndefined()
  })

  it("drops a key set to null instead of broadcasting it", () => {
    const controller = build()
    controller.update({ over: "archive" })
    controller.update({ over: null })

    expect(lastState().over).toBeUndefined()
  })

  it("says nothing when an update changes nothing", () => {
    const controller = build()
    controller.update({ over: "archive" })
    const before = announces().length
    controller.update({ over: "archive" })

    expect(announces()).toHaveLength(before)
  })
})

describe("following someone", () => {
  it("asks for that user's cursor stream and drops the previous one", () => {
    const controller = build()

    controller.watch({ params: { userId: 2 } })
    controller.watch({ params: { userId: 3 } })

    expect(performed.filter(p => p.action === "watch_cursor").map(p => p.data.user_id)).toEqual([2, 3])
    expect(performed.filter(p => p.action === "unwatch_cursor").map(p => p.data.user_id)).toEqual([2])
  })

  it("follows somebody whose id is a string, not only a number", () => {
    const controller = build()
    const uuid = "7f9c2ba4-e88f-4b3c-9d1a-2c1e5b6a8d40"

    controller.watch({ params: { userId: uuid } })

    expect(controller.watching).toBe(uuid)
    expect(performed.find(p => p.action === "watch_cursor")?.data.user_id).toBe(uuid)
    expect(lastState().watching).toBe(uuid)
  })

  it("re-asks after a reconnect, because the server's channel is new", () => {
    const controller = build()
    controller.watch({ params: { userId: 2 } })
    performed.length = 0

    controller.subscriptionConnected()

    expect(performed.filter(p => p.action === "watch_cursor").map(p => p.data.user_id)).toEqual([2])
  })

  it("takes the ghost down on unfollow, since no frame ever will", () => {
    const controller = build({ cursors: true })
    controller.handleMessage({ action: "presence", user: tom, state: { sharing: true } })
    controller.watch({ params: { userId: tom.id } })
    controller.paintCursor(tom, { a: "board", x: 0.5, y: 0.5 })

    const seen = []
    controller.element.addEventListener("reactive-presence:cursor", (e) => seen.push(e.detail))
    controller.watch({ params: { userId: tom.id } })

    expect(controller.element.querySelector(".reactive-presence-cursor")).toBeNull()
    expect(seen.at(-1).at).toBeNull()
    expect(seen.at(-1).user.id).toBe(tom.id)
  })

  it("takes the old ghost down when switching to somebody else", () => {
    const controller = build({ cursors: true })
    controller.watch({ params: { userId: tom.id } })
    controller.paintCursor(tom, { a: "board", x: 0.5, y: 0.5 })

    controller.watch({ params: { userId: 3 } })

    expect(controller.element.querySelector(".reactive-presence-cursor")).toBeNull()
    expect(controller.watching).toBe(3)
  })

  it("asks for nothing on reconnect when not following anyone", () => {
    const controller = build()
    performed.length = 0

    controller.subscriptionConnected()

    expect(performed.filter(p => p.action === "watch_cursor")).toHaveLength(0)
  })
})

describe("meeting a stranger", () => {
  it("answers so they do not wait out a heartbeat", async () => {
    vi.useFakeTimers()
    const controller = build()
    performed.length = 0

    controller.handleMessage({ action: "presence", user: tom, state: {} })

    expect(announces()).toHaveLength(0)

    await vi.advanceTimersByTimeAsync(600)

    expect(announces()).toHaveLength(1)
    vi.useRealTimers()
  })

  it("answers once for several arrivals at the same moment", async () => {
    vi.useFakeTimers()
    const controller = build()
    performed.length = 0

    controller.handleMessage({ action: "presence", user: tom, state: {} })
    controller.handleMessage({ action: "presence", user: { id: 3, name: "Kim" }, state: {} })

    await vi.advanceTimersByTimeAsync(600)

    expect(announces()).toHaveLength(1)
    vi.useRealTimers()
  })

  it("stays quiet for somebody it already knows", async () => {
    vi.useFakeTimers()
    const controller = build()
    controller.handleMessage({ action: "presence", user: tom, state: {} })
    await vi.advanceTimersByTimeAsync(600)
    performed.length = 0

    controller.handleMessage({ action: "presence", user: tom, state: { field: "body" } })
    await vi.advanceTimersByTimeAsync(600)

    expect(announces()).toHaveLength(0)
    vi.useRealTimers()
  })

  it("does not answer its own echo", async () => {
    vi.useFakeTimers()
    const controller = build()
    controller.handleMessage({ action: "presence_self", user: ana })
    performed.length = 0

    controller.handleMessage({ action: "presence", user: ana, state: {} })
    await vi.advanceTimersByTimeAsync(600)

    expect(announces()).toHaveLength(0)
    vi.useRealTimers()
  })
})

describe("cursor sampling", () => {
  it("installs no listener while nobody is watching", () => {
    const controller = build({ cursors: true })
    controller.shareCursor()

    expect(controller.sampler).toBeFalsy()
  })

  it("installs one once a peer says it is watching", () => {
    const controller = build({ cursors: true })
    controller.shareCursor()
    controller.handleMessage({ action: "presence_self", user: ana })
    controller.handleMessage({ action: "presence", user: tom, state: { watching: ana.id } })

    expect(controller.sampler).toBeTruthy()
  })

  it("removes it again when that peer stops watching", () => {
    const controller = build({ cursors: true })
    controller.shareCursor()
    controller.handleMessage({ action: "presence_self", user: ana })
    controller.handleMessage({ action: "presence", user: tom, state: { watching: ana.id } })
    controller.handleMessage({ action: "presence", user: tom, state: { watching: null } })

    expect(controller.sampler).toBeFalsy()
  })

  it("stays quiet when the component never opted in", () => {
    const controller = build({ cursors: false })
    controller.shareCursor()
    controller.handleMessage({ action: "presence_self", user: ana })
    controller.handleMessage({ action: "presence", user: tom, state: { watching: ana.id } })

    expect(controller.sampler).toBeFalsy()
  })
})

describe("painting", () => {
  beforeEach(() => { performed.length = 0 })

  it("builds a ghost with the class names an app styles", () => {
    const controller = build({ cursors: true })
    controller.paintCursor(tom, { a: "board", x: 0.5, y: 0.5 })

    expect(controller.element.querySelector(".reactive-presence-layer")).toBeTruthy()

    const ghost = controller.element.querySelector(".reactive-presence-cursor")

    expect(ghost).toBeTruthy()
    expect(ghost.dataset.presenceUser).toBe("Tom")
  })

  it("reports each position so an app can hang something off it", () => {
    const controller = build({ cursors: true })
    const seen = []
    controller.element.addEventListener("reactive-presence:cursor", (e) => seen.push(e.detail))

    controller.paintCursor(tom, { a: "board", x: 0.5, y: 0.5 })

    expect(seen).toHaveLength(1)
    expect(seen[0].user).toBe(tom)
    expect(seen[0].at).toBeTruthy()
  })

  it("reports the removal too, so nothing outlives the drag", () => {
    const controller = build({ cursors: true })
    controller.paintCursor(tom, { a: "board", x: 0.5, y: 0.5 })

    const seen = []
    controller.element.addEventListener("reactive-presence:cursor", (e) => seen.push(e.detail))
    controller.paintCursor(tom, null)

    expect(controller.element.querySelector(".reactive-presence-cursor")).toBeNull()
    expect(seen.at(-1).at).toBeNull()
  })

  it("takes down the cursor of a viewer who expired", () => {
    vi.useFakeTimers()
    const controller = build({ cursors: true })
    controller.handleMessage({ action: "presence_self", user: ana })
    controller.handleMessage({ action: "presence", user: tom, state: { sharing: true } })
    controller.paintCursor(tom, { a: "board", x: 0.5, y: 0.5 })

    // A crashed tab sends no leave and no final null frame; only expiry is left.
    vi.advanceTimersByTime(controller.ttlValue + 2000)

    expect(controller.roster.others()).toHaveLength(0)
    expect(controller.element.querySelector(".reactive-presence-cursor")).toBeNull()
    vi.useRealTimers()
  })

  it("clears every ghost when the connection drops", () => {
    const controller = build({ cursors: true })
    controller.paintCursor(tom, { a: "board", x: 0.5, y: 0.5 })

    const seen = []
    controller.element.addEventListener("reactive-presence:cursor", (e) => seen.push(e.detail))
    controller.subscriptionDisconnected()

    expect(controller.element.querySelector(".reactive-presence-cursor")).toBeNull()
    expect(seen.at(-1).user).toBeNull()
  })

  it("skips a frame whose anchor is not on this page", () => {
    const controller = build({ cursors: true })
    controller.paintCursor(tom, { a: "somewhere_else", x: 0.5, y: 0.5 })

    // The ghost exists but was never positioned, so nothing is drawn at 0,0
    // pretending to be a real pointer.
    expect(controller.element.querySelector(".reactive-presence-cursor").style.transform).toBe("")
  })
})

describe("the roster in the DOM", () => {
  it("marks the element and the field a peer holds", () => {
    const controller = build()
    const field = document.createElement("input")
    field.dataset.presenceField = "body"
    controller.element.append(field)

    controller.handleMessage({ action: "presence_self", user: ana })
    controller.handleMessage({ action: "presence", user: tom, state: { field: "body" } })

    expect(controller.element.hasAttribute("data-presence-here")).toBe(true)
    expect(field.getAttribute("data-presence-busy")).toBe("Tom")
  })

  it("never marks a field against the viewer holding it themselves", () => {
    const controller = build()
    const field = document.createElement("input")
    field.dataset.presenceField = "body"
    controller.element.append(field)

    controller.handleMessage({ action: "presence_self", user: ana })
    controller.handleMessage({ action: "presence", user: ana, state: { field: "body" } })

    expect(field.hasAttribute("data-presence-busy")).toBe(false)
    expect(controller.element.hasAttribute("data-presence-here")).toBe(false)
  })

  it("clears the marker when that peer leaves", () => {
    const controller = build()
    const field = document.createElement("input")
    field.dataset.presenceField = "body"
    controller.element.append(field)

    controller.handleMessage({ action: "presence_self", user: ana })
    controller.handleMessage({ action: "presence", user: tom, state: { field: "body" } })
    controller.handleMessage({ action: "presence_leave", user: tom })

    expect(field.hasAttribute("data-presence-busy")).toBe(false)
  })
})
