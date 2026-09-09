import { Controller } from "@hotwired/stimulus"
import { compileTemplate, morphElement, buildActionBody, routeMessage, duplicateIds, strictData } from "reactive_component/lib/reactive_renderer_utils"
import { findSubscription, subscribe, unsubscribe } from "reactive_component/lib/cable_subscriptions"

export default class extends Controller {
  static values = {
    template: String,
    templateId: String,
    stream: String,
    actionUrl: String,
    actionToken: String,
    state: { type: Object, default: {} },
    data: { type: Object, default: {} },
    strategy: { type: String, default: "push" },
    component: { type: String, default: "" },
    sgid: { type: String, default: "" },
    params: { type: Object, default: {} },
    fieldMap: { type: Object, default: {} },
    skipOwnBroadcasts: { type: Boolean, default: false }
  }

  connect() {
    const clashes = duplicateIds(document, this.element)
    if (clashes.length) {
      console.error(
        `[reactive-renderer] ${clashes.length + 1} components share id "${this.element.id}" — ` +
        "each will render every other's broadcast. Give the component a distinct dom_id_prefix.",
        this.element, ...clashes
      )
    }

    this.clientState = { ...this.stateValue }
    this.lastServerData = Object.keys(this.dataValue).length > 0 ? this.dataValue : null

    const encoded = this.resolveTemplate()
    this.renderFn = encoded ? compileTemplate(encoded) : null

    if (!this.renderFn) {
      if (!this.streamValue) return
    }

    if (!this.streamValue) return

    subscribe(this.streamValue, this)
  }

  disconnect() {
    if (this.streamValue) {
      unsubscribe(this.streamValue, this)
    }
  }

  subscriptionConnected() {
    this.element.setAttribute("data-reactive-renderer-connected", "")
  }

  subscriptionDisconnected() {
    this.element.removeAttribute("data-reactive-renderer-connected")
  }

  // ReactiveComponent.debug marks the wrapper, so the gem is quiet unless the
  // app turns debugging on server-side.
  log(...args) {
    if (this.element.hasAttribute("data-reactive-debug")) {
      console.log("[reactive-renderer]", ...args)
    }
  }

  resolveTemplate() {
    if (this.hasTemplateValue) return this.templateValue

    if (this.hasTemplateIdValue) {
      const el = document.getElementById(this.templateIdValue)
      if (el) return el.textContent
    }

    return null
  }

  handleMessage(message) {
    const route = routeMessage(message, this.element.id, this.strategyValue, this.ownRequestIds)

    switch (route.type) {
      case "render":
        this.log("render", this.element.id, route.data)
        this.lastServerData = route.data
        if (this.renderFn) this.render({ ...route.data, ...this.clientState })
        break

      case "request_update":
        this.log("update", this.element.id, { action: message.action, strategy: "notify" })
        this.requestUpdate()
        break

      case "update":
        this.log("update", this.element.id, route.data)
        this.lastServerData = route.data
        if (this.renderFn) this.render({ ...route.data, ...this.clientState })
        this.element.dispatchEvent(new CustomEvent("reactive-renderer:updated", {
          bubbles: true,
          detail: { data: route.data }
        }))
        break

      case "remove":
      case "destroy":
        this.element.remove()
        break
    }
  }

  requestUpdate() {
    if (this._updateTimer) clearTimeout(this._updateTimer)

    this._updateTimer = setTimeout(() => {
      this._updateTimer = null
      const sub = findSubscription(this.streamValue)
      if (!sub) return

      sub.perform("request_update", {
        component: this.componentValue,
        sgid: this.sgidValue,
        dom_id: this.element.id,
        // The channel reads client state off params, so the server renders the
        // state the component is in now, not the one the page was built with.
        params: { ...this.paramsValue, ...this.clientState }
      })
    }, 50)
  }

  render(data) {
    // ReactiveComponent.debug marks the wrapper; a missing key then throws
    // with its name rather than rendering as a silent falsy/undefined.
    const input = this.element.hasAttribute("data-reactive-debug") ? strictData(data, this.element.id) : data
    const newHtml = this.renderFn(input)
    this.morph(newHtml)
  }

  performAction(event) {
    event.preventDefault()
    event.stopPropagation()

    const actionName = event.params.action
    if (!actionName || !this.hasActionUrlValue || !this.hasActionTokenValue) return

    // --- Optimistic update ---
    const optimisticExpr = event.params.optimistic
    let rollbackData = null

    if (optimisticExpr && this.lastServerData && this.renderFn && this.fieldMapValue) {
      const dataKey = this.fieldMapValue[optimisticExpr]
      if (dataKey && dataKey in this.lastServerData) {
        rollbackData = { ...this.lastServerData }
        this.lastServerData[dataKey] = !this.lastServerData[dataKey]
        this.render({ ...this.lastServerData, ...this.clientState })
      }
    }
    // --- End optimistic ---

    const formData = event.type === "submit" ? new FormData(event.target) : null
    const { body, redirect } = buildActionBody(actionName, this.actionTokenValue, event.params, formData)

    fetch(this.actionUrlValue, {
      method: "POST",
      headers: this.actionHeaders(),
      body
    }).then(response => {
      if (!response.ok && rollbackData) {
        this.lastServerData = rollbackData
        this.render({ ...this.lastServerData, ...this.clientState })
      }
      if (redirect && response.ok) {
        Turbo.visit(redirect)
      } else if (response.ok && response.headers.get("content-type")?.includes("text/html")) {
        return response.text()
      }
    }).then(html => {
      if (html) this.morph(html)
    }).catch(() => {
      if (rollbackData) {
        this.lastServerData = rollbackData
        this.render({ ...this.lastServerData, ...this.clientState })
      }
    })
  }

  // With skipOwnBroadcasts, tags the request so the broadcast it causes can be
  // recognised and ignored. Turbo's header name, so turbo-rails tracks the id.
  actionHeaders() {
    const headers = { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content }
    if (!this.skipOwnBroadcastsValue) return headers

    const requestId = crypto.randomUUID?.() ?? Math.random().toString(36).slice(2)
    this.ownRequestIds ??= new Set()
    this.ownRequestIds.add(requestId)
    if (this.ownRequestIds.size > 20) this.ownRequestIds.delete(this.ownRequestIds.values().next().value)
    headers["X-Turbo-Request-Id"] = requestId
    return headers
  }

  setState(event) {
    const updates = { ...event.params }
    delete updates.action

    if (updates.exclusive) {
      delete updates.exclusive
      const container = this.element.parentElement
      if (container) {
        container.querySelectorAll(`:scope > [data-controller~="reactive-renderer"]`).forEach(el => {
          if (el === this.element) return
          const ctrl = this.application.getControllerForElementAndIdentifier(el, "reactive-renderer")
          if (!ctrl?.clientState) return
          let changed = false
          for (const key of Object.keys(updates)) {
            if (ctrl.clientState[key]) {
              ctrl.clientState[key] = false
              changed = true
            }
          }
          if (changed) ctrl.rerender()
        })
      }
    }

    Object.assign(this.clientState, updates)
    this.rerender()
  }

  // A push component holds the data it needs. A notify one may not have any
  // yet, its payload arrives on request, so a state change asks for it rather
  // than leaving the click with nothing to show.
  rerender() {
    if (this.lastServerData && this.renderFn) {
      requestAnimationFrame(() => this.render({ ...this.lastServerData, ...this.clientState }))
    } else if (this.strategyValue === "notify") {
      this.requestUpdate()
    }
  }

  morph(newHtml) {
    morphElement(this.element, newHtml)
  }
}
