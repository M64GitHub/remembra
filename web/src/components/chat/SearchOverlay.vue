<script setup>
import { ref, watch, onMounted, onUnmounted } from 'vue'
import { chat } from '../../api/client.js'

const emit = defineEmits(['close', 'jump-to'])

const searchQuery = ref('')
const results = ref([])
const isSearching = ref(false)
const inputRef = ref(null)
let searchTimeout = null

function formatDate(ms) {
  if (!ms) return ''
  const d = new Date(ms)
  return d.toLocaleDateString(undefined, {
    month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
  })
}

function truncate(text, maxLen = 100) {
  if (!text) return ''
  if (text.length <= maxLen) return text
  return text.substring(0, maxLen) + '...'
}

function roleLabel(role) {
  if (role === 'user') return 'You'
  if (role === 'assistant') return 'AI'
  return role
}

async function performSearch() {
  const q = searchQuery.value.trim()
  if (!q || q.length < 2) {
    results.value = []
    return
  }

  isSearching.value = true
  try {
    const data = await chat.search(q)
    results.value = data.results || []
  } catch (e) {
    console.error('Search error:', e)
    results.value = []
  } finally {
    isSearching.value = false
  }
}

function debouncedSearch() {
  if (searchTimeout) clearTimeout(searchTimeout)
  searchTimeout = setTimeout(performSearch, 300)
}

watch(searchQuery, debouncedSearch)

function handleJump(messageId) {
  emit('jump-to', messageId)
  emit('close')
}

function handleKeydown(e) {
  if (e.key === 'Escape') {
    emit('close')
  }
}

function handleOverlayClick(e) {
  if (e.target === e.currentTarget) {
    emit('close')
  }
}

onMounted(() => {
  document.addEventListener('keydown', handleKeydown)
  if (inputRef.value) {
    inputRef.value.focus()
  }
})

onUnmounted(() => {
  document.removeEventListener('keydown', handleKeydown)
  if (searchTimeout) clearTimeout(searchTimeout)
})
</script>

<template>
  <div class="search-overlay" @click="handleOverlayClick">
    <div class="search-panel">
      <div class="search-header">
        <input
          ref="inputRef"
          v-model="searchQuery"
          type="text"
          placeholder="Search messages..."
          class="search-input"
        />
        <button class="close-btn" @click="$emit('close')">&#x2715;</button>
      </div>

      <div class="search-results">
        <div v-if="isSearching" class="search-loading">
          Searching...
        </div>
        <div v-else-if="results.length === 0 && searchQuery.length >= 2" class="search-empty">
          No messages found
        </div>
        <div v-else-if="searchQuery.length < 2" class="search-hint">
          Type at least 2 characters to search
        </div>
        <div
          v-for="result in results"
          :key="result.id"
          class="result-item"
          @click="handleJump(result.id)"
        >
          <div class="result-meta">
            <span class="result-role" :class="result.role">
              {{ roleLabel(result.role) }}
            </span>
            <span class="result-date">{{ formatDate(result.created_at_ms) }}</span>
          </div>
          <div class="result-content">{{ truncate(result.content, 150) }}</div>
        </div>
      </div>

      <div class="search-footer">
        {{ results.length }} results
      </div>
    </div>
  </div>
</template>

<style scoped>
.search-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding-top: 80px;
  z-index: 150;
}

.search-panel {
  width: 90%;
  max-width: 600px;
  max-height: 70vh;
  background: var(--bg-primary);
  border-radius: var(--border-radius-lg);
  border: var(--border-subtle);
  box-shadow: var(--shadow-lg);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.search-header {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  padding: var(--space-md);
  border-bottom: var(--border-subtle);
}

.search-input {
  flex: 1;
  padding: var(--space-sm) var(--space-md);
  font-size: var(--text-base);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius);
  color: var(--text-primary);
}

.search-input:focus {
  outline: none;
  border-color: var(--accent-primary);
}

.close-btn {
  padding: var(--space-xs);
  font-size: var(--text-base);
  color: var(--text-muted);
  border-radius: var(--border-radius-sm);
}

.close-btn:hover {
  background: var(--bg-hover);
  color: var(--text-primary);
}

.search-results {
  flex: 1;
  overflow-y: auto;
  padding: var(--space-sm);
}

.search-loading,
.search-empty,
.search-hint {
  padding: var(--space-lg);
  text-align: center;
  color: var(--text-dim);
  font-size: var(--text-sm);
}

.result-item {
  padding: var(--space-sm);
  margin-bottom: var(--space-xs);
  background: var(--bg-secondary);
  border-radius: var(--border-radius-sm);
  cursor: pointer;
  transition: all var(--transition-fast);
}

.result-item:hover {
  background: var(--bg-hover);
  border-left: 2px solid var(--accent-primary);
}

.result-meta {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  margin-bottom: var(--space-xs);
}

.result-role {
  font-size: var(--text-xs);
  font-weight: 500;
  padding: 2px 6px;
  border-radius: var(--border-radius-sm);
}

.result-role.user {
  background: var(--accent-glow);
  color: var(--accent-primary);
}

.result-role.assistant {
  background: var(--success-dim);
  color: var(--success);
}

.result-date {
  font-size: 10px;
  color: var(--text-dim);
}

.result-content {
  font-size: var(--text-sm);
  color: var(--text-secondary);
  line-height: 1.4;
}

.search-footer {
  padding: var(--space-xs) var(--space-md);
  font-size: var(--text-xs);
  color: var(--text-dim);
  text-align: center;
  border-top: var(--border-subtle);
}
</style>
