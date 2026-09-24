import { createConsumer } from "@rails/actioncable"
import { decompress } from "reactive_component/lib/reactive_renderer_utils"

const consumer = createConsumer()

// One ActionCable subscription per signed stream, shared by every controller on
// the page. A handler is any object answering subscriptionConnected,
// subscriptionDisconnected and handleMessage.
export function findSubscription(streamValue) {
  const identifier = JSON.stringify({ channel: "ReactiveComponent::Channel", signed_stream_name: streamValue })
  return consumer.subscriptions.subscriptions.find(s => s.identifier === identifier)
}

export function subscribe(streamValue, handler) {
  let sub = findSubscription(streamValue)

  if (!sub) {
    sub = consumer.subscriptions.create(
      { channel: "ReactiveComponent::Channel", signed_stream_name: streamValue },
      {
        connected() {
          sub._connected = true
          for (const handler of sub.handlers || []) {
            handler.subscriptionConnected()
          }
        },
        disconnected() {
          sub._connected = false
          for (const handler of sub.handlers || []) {
            handler.subscriptionDisconnected()
          }
        },
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
  sub.handlers.add(handler)
  if (sub._connected) handler.subscriptionConnected()
}

export function unsubscribe(streamValue, handler) {
  const sub = findSubscription(streamValue)
  if (!sub) return

  sub.handlers.delete(handler)
  if (sub.handlers.size === 0) {
    consumer.subscriptions.remove(sub)
  }
}
