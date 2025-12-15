<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue'
import { thoughts as thoughtsApi } from '../../api/client.js'
import { appState } from '../../stores/appState.js'
import ThoughtCard from './ThoughtCard.vue'

const thoughts = ref([])
const isLoading = ref(false)
const error = ref(null)

let refreshInterval = null

async function loadThoughts() {
  if (isLoading.value || appState.isChatBusy) return

  isLoading.value = true
  error.value = null

  try {
    const data = await thoughtsApi.list()
    thoughts.value = data.memories || []
    console.log('[Thoughts] Loaded', thoughts.value.length, 'thoughts')
  } catch (e) {
    console.error('[Thoughts] Error:', e)
    error.value = e.message
  } finally {
    isLoading.value = false
  }
}

watch(
  () => appState.isChatBusy,
  (newVal, oldVal) => {
    if (oldVal === true && newVal === false) {
      setTimeout(loadThoughts, 1500)
    }
  }
)

onMounted(() => {
  setTimeout(loadThoughts, 3000)
  refreshInterval = setInterval(loadThoughts, 30000)
})

onUnmounted(() => {
  if (refreshInterval) clearInterval(refreshInterval)
})
</script>

<template>
  <div class="thoughts-viewer">
    <div class="viewer-toolbar">
      <span class="toolbar-label">AI Reflections</span>
      <button
        @click="loadThoughts"
        class="toolbar-btn"
        :disabled="isLoading || appState.isChatBusy"
        title="Refresh"
      >
        &#x21BB;
      </button>
    </div>

    <div class="viewer-error" v-if="error">
      {{ error }}
    </div>

    <div class="viewer-content">
      <div class="thought-list" v-if="thoughts.length > 0">
        <ThoughtCard
          v-for="thought in thoughts"
          :key="thought.id"
          :thought="thought"
        />
      </div>

      <div class="viewer-empty" v-else-if="!isLoading">
        No thoughts yet...
      </div>

      <div class="viewer-loading" v-if="isLoading">
        Loading...
      </div>
    </div>

    <div class="viewer-status">
      <span>{{ thoughts.length }} thoughts</span>
    </div>
  </div>
</template>

<style scoped>
.thoughts-viewer {
  display: flex;
  flex-direction: column;
  height: 100%;
  font-size: var(--text-xs);
}

.viewer-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--space-xs) var(--space-sm);
  background: var(--bg-secondary);
  border-bottom: var(--border-subtle);
}

.toolbar-label {
  color: var(--text-dim);
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

.viewer-error {
  padding: var(--space-xs) var(--space-sm);
  background: var(--error-dim);
  color: var(--error);
}

.viewer-content {
  flex: 1;
  overflow-y: auto;
  padding: var(--space-xs);
}

.thought-list {
  display: flex;
  flex-direction: column;
}

.viewer-empty {
  text-align: center;
  color: var(--text-dim);
  padding: var(--space-lg);
  font-style: italic;
}

.viewer-loading {
  text-align: center;
  color: var(--text-dim);
  padding: var(--space-lg);
}

.viewer-status {
  padding: var(--space-xs) var(--space-sm);
  background: var(--bg-secondary);
  border-top: var(--border-subtle);
  color: var(--text-dim);
  font-size: 10px;
}
</style>
