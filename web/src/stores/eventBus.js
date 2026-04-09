/**
 * SSE Event Bus for real-time event streaming from the server.
 * Connects to the event server on port 8081 and dispatches events to listeners.
 */

let eventSource = null
const listeners = new Map()
let reconnectTimeout = null

export function connectEvents(port = 8081) {
  if (eventSource) {
    return
  }

  const url = `${location.protocol}//${location.hostname}:${port}/events`
  eventSource = new EventSource(url)

  eventSource.onmessage = (e) => {
    try {
      const event = JSON.parse(e.data)
      dispatchEvent(event)
    } catch (err) {
      console.warn('[eventBus] Failed to parse event:', err)
    }
  }

  eventSource.onopen = () => {
    console.log('[eventBus] Connected to event server')
    if (reconnectTimeout) {
      clearTimeout(reconnectTimeout)
      reconnectTimeout = null
    }
  }

  eventSource.onerror = () => {
    console.warn('[eventBus] Connection error, will reconnect...')
    eventSource.close()
    eventSource = null
    reconnectTimeout = setTimeout(() => connectEvents(port), 3000)
  }
}

function dispatchEvent(event) {
  const kindListeners = listeners.get(event.kind) || []
  kindListeners.forEach(cb => cb(event))

  const allListeners = listeners.get('*') || []
  allListeners.forEach(cb => cb(event))
}

export function onEvent(kind, callback) {
  if (!listeners.has(kind)) {
    listeners.set(kind, [])
  }
  listeners.get(kind).push(callback)

  return () => {
    const arr = listeners.get(kind)
    const idx = arr.indexOf(callback)
    if (idx >= 0) arr.splice(idx, 1)
  }
}

export function emitEvent(kind, data = {}) {
  dispatchEvent({ kind, ...data })
}

export function disconnectEvents() {
  if (reconnectTimeout) {
    clearTimeout(reconnectTimeout)
    reconnectTimeout = null
  }
  if (eventSource) {
    eventSource.close()
    eventSource = null
  }
  listeners.clear()
}

export function isConnected() {
  return eventSource !== null && eventSource.readyState === EventSource.OPEN
}
