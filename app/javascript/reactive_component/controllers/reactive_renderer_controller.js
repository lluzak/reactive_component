import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { compileTemplate, decompress, morphElement, buildActionBody, routeMessage } from "reactive_component/lib/reactive_renderer_utils"

const consumer = createConsumer()
const log = (...args) => {
  if (localStorage.getItem("devToolbar:debug") !== "false") {
    console.log("[reactive-renderer]", ...args)
  }
}

function findSubscription(streamValue) {
  const identifier = JSON.stringify({ channel: "ReactiveComponent::Channel", signed_stream_name: streamValue })
  return consumer.subscriptions.subscriptions.find(s => s.identifier === identifier)
}

function subscribe(streamValue, controller) {
  let sub = findSubscription(streamValue)

  if (!sub) {
    sub = consumer.subscriptions.create(
      { channel: "ReactiveComponent::Channel", signed_stream_name: streamValue },
      {
        received: async (message) => {
          const decoded = message.z ? await decompress(message.z) : message
          for (const handler of sub.handlers) {
            handler.handleMessage(decoded)
          }
        }
      }
    )
    sub.handlers = new Set()
  }
  sub.handlers.add(controller)
}

function unsubscribe(streamValue, controller) {
  const sub = findSubscription(streamValue)
  if (!sub) return

  sub.handlers.delete(controller)
  if (sub.handlers.size === 0) {
    consumer.subscriptions.remove(sub)
  }
}

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
    params: { type: Object, default: {} },
    fieldMap: { type: Object, default: {} }
  }

  connect() {
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

  resolveTemplate() {
    if (this.hasTemplateValue) return this.templateValue

    if (this.hasTemplateIdValue) {
      const el = document.getElementById(this.templateIdValue)
      if (el) return el.textContent
    }

    return null
  }

  handleMessage(message) {
    const route = routeMessage(message, this.element.id, this.strategyValue)

    switch (route.type) {
      case "render":
        log("render", this.element.id, route.data)
        this.lastServerData = route.data
        if (this.renderFn) this.render({ ...route.data, ...this.clientState })
        break

      case "request_update":
        log("update", this.element.id, { action: message.action, strategy: "notify" })
        this.requestUpdate()
        break

      case "update":
        log("update", this.element.id, route.data)
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
        record_id: this.dataValue?.id,
        dom_id: this.element.id,
        params: this.paramsValue
      })
    }, 50)
  }

  render(data) {
    const newHtml = this.renderFn(data)
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
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
      },
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
          if (changed && ctrl.lastServerData && ctrl.renderFn) {
            requestAnimationFrame(() => ctrl.render({ ...ctrl.lastServerData, ...ctrl.clientState }))
          }
        })
      }
    }

    Object.assign(this.clientState, updates)
    if (this.lastServerData && this.renderFn) {
      requestAnimationFrame(() => this.render({ ...this.lastServerData, ...this.clientState }))
    }
  }

  morph(newHtml) {
    morphElement(this.element, newHtml)
  }
}
