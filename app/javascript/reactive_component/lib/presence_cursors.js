// Cursor geometry and rate control. No DOM queries beyond the elements handed
// in and no cable import, so this is unit testable.

// A point is a fraction of a named anchor, never a page pixel. The receiver
// multiplies back through its OWN rect, so a different viewport width, a scroll
// offset or a reflowed sidebar all still land the ghost on the element the
// sender was pointing at.
export function toAnchorPoint(event, anchor) {
  const rect = anchor.getBoundingClientRect()
  if (!rect.width || !rect.height) return null

  return {
    a: anchor.dataset.presenceAnchor,
    x: round((event.clientX - rect.left) / rect.width),
    y: round((event.clientY - rect.top) / rect.height)
  }
}

export function fromAnchorPoint(point, anchor, layer) {
  const rect = anchor.getBoundingClientRect()
  const base = layer.getBoundingClientRect()

  return {
    x: rect.left - base.left + point.x * rect.width,
    y: rect.top - base.top + point.y * rect.height
  }
}

// An anchor that is not on this page means the sender is looking at something
// this viewer cannot see. Skip the frame rather than guessing at a position.
// Compared rather than interpolated into a selector: the name arrives over the
// wire, and this way it cannot break out of one.
export function findAnchor(root, name) {
  if (root.dataset.presenceAnchor === name) return root

  for (const element of root.querySelectorAll("[data-presence-anchor]")) {
    if (element.dataset.presenceAnchor === name) return element
  }

  return null
}

// The throttle IS the batch. Coalescing to the newest point beats shipping an
// array of them: every older point is garbage the moment a newer one exists, so
// batching would spend bytes to draw one dot.
export function coalesce(send, { every = 50, deadband = 0.004 } = {}) {
  let pending = null
  let timer = null
  let last = null

  return (point) => {
    pending = point
    if (timer) return

    timer = setTimeout(() => {
      timer = null
      const next = pending
      pending = null
      if (!next) return
      if (last && within(last, next, deadband)) return

      last = next
      send(next)
    }, every)
  }
}

function within(a, b, deadband) {
  return Math.abs(a.x - b.x) < deadband && Math.abs(a.y - b.y) < deadband
}

function round(value) {
  return Math.round(value * 1000) / 1000
}
