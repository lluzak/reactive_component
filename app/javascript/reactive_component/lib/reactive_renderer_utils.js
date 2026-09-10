const templateCache = new Map()

export function isBase64(str) {
  return /^[A-Za-z0-9+/\n]+=*$/.test(str.trim())
}

export function compileTemplate(source) {
  if (templateCache.has(source)) return templateCache.get(source)

  try {
    const body = isBase64(source) ? decodeBase64(source) : source
    const fn = new Function("data", body)
    templateCache.set(source, fn)
    return fn
  } catch (e) {
    console.log("[reactive-renderer] ERROR compiling template:", e)
    return null
  }
}

// atob yields one char per byte, so multibyte UTF-8 (★, é, emoji) in a
// template literal came out as mojibake once the client re-rendered.
function decodeBase64(base64) {
  return new TextDecoder().decode(Uint8Array.from(atob(base64), c => c.charCodeAt(0)))
}

export function clearTemplateCache() {
  templateCache.clear()
}

export async function decompress(base64) {
  const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0))
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"))
  return new Response(stream).json()
}

export function morphElement(element, newHtml) {
  const parser = new DOMParser()
  const doc = parser.parseFromString(`<div>${newHtml}</div>`, "text/html")
  const newContent = doc.body.firstChild

  if (typeof Idiomorph !== "undefined") {
    Idiomorph.morph(element, newContent, {
      morphStyle: "innerHTML",
      ignoreActiveValue: true
    })
  } else {
    element.innerHTML = newContent.innerHTML
  }

  element.classList.remove("reactive-morph-flash")
  void element.offsetWidth
  element.classList.add("reactive-morph-flash")
}

export function buildActionBody(actionName, actionToken, stimulusParams, formData) {
  const body = new URLSearchParams({
    token: actionToken,
    action_name: actionName
  })

  const params = { ...stimulusParams }
  delete params.action
  const redirect = params.redirect
  delete params.redirect

  for (const [key, value] of Object.entries(params)) {
    const snakeKey = key.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`)
    body.append(`params[${snakeKey}]`, value)
  }

  if (formData) {
    for (const [key, value] of formData.entries()) {
      body.append(`params[${key}]`, value)
    }
  }

  return { body, redirect }
}

export function routeMessage(message, elementId, strategy) {
  const { action, data } = message

  if (action === "render" && data?.dom_id === elementId) {
    return { type: "render", data }
  }

  if (strategy === "notify" && (action === "update" || action === "destroy")) {
    return { type: "request_update" }
  }

  if (action === "update" && data?.dom_id === elementId) {
    return { type: "update", data }
  }

  if (action === "remove" && (message.dom_id || data?.dom_id) === elementId) {
    return { type: "remove" }
  }

  if (action === "destroy" && data?.dom_id === elementId) {
    return { type: "destroy" }
  }

  return { type: "ignore" }
}

// Every element in `doc` that shares `element`'s id, excluding `element`.
// Broadcasts are routed to a component by its id, so a duplicate means one
// payload renders into several components — and a TypeError deep in the
// compiled template as soon as their shapes differ. Checked on connect, which
// Stimulus already fires for every component entering the DOM (its own
// MutationObserver), so nothing else needs to watch the page.
export function duplicateIds(doc, element) {
  if (!element.id) return []
  const selector = `[id="${element.id.replace(/["\\]/g, "\\$&")}"]`
  return [...doc.querySelectorAll(selector)].filter(other => other !== element)
}

// Debug mode only: `data` (and every item inside it) wrapped so that reading
// a key the payload does not carry THROWS, naming the key and what is there,
// instead of yielding undefined — which is silently falsy in an `if` and
// only ever surfaces as a mystery `.x of undefined` further down. Keys on the
// prototype chain (map, toString, constructor) and symbols pass through, so
// only a genuinely missing field trips it.
export function strictData(data, label) {
  const wrap = (target, path) => new Proxy(target, {
    get(obj, key, receiver) {
      if (typeof key === "symbol" || key in obj) {
        const value = Reflect.get(obj, key, receiver)
        return value && typeof value === "object" ? wrap(value, `${path}${String(key)}.`) : value
      }
      throw new TypeError(
        `[reactive-renderer] ${label}: template read "${path}${String(key)}" but the payload only has: ` +
        Object.keys(obj).join(", ")
      )
    }
  })
  return wrap(data, "")
}
