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
  }

  drophint() {
    this.draggingId = null
    this.announcedOver = null
    this.presence?.update({ over: null })
    this.clearHints()
  }

  over(event) {
    event.preventDefault()
    event.currentTarget.classList.add("ring-2", "ring-blue-400")

    // Only when the target actually changes: dragover fires continuously, and
    // this goes out on the roster stream, not the cursor one.
    const label = event.currentTarget.dataset.column
    if (this.announcedOver === label) return

    this.announcedOver = label
    this.presence?.update({ over: label })
  }

  leave(event) {
    event.currentTarget.classList.remove("ring-2", "ring-blue-400")
  }

  drop(event) {
    event.preventDefault()
    this.clearHints()
    this.announcedOver = null
    this.presence?.update({ over: null })

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

    const position = Number(shell.querySelector("[data-position]")?.dataset.position ?? 0)
    if (shell.parentElement === cards && this.positionOf(shell) === position) return

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
      return
    }

    const held = at && this.heldBy(user.name)
    let preview = this.previews.get(user.id)

    if (!held) {
      preview?.remove()
      this.previews.delete(user.id)
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
  }

  // Where everybody else is about to drop. Column granularity, so it costs one
  // frame per change of mind rather than one per mouse move.
  showTargets(event) {
    const incoming = new Map()
    for (const entry of event.detail.others) {
      if (entry.state.over) incoming.set(entry.state.over, entry.user.name)
    }

    for (const column of this.element.querySelectorAll("[data-column]")) {
      const name = incoming.get(column.dataset.column)
      if (name) column.setAttribute("data-incoming", name)
      else column.removeAttribute("data-incoming")
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
