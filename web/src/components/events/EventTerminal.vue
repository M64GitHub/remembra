<script setup>
import { ref, onMounted, onUnmounted, nextTick, computed } from 'vue'
import { onEvent } from '../../stores/eventBus.js'
import EventLine from './EventLine.vue'

const events = ref([])
const filter = ref('all')
const terminalRef = ref(null)
let eventId = 0

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
  store_changed: 'cyan',
  bookmarks_changed: 'cyan',
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
      case 'system':
        return kind.includes('context') ||
               kind.includes('chat') ||
               kind.includes('security') ||
               kind.includes('store') ||
               kind.includes('bookmark')
      default: return true
    }
  })
})

function handleEvent(event) {
  const evt = {
    id: ++eventId,
    kind: event.kind,
    subject: event.subject,
    details: event.data,
    timestamp_ms: Date.now(),
    color: EVENT_COLORS[event.kind] || 'blue',
  }

  events.value = [...events.value, evt].slice(-500)

  nextTick(() => scrollToBottom())
}

function scrollToBottom() {
  if (terminalRef.value) {
    terminalRef.value.scrollTop = terminalRef.value.scrollHeight
  }
}

function clearEvents() {
  events.value = []
}

let unsubscribe = null

onMounted(() => {
  unsubscribe = onEvent('*', handleEvent)
})

onUnmounted(() => {
  if (unsubscribe) unsubscribe()
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
      <span class="status-dot"></span>
      <span>{{ events.length }} events (SSE)</span>
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
</style>
