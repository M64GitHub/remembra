<script setup>
import { ref, watch, onMounted, onUnmounted, nextTick, computed } from 'vue'
import { events as eventsApi } from '../../api/client.js'
import { appState, registerReload } from '../../stores/appState.js'
import EventLine from './EventLine.vue'

const events = ref([])
const isLoading = ref(false)
const filter = ref('all')
const error = ref(null)
const terminalRef = ref(null)
const lastTimestamp = ref(0)

let pollInterval = null

const EVENT_COLORS = {
  memory_proposed: 'purple',
  memory_stored: 'purple',
  memory_decayed: 'orange',
  memory_rejected: 'red',
  thought_generated: 'green',
  episode_compacted: 'yellow',
  governor_blocked: 'red',
  governor_accepted: 'green',
  context_built: 'blue',
  chat_completed: 'blue',
  security_warning: 'red',
  command_executed: 'cyan',
}

const filterOptions = [
  { value: 'all', label: 'All Events' },
  { value: 'memory', label: 'Memory' },
  { value: 'thought', label: 'Thoughts' },
  { value: 'governor', label: 'Governor' },
  { value: 'system', label: 'System' },
]

const filteredEvents = computed(() => {
  if (filter.value === 'all') return events.value
  return events.value.filter(e => {
    const kind = e.kind || ''
    switch (filter.value) {
      case 'memory': return kind.startsWith('memory_')
      case 'thought': return kind.includes('thought') || kind.includes('episode')
      case 'governor': return kind.startsWith('governor_')
      case 'system': return kind.includes('context') || kind.includes('chat') || kind.includes('security')
      default: return true
    }
  })
})

async function fetchEvents() {
  if (isLoading.value || appState.isChatBusy) return

  isLoading.value = true
  try {
    const since = lastTimestamp.value > 0 ? lastTimestamp.value + 1 : null
    console.log('[Events] Fetching since:', since)
    const data = await eventsApi.list(since, 100)
    const newEvents = data.events || []
    console.log('[Events] Got', newEvents.length, 'events:', newEvents)

    if (newEvents.length > 0) {
      for (const evt of newEvents) {
        evt.color = EVENT_COLORS[evt.kind] || 'blue'
        if (evt.timestamp_ms > lastTimestamp.value) {
          lastTimestamp.value = evt.timestamp_ms
        }
      }

      events.value = [...events.value, ...newEvents].slice(-500)
      console.log('[Events] Total events now:', events.value.length)

      await nextTick()
      scrollToBottom()
    }
    error.value = null
  } catch (e) {
    console.error('[Events] Fetch error:', e)
    error.value = e.message
  } finally {
    isLoading.value = false
  }
}

function scrollToBottom() {
  if (terminalRef.value) {
    terminalRef.value.scrollTop = terminalRef.value.scrollHeight
  }
}

function clearEvents() {
  events.value = []
  lastTimestamp.value = 0
}

let unregisterReload = null

onMounted(() => {
  // Delay initial fetch to let messages load first (single-threaded server)
  setTimeout(() => {
    fetchEvents()
    pollInterval = setInterval(fetchEvents, 5000)  // Poll every 5 seconds
  }, 1500)

  // Register for persona change reloads
  unregisterReload = registerReload('events', async () => {
    clearEvents()
    await fetchEvents()
  })
})

onUnmounted(() => {
  if (pollInterval) clearInterval(pollInterval)
  if (unregisterReload) unregisterReload()
})
</script>

<template>
  <div class="event-terminal">
    <div class="terminal-toolbar">
      <select v-model="filter" class="filter-select">
        <option
          v-for="opt in filterOptions"
          :key="opt.value"
          :value="opt.value"
        >
          {{ opt.label }}
        </option>
      </select>

      <div class="toolbar-spacer"></div>

      <button
        @click="clearEvents"
        class="toolbar-btn"
        title="Clear"
      >
        ×
      </button>
    </div>

    <div class="terminal-error" v-if="error">
      {{ error }}
    </div>

    <div class="terminal-content" ref="terminalRef">
      <div v-if="filteredEvents.length === 0" class="terminal-empty">
        Waiting for events...
      </div>

      <EventLine
        v-for="event in filteredEvents"
        :key="event.id"
        :event="event"
      />
    </div>

    <div class="terminal-status">
      <span class="status-dot" :class="{ busy: appState.isChatBusy }"></span>
      <span v-if="appState.isChatBusy">Waiting for chat...</span>
      <span v-else>{{ events.length }} events</span>
    </div>
  </div>
</template>

<style scoped>
.event-terminal {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: var(--bg-deep);
  font-family: var(--font-mono);
  font-size: var(--text-xs);
}

.terminal-toolbar {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  padding: var(--space-xs) var(--space-sm);
  background: var(--bg-secondary);
  border-bottom: var(--border-subtle);
}

.filter-select {
  padding: 2px var(--space-xs);
  background: var(--bg-tertiary);
  border: none;
  border-radius: var(--border-radius-sm);
  color: var(--text-secondary);
  font-size: var(--text-xs);
  font-family: var(--font-mono);
}

.toolbar-spacer {
  flex: 1;
}

.toolbar-btn {
  width: 24px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--border-radius-sm);
  color: var(--text-muted);
  font-size: 10px;
  transition: all var(--transition-fast);
}

.toolbar-btn:hover {
  background: var(--bg-tertiary);
  color: var(--text-primary);
}

.terminal-error {
  padding: var(--space-xs) var(--space-sm);
  background: var(--error-dim);
  color: var(--error);
  font-size: var(--text-xs);
}

.terminal-content {
  flex: 1;
  overflow-y: auto;
  overflow-x: hidden;
  padding: var(--space-xs);
}

.terminal-empty {
  color: var(--text-dim);
  text-align: center;
  padding: var(--space-lg);
}

.terminal-status {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  padding: var(--space-xs) var(--space-sm);
  background: var(--bg-secondary);
  border-top: var(--border-subtle);
  color: var(--text-dim);
  font-size: 10px;
}

.status-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--success);
}

.status-dot.busy {
  background: var(--accent-primary);
  animation: pulse 1s infinite;
}
</style>
