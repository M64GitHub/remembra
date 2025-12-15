import { reactive } from 'vue'

// Simple shared state for coordinating requests
// Single-threaded server can only handle one request at a time
export const appState = reactive({
  isChatBusy: false,
  activeAiName: '...',
  activePersonaId: null,
  maxRecentMessages: 24,
})

// Reload callback registry for sequential persona change reloads
const reloadCallbacks = []

export function registerReload(name, callback) {
  reloadCallbacks.push({ name, callback })
  return () => {
    const idx = reloadCallbacks.findIndex(r => r.name === name)
    if (idx >= 0) reloadCallbacks.splice(idx, 1)
  }
}

export async function reloadAllData() {
  console.log('[AppState] Sequential reload starting...')
  for (const { name, callback } of reloadCallbacks) {
    console.log(`[AppState] Reloading: ${name}`)
    try {
      await callback()
    } catch (e) {
      console.error(`[AppState] Reload failed: ${name}`, e)
    }
  }
  console.log('[AppState] Sequential reload complete')
}
