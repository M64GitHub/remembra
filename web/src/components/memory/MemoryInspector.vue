<script setup>
import { ref, onMounted, onUnmounted, computed, watch } from 'vue'
import { memories as memoriesApi } from '../../api/client.js'
import { appState, registerReload } from '../../stores/appState.js'
import { onEvent } from '../../stores/eventBus.js'
import MemoryCard from './MemoryCard.vue'

const memories = ref([])
const isLoading = ref(false)
const error = ref(null)
const searchQuery = ref('')
const filterType = ref('all')
const hasLoaded = ref(false)
const referenceTime = ref(Date.now())

const filterOptions = [
  { value: 'all', label: 'All' },
  { value: 'fact', label: 'Facts' },
  { value: 'preference', label: 'Prefs' },
  { value: 'episode', label: 'Episodes' },
]

const filteredMemories = computed(() => {
  // Always filter out thoughts - they show in Thoughts Viewer
  let result = memories.value.filter(m => {
    const subj = m.subject?.toLowerCase() || ''
    const pred = m.predicate?.toLowerCase() || ''
    return !(subj === 'self' && pred === 'thought')
  })

  // Filter by type
  if (filterType.value !== 'all') {
    result = result.filter(m => {
      const pred = m.predicate?.toLowerCase() || ''

      switch (filterType.value) {
        case 'episode':
          return pred === 'episode' || pred === 'summary'
        case 'preference':
          return pred.includes('prefer') || pred.includes('like')
        case 'fact':
          return !pred.includes('episode') &&
                 !pred.includes('summary') &&
                 !pred.includes('prefer') &&
                 !pred.includes('like')
        default:
          return true
      }
    })
  }

  // Filter by search
  if (searchQuery.value.trim()) {
    const q = searchQuery.value.toLowerCase()
    result = result.filter(m =>
      m.subject?.toLowerCase().includes(q) ||
      m.predicate?.toLowerCase().includes(q) ||
      m.object?.toLowerCase().includes(q)
    )
  }

  return result
})

const memoryCount = computed(() => {
  return `${filteredMemories.value.length}/${memories.value.length}`
})

async function loadMemories() {
  if (isLoading.value || appState.isChatBusy) return

  isLoading.value = true
  error.value = null

  try {
    const data = await memoriesApi.list()
    memories.value = data.memories || []
    referenceTime.value = Date.now()
    console.log('[Memory] Loaded', memories.value.length, 'memories')
    if (memories.value.length > 0) {
      console.log('[Memory] Sample:', memories.value[0])
    }
  } catch (e) {
    console.error('[Memory] Error:', e)
    error.value = e.message
  } finally {
    isLoading.value = false
  }
}

async function deleteMemory(id) {
  try {
    await memoriesApi.remove(id)
    memories.value = memories.value.filter(m => m.id !== id)
  } catch (e) {
    console.error('[Memory] Delete error:', e)
    error.value = e.message
  }
}

// Load when pane becomes active
watch(
  () => appState.leftSidebarMode,
  (mode) => {
    if (mode === 'memory' && !hasLoaded.value) {
      loadMemories()
      hasLoaded.value = true
    }
  },
  { immediate: true }
)

let unregisterReload = null
let unsubscribeMemory = null

onMounted(() => {
  // Listen for memory_stored events from backend
  unsubscribeMemory = onEvent('memory_stored', () => {
    if (appState.leftSidebarMode === 'memory') {
      loadMemories()
    }
  })

  // Register for persona change reloads
  unregisterReload = registerReload('memories', async () => {
    memories.value = []
    hasLoaded.value = false
    await loadMemories()
    hasLoaded.value = true
  })
})

onUnmounted(() => {
  if (unsubscribeMemory) unsubscribeMemory()
  if (unregisterReload) unregisterReload()
})
</script>

<template>
  <div class="memory-inspector">
    <div class="inspector-toolbar">
      <input
        type="text"
        v-model="searchQuery"
        placeholder="Search..."
        class="search-input"
      />
      <select v-model="filterType" class="filter-select">
        <option
          v-for="opt in filterOptions"
          :key="opt.value"
          :value="opt.value"
        >
          {{ opt.label }}
        </option>
      </select>
      <button
        @click="loadMemories"
        class="toolbar-btn"
        :disabled="isLoading || appState.isChatBusy"
        title="Refresh"
      >
        &#x21BB;
      </button>
    </div>

    <div class="inspector-error" v-if="error">
      {{ error }}
    </div>

    <div class="inspector-content">
      <div class="memory-list" v-if="filteredMemories.length > 0">
        <MemoryCard
          v-for="memory in filteredMemories"
          :key="memory.id"
          :memory="memory"
          :reference-time="referenceTime"
          @delete="deleteMemory"
        />
      </div>

      <div class="inspector-empty" v-else-if="!isLoading">
        <template v-if="memories.length === 0">
          <p>No memories yet</p>
          <p class="hint">Chat with the AI and it will remember important facts</p>
        </template>
        <p v-else>No matches</p>
      </div>

      <div class="inspector-loading" v-if="isLoading">
        Loading...
      </div>
    </div>

    <div class="inspector-status">
      <span>{{ memoryCount }} memories</span>
    </div>
  </div>
</template>

<style scoped>
.memory-inspector {
  display: flex;
  flex-direction: column;
  height: 100%;
  font-size: var(--text-xs);
}

.inspector-toolbar {
  display: flex;
  gap: var(--space-xs);
  padding: var(--space-xs) var(--space-sm);
  background: var(--bg-secondary);
  border-bottom: var(--border-subtle);
}

.search-input {
  flex: 1;
  min-width: 0;
  padding: 4px 8px;
  background: var(--bg-tertiary);
  border: none;
  border-radius: var(--border-radius-sm);
  color: var(--text-primary);
  font-size: var(--text-xs);
}

.search-input::placeholder {
  color: var(--text-dim);
}

.filter-select {
  padding: 4px 6px;
  background: var(--bg-tertiary);
  border: none;
  border-radius: var(--border-radius-sm);
  color: var(--text-secondary);
  font-size: var(--text-xs);
}

.toolbar-btn {
  width: 24px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--border-radius-sm);
  color: var(--text-muted);
  font-size: 14px;
  transition: all var(--transition-fast);
}

.toolbar-btn:hover:not(:disabled) {
  background: var(--bg-tertiary);
  color: var(--text-primary);
}

.toolbar-btn:disabled {
  opacity: 0.5;
}

.inspector-error {
  padding: var(--space-xs) var(--space-sm);
  background: var(--error-dim);
  color: var(--error);
}

.inspector-content {
  flex: 1;
  overflow-y: auto;
  padding: var(--space-xs);
}

.memory-list {
  display: flex;
  flex-direction: column;
}

.inspector-empty {
  text-align: center;
  color: var(--text-dim);
  padding: var(--space-lg);
}

.inspector-empty .hint {
  font-size: var(--text-xs);
  margin-top: var(--space-xs);
  opacity: 0.7;
}

.inspector-loading {
  text-align: center;
  color: var(--text-dim);
  padding: var(--space-lg);
}

.inspector-status {
  padding: var(--space-xs) var(--space-sm);
  background: var(--bg-secondary);
  border-top: var(--border-subtle);
  color: var(--text-dim);
  font-size: 10px;
}
</style>
