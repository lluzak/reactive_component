import { describe, it, expect, vi, afterEach } from "vitest"
import { PresenceRoster } from "reactive_component/lib/presence_roster"

const ana = { id: 1, name: "Ana" }
const tom = { id: 2, name: "Tom" }

afterEach(() => vi.useRealTimers())

describe("apply", () => {
  it("reports a change for a viewer it has not seen", () => {
    const roster = new PresenceRoster()

    expect(roster.apply(ana, { field: "body" })).toBe(true)
  })

  it("reports no change when a heartbeat repeats the same state", () => {
    const roster = new PresenceRoster()
    roster.apply(ana, { field: "body" })

    expect(roster.apply(ana, { field: "body" })).toBe(false)
  })

  it("reports a change when a key is added", () => {
    const roster = new PresenceRoster()
    roster.apply(ana, { field: "body" })

    expect(roster.apply(ana, { field: "body", sharing: true })).toBe(true)
  })

  it("reports a change when a key is removed", () => {
    const roster = new PresenceRoster()
    roster.apply(ana, { field: "body" })

    expect(roster.apply(ana, {})).toBe(true)
  })

  it("replaces the entry rather than accumulating", () => {
    const roster = new PresenceRoster()
    roster.apply(ana, { field: "subject" })
    roster.apply(ana, { field: "body" })

    expect(roster.others()).toHaveLength(1)
    expect(roster.others()[0].state).toEqual({ field: "body" })
  })
})

describe("remove", () => {
  it("drops the viewer and says so", () => {
    const roster = new PresenceRoster()
    roster.apply(ana, {})

    expect(roster.remove(ana.id)).toBe(true)
    expect(roster.others()).toHaveLength(0)
  })

  it("says nothing changed for a viewer it never had", () => {
    expect(new PresenceRoster().remove(ana.id)).toBe(false)
  })
})

describe("expire", () => {
  it("drops a viewer that has been silent longer than the ttl", () => {
    vi.useFakeTimers()
    const roster = new PresenceRoster({ ttl: 30000 })
    roster.apply(ana, {})

    vi.advanceTimersByTime(30001)

    expect(roster.expire()).toBe(true)
    expect(roster.others()).toHaveLength(0)
  })

  it("keeps a viewer that heartbeated inside the ttl", () => {
    vi.useFakeTimers()
    const roster = new PresenceRoster({ ttl: 30000 })
    roster.apply(ana, {})

    vi.advanceTimersByTime(20000)
    roster.apply(ana, {})
    vi.advanceTimersByTime(20000)

    expect(roster.expire()).toBe(false)
    expect(roster.others()).toHaveLength(1)
  })

  it("reports nothing when there is nothing to drop", () => {
    expect(new PresenceRoster().expire()).toBe(false)
  })
})

describe("others", () => {
  it("excludes this viewer once the server has named them", () => {
    const roster = new PresenceRoster()
    roster.apply(ana, {})
    roster.apply(tom, {})

    expect(roster.others()).toHaveLength(2)

    roster.selfId = ana.id

    expect(roster.others().map(entry => entry.user.id)).toEqual([tom.id])
  })
})

describe("watchedBy", () => {
  it("is false when nobody named this viewer", () => {
    const roster = new PresenceRoster()
    roster.selfId = ana.id
    roster.apply(tom, { watching: null })

    expect(roster.watchedBy(ana.id)).toBe(false)
  })

  it("is true once somebody names this viewer", () => {
    const roster = new PresenceRoster()
    roster.selfId = ana.id
    roster.apply(tom, { watching: ana.id })

    expect(roster.watchedBy(ana.id)).toBe(true)
  })

  it("ignores this viewer watching themselves", () => {
    const roster = new PresenceRoster()
    roster.selfId = ana.id
    roster.apply(ana, { watching: ana.id })

    expect(roster.watchedBy(ana.id)).toBe(false)
  })
})
