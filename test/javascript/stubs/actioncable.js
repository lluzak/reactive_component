// ActionCable is a peer dependency and is not installed. Nothing here opens a
// socket: tests that reach the registry substitute their own subscription.
export function createConsumer() {
  return { subscriptions: { subscriptions: [], create: () => ({}), remove() {} } }
}
