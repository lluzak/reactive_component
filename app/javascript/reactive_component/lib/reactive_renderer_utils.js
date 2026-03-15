const templateCache = new Map()

export function isBase64(str) {
  return /^[A-Za-z0-9+/\n]+=*$/.test(str.trim())
}

export function compileTemplate(source) {
  if (templateCache.has(source)) return templateCache.get(source)

  try {
    const body = isBase64(source) ? atob(source) : source
    const fn = new Function("data", body)
    templateCache.set(source, fn)
    return fn
  } catch (e) {
    console.log("[reactive-renderer] ERROR compiling template:", e)
    return null
  }
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
