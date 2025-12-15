import { reactive } from 'vue'

// Simple shared state for coordinating requests
// Single-threaded server can only handle one request at a time
export const appState = reactive({
  isChatBusy: false,
  activeAiName: '...',
})
