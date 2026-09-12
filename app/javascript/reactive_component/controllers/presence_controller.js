import { Controller } from "@hotwired/stimulus"
import { subscribe, unsubscribe, findSubscription } from "reactive_component/lib/cable_subscriptions"
import { PresenceRoster, sameState } from "reactive_component/lib/presence_roster"
import { toAnchorPoint, fromAnchorPoint, findAnchor, coalesce } from "reactive_component/lib/presence_cursors"

const HEARTBEAT = 10000
const SWEEP = 1000

// Browsers throttle timers in a hidden tab to roughly once a minute, so a
// heartbeat from a backgrounded viewer can be a minute late. The expiry has to
// sit well clear of that, or switching tabs drops you out of everyone's roster
// and takes your cursor with you. A clean disconnect still broadcasts a leave,
// so this only governs the crashed-tab case.
const TTL = 90000

export default class extends Controller {
  static values = {
    stream: String,
    ttl: { type: Number, default: TTL },
    cursors: { type: Boolean, default: false }
  }

  connect() {
    if (!this.hasStreamValue) return

    this.roster = new PresenceRoster({ ttl: this.ttlValue })
    this.state = {}
    this.sharing = false
    this.watching = null
    this.ghosts = new Map()
    this.queued = new Map()

    subscribe(this.streamValue, this)

    // ponytail: no join handshake — a newcomer's roster fills within one
    // heartbeat instead of every peer re-announcing at once on every arrival.
    // Announce traffic is O(n^2) per stream; past roughly 50 concurrent
    // viewers this wants a Redis-backed roster on the server.
    this.beat = setInterval(() => this.announce(), HEARTBEAT)
    this.sweep = setInterval(() => this.expire(), SWEEP)

    // A tab coming back to the foreground has been quiet for as long as the
    // browser throttled it. Announce at once rather than waiting out a beat.
    this.onVisible = () => { if (!document.hidden) this.announce() }
    document.addEventListener("visibilitychange", this.onVisible)

    // A component that mounts later asks for the roster as it stands.
    this.onRequest = () => this.changed()
    this.element.addEventListener("reactive-presence:request", this.onRequest)
  }

  disconnect() {
    clearInterval(this.beat)
    clearInterval(this.sweep)
    document.removeEventListener("visibilitychange", this.onVisible)
    this.element.removeEventListener("reactive-presence:request", this.onRequest)
    this.stopSampling()
    if (this.hasStreamValue) unsubscribe(this.streamValue, this)
  }

  // Announcing on connect rather than in connect(): a perform before the
  // subscription is confirmed is dropped on the floor.
  subscriptionConnected() {
    this.announce()

    // A reconnect builds a new channel on the server, and that channel streams
    // only what `subscribed` verified. A cursor watch has to be asked for
    // again or it is silently gone while this side still believes it is
    // following — which is what a dropped connection looks like from here.
    if (this.watching != null) {
      findSubscription(this.streamValue)?.perform("watch_cursor", { user_id: this.watching })
    }
  }

  // Whatever was on screen is now stale, and a frozen cursor reads as a live
  // one. Clear them rather than leaving somebody's pointer parked mid-page.
  subscriptionDisconnected() {
    for (const [id, ghost] of this.ghosts) {
      ghost.remove()
      this.ghosts.delete(id)
    }
    this.announceCursorsCleared()
  }

  announceCursorsCleared() {
    this.element.dispatchEvent(new CustomEvent("reactive-presence:cursor", {
      bubbles: true,
      detail: { user: null, point: null, at: null, layer: this.cursorLayer ?? null }
    }))
  }

  handleMessage(message) {
    switch (message.action) {
      case "presence_self":
        // Arrives on every announce; only a change of identity is news.
        if (this.roster.selfId === message.user.id) break
        this.roster.selfId = message.user.id
        this.changed()
        break

      case "presence":
        if (this.roster.apply(message.user, message.state)) this.changed()
        break

      case "presence_leave":
        // A leave is per connection but a roster is per user, so the same
        // person closing another tab drops them for everyone. This tab is proof
        // they are still here: say so straight away. Directly, not via greet,
        // because a hidden tab's timers can run a minute late.
        if (message.user.id === this.roster.selfId) {
          this.announce()
          break
        }
        this.paintCursor(message.user, null)
        if (this.roster.remove(message.user.id)) this.changed()
        break

      case "cursor":
        this.queueCursor(message.user, message.cursor)
        break
    }
    // Anything else on this stream belongs to the renderer, whose routeMessage
    // already returns "ignore" for actions it does not know.
  }

  // A viewer who went silent takes their cursor with them. Expiry is the
  // crashed-tab case, where no leave and no final null frame will ever come, so
  // nothing else would clear it.
  expire() {
    if (!this.roster.expire()) return

    for (const id of [...this.ghosts.keys()]) {
      if (!this.roster.entries.has(id)) this.paintCursor({ id }, null)
    }
    this.changed()
  }

  announce() {
    findSubscription(this.streamValue)?.perform("announce", {
      state: { ...this.state, sharing: this.sharing, watching: this.watching }
    })
  }

