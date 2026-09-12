import { Controller } from "@hotwired/stimulus"

// Drag and drop for the demo board. The move itself is an ordinary
// live_action on the card component, so every other browser learns about it
// through the broadcast the gem already sends.
export default class extends Controller {
  pick(event) {
    // Presence prevents the collision rather than resolving it: a card somebody
    // else has hold of simply will not start a drag here.
    if (event.currentTarget.hasAttribute("data-presence-busy")) {
      event.preventDefault()
      return
    }

    this.draggingId = event.currentTarget.dataset.cardId
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggingId)
    // The browser draws its own drag image; the card left behind should read
    // as the slot being vacated, not as a second copy.
    event.currentTarget.classList.add("opacity-40")
  }

  drophint() {
    this.element.querySelector(`[data-card-id="${this.draggingId}"]`)?.classList.remove("opacity-40")
    this.draggingId = null
    this.announcedOver = null
    this.announcedAfter = null
    this.mySlot().remove()   // a cancelled drag never reaches drop()
    this.presence?.update({ over: null, after: null })
    this.clearHints()
  }

  over(event) {
    event.preventDefault()
    const column = event.currentTarget
    column.classList.add("ring-2", "ring-blue-400")

    // Where the card would land if released right now — the same computation
    // drop() makes, so the slot never lies.
    const dragged = this.draggingId && this.element.querySelector(`[data-card-id="${this.draggingId}"]`)
    const cards = column.querySelector("[data-cards]")
    const after = dragged ? this.cardAbove(cards, dragged, event.clientY) : null
    this.placeSlot(this.mySlot(), cards, after)

    // Announced only when the slot moves: dragover fires continuously, and this
    // rides the roster stream. Bounded by the number of cards, not by the mouse.
    const label = column.dataset.column
    const afterId = after ? after.dataset.cardId : "top"
    if (this.announcedOver === label && this.announcedAfter === afterId) return

    this.announcedOver = label
    this.announcedAfter = afterId
    this.presence?.update({ over: label, after: afterId })
  }

  leave(event) {
    // dragleave also fires when the pointer crosses into a child; only a real
    // exit should clear anything, or the slot flickers on every card boundary.
    if (event.currentTarget.contains(event.relatedTarget)) return

    event.currentTarget.classList.remove("ring-2", "ring-blue-400")
    this.mySlot().remove()
  }

  mySlot() {
    this.slot ||= Object.assign(document.createElement("div"), { className: "drop-slot drop-slot--mine" })
    return this.slot
  }

  placeSlot(slot, cards, after) {
    if (after) {
      if (slot.previousElementSibling !== after) after.after(slot)
    } else if (cards.firstElementChild !== slot) {
      cards.prepend(slot)
    }
  }

  drop(event) {
    event.preventDefault()
    this.clearHints()
    this.mySlot().remove()
    this.announcedOver = null
    this.announcedAfter = null
    this.presence?.update({ over: null, after: null })

    const label = event.currentTarget.dataset.column
    const id = this.draggingId || event.dataTransfer.getData("text/plain")
    const shell = this.element.querySelector(`[data-card-id="${id}"]`)
    if (!shell || !label) return

    const cards = event.currentTarget.querySelector("[data-cards]")
    const after = this.cardAbove(cards, shell, event.clientY)

    // Move it locally first so the drag feels immediate. The broadcast will
    // land every other browser in the same place a moment later.
    after ? after.after(shell) : cards.prepend(shell)

    const card = shell.querySelector('[data-controller~="reactive-renderer"]')
    const renderer = this.application.getControllerForElementAndIdentifier(card, "reactive-renderer")
    renderer?.performAction({
      type: "drop",
      preventDefault() {},
      stopPropagation() {},
      params: { action: "move", label, after: after ? this.messageId(after) : "" }
    })
  }

  // The card the pointer is below, which is the one the drop should land after.
  cardAbove(cards, dragged, clientY) {
    let above = null

    for (const shell of cards.querySelectorAll(".card-shell")) {
      if (shell === dragged) continue
      const rect = shell.getBoundingClientRect()
      if (clientY > rect.top + rect.height / 2) above = shell
    }

    return above
  }

  messageId(shell) {
    return shell.dataset.cardId.replace("card_message_", "")
  }

  // A card that moved in somebody else's browser arrives here as an ordinary
  // component update, so the board just reads where it belongs now.
  relocate(event) {
    const shell = event.target.closest(".card-shell")
    const label = shell?.querySelector("[data-label]")?.dataset.label
    if (!label) return

    const cards = this.element.querySelector(`[data-column="${label}"] [data-cards]`)
    if (!cards) return

    // Measure, move, then play the gap back as a transform, so somebody else's
    // move reads as the card travelling rather than teleporting between columns.
    const from = shell.getBoundingClientRect()
    this.insertInOrder(cards, shell)
    const to = shell.getBoundingClientRect()

    const dx = from.left - to.left
    const dy = from.top - to.top
    if ((!dx && !dy) || matchMedia("(prefers-reduced-motion: reduce)").matches) return

    shell.animate(
      [{ transform: `translate(${dx}px, ${dy}px)`, boxShadow: "0 8px 20px -6px rgba(0,0,0,.45)" },
       { transform: "none", boxShadow: "none" }],
      { duration: 280, easing: "cubic-bezier(.2,.7,.3,1)" }
    )
  }

  // Somebody you follow is dragging: carry a copy of their card along with
  // their cursor, so you watch the move happen rather than only its result.
  trackDrag(event) {
    const { user, at, layer } = event.detail
    this.previews ||= new Map()

    // A cleared event names nobody: the connection dropped, so nothing on
    // screen can be trusted.
    if (!user) {
      for (const [id, preview] of this.previews) {
        preview.remove()
        this.previews.delete(id)
      }
      this.element.querySelectorAll('[data-lifted="true"]')
        .forEach(shell => delete shell.dataset.lifted)
      return
    }

    const held = at && this.heldBy(user.name)
    let preview = this.previews.get(user.id)

    if (!held) {
      preview?.remove()
      this.previews.delete(user.id)
      this.element.querySelectorAll('[data-lifted="true"]')
        .forEach(shell => delete shell.dataset.lifted)
      return
    }

    if (!preview) {
      // The card body, not the shell: the shell also holds the compiled
      // template script the gem emits alongside the component.
      preview = held.querySelector("[data-label]").cloneNode(true)
      preview.className = "drag-preview " + preview.className
      preview.style.width = `${held.getBoundingClientRect().width}px`
      layer.append(preview)
      this.previews.set(user.id, preview)
    }

    preview.style.transform = `translate3d(${at.x + 12}px, ${at.y + 12}px, 0)`

    // The source slot empties while the copy is in flight, so the card looks
    // picked up rather than duplicated.
    held.dataset.lifted = "true"
  }

  // Where everybody else is about to drop. Column granularity, so it costs one
  // frame per change of mind rather than one per mouse move.
  showTargets(event) {
    // A drop clears the hold before the next cursor frame arrives, and the
    // mouse may not move again. Drop any preview whose card is no longer held.
    for (const [id, preview] of this.previews ?? []) {
      const entry = event.detail.others.find(other => other.user.id === id)
      if (entry && this.heldBy(entry.user.name)) continue

      preview.remove()
      this.previews.delete(id)
    }
    this.element.querySelectorAll('[data-lifted="true"]').forEach(shell => {
      if (!shell.hasAttribute("data-presence-busy")) delete shell.dataset.lifted
    })

    const incoming = new Map()
    for (const entry of event.detail.others) {
      if (entry.state.over) incoming.set(entry.state.over, entry.user.name)
    }

    for (const column of this.element.querySelectorAll("[data-column]")) {
      const name = incoming.get(column.dataset.column)
      if (name) column.setAttribute("data-incoming", name)
      else column.removeAttribute("data-incoming")
    }

    // The exact slot each of them would drop into, in this page's own order.
    this.theirSlots ||= new Map()
    const active = new Set()

    for (const entry of event.detail.others) {
      const { over, after } = entry.state
      if (!over) continue
      const cards = this.element.querySelector(`[data-column="${over}"] [data-cards]`)
      if (!cards) continue
      const anchor = after && after !== "top" ? cards.querySelector(`[data-card-id="${after}"]`) : null
      if (after && after !== "top" && !anchor) continue   // not on this page yet: skip, don't guess

      let slot = this.theirSlots.get(entry.user.id)
      if (!slot) {
        slot = Object.assign(document.createElement("div"), { className: "drop-slot drop-slot--theirs" })
        this.theirSlots.set(entry.user.id, slot)
      }
      slot.dataset.by = entry.user.name
      this.placeSlot(slot, cards, anchor)
      active.add(entry.user.id)
    }

    for (const [id, slot] of this.theirSlots) {
      if (active.has(id)) continue
      slot.remove()
      this.theirSlots.delete(id)
    }
  }

  get presence() {
    return this.application.getControllerForElementAndIdentifier(this.element, "presence")
  }

  // Somebody else's reorder arrives as a component update carrying the new
  // position, so the board puts the card where that position says.
  insertInOrder(cards, shell) {
    const position = Number(shell.querySelector("[data-position]")?.dataset.position ?? 0)
    const later = [...cards.querySelectorAll(".card-shell")]
      .find(other => other !== shell && this.positionOf(other) > position)

    later ? later.before(shell) : cards.append(shell)
  }

  positionOf(shell) {
    return Number(shell.querySelector("[data-position]")?.dataset.position ?? 0)
  }

  heldBy(name) {
    return [...this.element.querySelectorAll(".card-shell[data-presence-busy]")]
      .find(shell => shell.getAttribute("data-presence-busy").split(", ").includes(name))
  }

  clearHints() {
    for (const column of this.element.querySelectorAll("[data-column]")) {
      column.classList.remove("ring-2", "ring-blue-400")
    }
  }
}
