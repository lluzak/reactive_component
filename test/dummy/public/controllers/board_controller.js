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
    this.clearHints()
  }

  over(event) {
    event.preventDefault()
    event.currentTarget.classList.add("ring-2", "ring-blue-400")
  }

  leave(event) {
    event.currentTarget.classList.remove("ring-2", "ring-blue-400")
  }

  drop(event) {
    event.preventDefault()
    this.clearHints()

    const label = event.currentTarget.dataset.column
    const id = this.draggingId || event.dataTransfer.getData("text/plain")
    const shell = this.element.querySelector(`[data-card-id="${id}"]`)
    if (!shell || !label) return

    // Move it locally first so the drag feels immediate. The broadcast will
    // land every other browser in the same place a moment later.
    event.currentTarget.querySelector("[data-cards]").append(shell)

    const card = shell.querySelector('[data-controller~="reactive-renderer"]')
    const renderer = this.application.getControllerForElementAndIdentifier(card, "reactive-renderer")
    renderer?.performAction({
      type: "drop",
      preventDefault() {},
      stopPropagation() {},
      params: { action: "move", label }
    })
  }

  // A card that moved in somebody else's browser arrives here as an ordinary
  // component update, so the board just reads where it belongs now.
  relocate(event) {
    const shell = event.target.closest(".card-shell")
    const label = shell?.querySelector("[data-label]")?.dataset.label
    if (!label) return

    const cards = this.element.querySelector(`[data-column="${label}"] [data-cards]`)
    if (!cards || shell.parentElement === cards) return

    // Measure, move, then play the gap back as a transform, so somebody else's
    // move reads as the card travelling rather than teleporting between columns.
    const from = shell.getBoundingClientRect()
    cards.append(shell)
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

  clearHints() {
    for (const column of this.element.querySelectorAll("[data-column]")) {
      column.classList.remove("ring-2", "ring-blue-400")
    }
  }
}