  // Both halves of the cursor opt-in ride the roster, so every peer can see who
  // is broadcasting and who is being watched. That second fact is what lets a
  // sharer stop sampling the mouse when nobody is looking.
  shareCursor() {
    this.sharing = true
    this.announce()
  }

  stopSharingCursor() {
    this.sharing = false
    this.announce()
  }

  watch(event) {
    // As given, never coerced: Stimulus already turns a numeric param into a
    // number, and an id that is a UUID or any other string has to stay one or
    // it becomes NaN and silently matches nobody.
    const userId = event.params.userId
    const subscription = findSubscription(this.streamValue)

    if (this.watching != null) subscription?.perform("unwatch_cursor", { user_id: this.watching })

    this.watching = this.watching === userId ? null : userId

    if (this.watching != null) subscription?.perform("watch_cursor", { user_id: this.watching })

    this.announce()
  }

  claim(event) {
    this.state = { ...this.state, field: event.target.dataset.presenceField }
    this.announce()
  }

  release() {
    const { field, ...rest } = this.state
    this.state = rest
    this.announce()
  }

  // Anything else an app wants every viewer to know. `claim` and `release` own
  // the focused field and leave the rest of the state alone, so the two do not
  // fight over it. A key set to null is dropped rather than broadcast.
  update(patch) {
    const next = { ...this.state, ...patch }
    for (const [key, value] of Object.entries(next)) {
      if (value === null || value === undefined) delete next[key]
    }

    if (sameState(this.state, next)) return

    this.state = next
    this.announce()
  }

  // Attributes only: this never re-renders anything and never touches the morph
  // path. What any of it looks like is the host app's CSS to decide.
  changed() {
    const others = this.roster.others()

    this.element.toggleAttribute("data-presence-here", others.length > 0)

    for (const field of this.element.querySelectorAll("[data-presence-field]")) {
      const names = others
        .filter(entry => entry.state.field === field.dataset.presenceField)
        .map(entry => entry.user.name)

      if (names.length) field.setAttribute("data-presence-busy", names.join(", "))
      else field.removeAttribute("data-presence-busy")
    }

    this.element.dispatchEvent(new CustomEvent("reactive-presence:changed", {
      bubbles: true,
      detail: { others }
    }))

    this.syncSampling()
  }

  // Two gates before a mousemove is even measured: this viewer opted in, and
  // somebody actually asked to watch them. Nobody watching means no listener.
  syncSampling() {
    const wanted = this.cursorsValue && this.sharing && this.roster.watchedBy(this.roster.selfId)
    if (wanted === !!this.sampler) return

    wanted ? this.startSampling() : this.stopSampling()
  }

  startSampling() {
    const anchor = this.element.querySelector("[data-presence-anchor]") || this.element
    const send = coalesce(point =>
      findSubscription(this.streamValue)?.perform("cursor", { cursor: point }))

    this.sampler = (event) => {
      const point = toAnchorPoint(event, anchor)
      if (point) send(point)
    }

    this.element.addEventListener("mousemove", this.sampler)
  }

  stopSampling() {
    if (!this.sampler) return

    this.element.removeEventListener("mousemove", this.sampler)
    this.sampler = null
    findSubscription(this.streamValue)?.perform("cursor", { cursor: null })
  }

  // Watching several people means several frames a tick. Paint once.
  queueCursor(user, point) {
    this.queued.set(user.id, { user, point })
    if (this.frame) return

    this.frame = requestAnimationFrame(() => {
      this.frame = null
      for (const entry of this.queued.values()) this.paintCursor(entry.user, entry.point)
      this.queued.clear()
    })
  }

  // Ghosts live in an overlay outside any reactive wrapper and move by
  // transform alone, so 20 Hz never reaches a component's DOM.
  paintCursor(user, point) {
    let ghost = this.ghosts.get(user.id)

    if (!point) {
      ghost?.remove()
      this.ghosts.delete(user.id)
      this.announceCursor(user, null, null)
      return
    }

    if (!ghost) {
      ghost = document.createElement("div")
      ghost.className = "reactive-presence-cursor"
      ghost.dataset.presenceUser = user.name
      if (user.color) ghost.style.setProperty("--presence-color", user.color)
      this.layer().append(ghost)
      this.ghosts.set(user.id, ghost)
    }

    const anchor = findAnchor(this.element, point.a)
    if (!anchor) return

    const at = fromAnchorPoint(point, anchor, this.layer())
    ghost.style.transform = `translate3d(${at.x}px, ${at.y}px, 0)`
    this.announceCursor(user, point, at)
  }

  // Where somebody else's pointer is, in this page's own coordinates. Enough
  // for an app to hang something off it — a drag preview, a viewport follow —
  // without repeating the anchor arithmetic.
  announceCursor(user, point, at) {
    this.element.dispatchEvent(new CustomEvent("reactive-presence:cursor", {
      bubbles: true,
      detail: { user, point, at, layer: this.layer() }
    }))
  }

  layer() {
    if (this.cursorLayer?.isConnected) return this.cursorLayer

    this.cursorLayer = document.createElement("div")
    this.cursorLayer.className = "reactive-presence-layer"
    this.element.append(this.cursorLayer)

    return this.cursorLayer
  }
}
