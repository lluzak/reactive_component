import { Controller } from "@hotwired/stimulus"
import { subscribe, unsubscribe, findSubscription } from "reactive_component/lib/cable_subscriptions"
import { PresenceRoster } from "reactive_component/lib/presence_roster"

const HEARTBEAT = 10000
const SWEEP = 1000

export default class extends Controller {
  static values = {
    stream: String,
    ttl: { type: Number, default: 30000 }
  }

  connect() {
    if (!this.hasStreamValue) return

    this.roster = new PresenceRoster({ ttl: this.ttlValue })
    this.state = {}
    this.sharing = false
    this.watching = null

    subscribe(this.streamValue, this)

    // ponytail: no join handshake — a newcomer's roster fills within one
    // heartbeat instead of every peer re-announcing at once on every arrival.
    // Announce traffic is O(n^2) per stream; past roughly 50 concurrent
    // viewers this wants a Redis-backed roster on the server.
    this.beat = setInterval(() => this.announce(), HEARTBEAT)
    this.sweep = setInterval(() => { if (this.roster.expire()) this.changed() }, SWEEP)
  }

  disconnect() {
    clearInterval(this.beat)
    clearInterval(this.sweep)
    if (this.hasStreamValue) unsubscribe(this.streamValue, this)
  }

  // Announcing on connect rather than in connect(): a perform before the
  // subscription is confirmed is dropped on the floor.
  subscriptionConnected() {
    this.announce()
  }

  subscriptionDisconnected() {}

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
        if (this.roster.remove(message.user.id)) this.changed()
        break
    }
    // Anything else on this stream belongs to the renderer, whose routeMessage
    // already returns "ignore" for actions it does not know.
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
    this.state = { field: event.target.dataset.presenceField }
    this.announce()
  }

  release() {
    this.state = {}
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
  }
}
