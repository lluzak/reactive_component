// Who is on the stream and what they said they were doing.
//
// No DOM and no cable import, deliberately: @rails/actioncable is a peer
// dependency and is not installed, so anything that imports it is invisible to
// the unit tests. Keeping this module pure is what makes the roster testable.
export class PresenceRoster {
  constructor({ ttl = 30000 } = {}) {
    this.ttl = ttl
    this.selfId = null
    this.entries = new Map()
  }

  // True when something a renderer would care about changed, so a heartbeat
  // repeating the same state wakes nothing up.
  apply(user, state = {}) {
    const previous = this.entries.get(user.id)
    this.entries.set(user.id, { user, state, lastSeen: Date.now() })

    return !previous || !sameState(previous.state, state)
  }

  remove(userId) {
    return this.entries.delete(userId)
  }

  // The real recovery path. A crashed tab, a closed laptop and a dead cable
  // worker look identical from here and all resolve the same way. lastSeen is
  // stamped on receipt, never read off the frame, so expiry never depends on
  // two machines agreeing about the time.
  expire(now = Date.now()) {
    let dropped = false

    for (const [id, entry] of this.entries) {
      if (now - entry.lastSeen > this.ttl) {
        this.entries.delete(id)
        dropped = true
      }
    }

    return dropped
  }

  others() {
    return [...this.entries.values()].filter(entry => entry.user.id !== this.selfId)
  }

  // A watch is announced like any other state, so the person being watched can
  // read it straight off the roster. No watchers means no reason to sample.
  watchedBy(userId) {
    return this.others().some(entry => entry.state.watching === userId)
  }
}

function sameState(a = {}, b = {}) {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)])

  for (const key of keys) {
    if (a[key] !== b[key]) return false
  }

  return true
}
