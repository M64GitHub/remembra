<script setup>
import { ref, onMounted, onUnmounted, computed, watch } from 'vue'
import { context as contextApi } from '../../api/client.js'
import { appState, registerReload } from '../../stores/appState.js'

const contextData = ref(null)
const isLoading = ref(false)
const error = ref(null)
const expandedSections = ref({
  prompt: true,
  stats: true,
})

const formattedTime = computed(() => {
  if (!contextData.value?.timestamp_ms) return 'Never'
  const date = new Date(contextData.value.timestamp_ms)
  return date.toLocaleTimeString('en-US', {
    hour12: false,
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
})

const promptLines = computed(() => {
  if (!contextData.value?.system_prompt) return 0
  return contextData.value.system_prompt.split('\n').length
})

const promptChars = computed(() => {
  if (!contextData.value?.system_prompt) return 0
  return contextData.value.system_prompt.length
})

async function loadContext() {
  if (isLoading.value || appState.isChatBusy) return

  isLoading.value = true
  error.value = null

  try {
    const data = await contextApi.get()
    contextData.value = data
    console.log('[Context] Loaded:', data)
  } catch (e) {
    console.error('[Context] Error:', e)
    error.value = e.message
  } finally {
    isLoading.value = false
  }
}

function toggleSection(section) {
  expandedSections.value[section] = !expandedSections.value[section]
}

// Auto-refresh context when chat completes
watch(
  () => appState.isChatBusy,
  (newVal, oldVal) => {
    if (oldVal === true && newVal === false) {
      // Chat just finished - context was freshly built
      setTimeout(loadContext, 500)
    }
  }
)

let unregisterReload = null

onMounted(() => {
  setTimeout(loadContext, 2000)

  // Register for persona change reloads
  unregisterReload = registerReload('context', async () => {
    contextData.value = null
    await loadContext()
  })
})

onUnmounted(() => {
  if (unregisterReload) unregisterReload()
})
</script>

<template>
  <div class="context-viewer">
    <div class="context-toolbar">
      <button
        @click="loadContext"
        class="toolbar-btn"
        :disabled="isLoading || appState.isChatBusy"
        title="Refresh context"
      >
        &#x21BB;
      </button>
      <span class="context-time">{{ formattedTime }}</span>
    </div>

    <div class="context-error" v-if="error">
      {{ error }}
    </div>

    <div class="context-content" v-if="contextData">
      <!-- Stats Section -->
      <div class="context-section">
        <button
          class="section-header"
          @click="toggleSection('stats')"
        >
          <span class="section-title">Stats</span>
          <span class="section-toggle">
            {{ expandedSections.stats ? '\u25BC' : '\u25B6' }}
          </span>
        </button>
        <div class="section-body" v-show="expandedSections.stats">
          <div class="stat-row">
            <span class="stat-label">Memories injected:</span>
            <span class="stat-value">{{ contextData.memory_count }}</span>
          </div>
          <div class="stat-row">
            <span class="stat-label">Recent messages:</span>
            <span class="stat-value">{{ contextData.recent_count }}</span>
          </div>
          <div class="stat-row">
            <span class="stat-label">Prompt lines:</span>
            <span class="stat-value">{{ promptLines }}</span>
          </div>
          <div class="stat-row">
            <span class="stat-label">Prompt chars:</span>
            <span class="stat-value">{{ promptChars.toLocaleString() }}</span>
          </div>
        </div>
      </div>

      <!-- System Prompt Section -->
      <div class="context-section">
        <button
          class="section-header"
          @click="toggleSection('prompt')"
        >
          <span class="section-title">System Prompt</span>
          <span class="section-toggle">
            {{ expandedSections.prompt ? '\u25BC' : '\u25B6' }}
          </span>
        </button>
        <div class="section-body" v-show="expandedSections.prompt">
          <pre class="prompt-content">{{ contextData.system_prompt || '(empty)' }}</pre>
        </div>
      </div>
    </div>

    <div class="context-empty" v-else-if="!isLoading && !error">
      <p>No context yet</p>
      <p class="text-dim">Send a message to generate context</p>
    </div>

    <div class="context-loading" v-if="isLoading">
      Loading...
    </div>
  </div>
</template>

<style scoped>
.context-viewer {
  display: flex;
  flex-direction: column;
  height: 100%;
  font-size: var(--text-xs);
}

.context-toolbar {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  padding: var(--space-xs) var(--space-sm);
  background: var(--bg-secondary);
  border-bottom: var(--border-subtle);
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

.context-time {
  color: var(--text-dim);
  font-family: var(--font-mono);
  font-size: 10px;
}

.context-error {
  padding: var(--space-xs) var(--space-sm);
  background: var(--error-dim);
  color: var(--error);
}

.context-content {
  flex: 1;
  overflow-y: auto;
  padding: var(--space-xs);
}

.context-section {
  margin-bottom: var(--space-xs);
  background: var(--bg-secondary);
  border-radius: var(--border-radius-sm);
  overflow: hidden;
}

.section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  width: 100%;
  padding: var(--space-xs) var(--space-sm);
  background: var(--bg-tertiary);
  text-align: left;
  transition: background var(--transition-fast);
}

.section-header:hover {
  background: var(--bg-hover);
}

.section-title {
  font-weight: 500;
  color: var(--text-secondary);
}

.section-toggle {
  color: var(--text-dim);
  font-size: 10px;
}

.section-body {
  padding: var(--space-sm);
}

.stat-row {
  display: flex;
  justify-content: space-between;
  padding: 2px 0;
}

.stat-label {
  color: var(--text-muted);
}

.stat-value {
  color: var(--accent-primary);
  font-family: var(--font-mono);
}

.prompt-content {
  font-family: var(--font-mono);
  font-size: 10px;
  line-height: 1.4;
  color: var(--text-secondary);
  white-space: pre-wrap;
  word-break: break-word;
  max-height: 300px;
  overflow-y: auto;
  padding: var(--space-xs);
  background: var(--bg-deep);
  border-radius: var(--border-radius-sm);
}

.context-empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  color: var(--text-muted);
  padding: var(--space-lg);
}

.context-loading {
  padding: var(--space-lg);
  text-align: center;
  color: var(--text-dim);
}
</style>
