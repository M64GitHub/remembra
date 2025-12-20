<script setup>
import { ref, computed } from 'vue'
import { appState, clearSelection } from '../../stores/appState.js'
import { store } from '../../api/client.js'

const props = defineProps({
  messages: {
    type: Array,
    default: () => [],
  },
})

const emit = defineEmits(['store-created'])

const combineMode = ref(false)

const selectionCount = computed(() => appState.selectedMessageIds.size)
const hasSelection = computed(() => selectionCount.value > 0)

function formatRole(role) {
  if (role === 'user') return 'User'
  if (role === 'assistant') return 'Assistant'
  if (role === 'system') return 'System'
  return role
}

function formatTimestamp(ts) {
  if (!ts) return ''
  const date = new Date(ts)
  return date.toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function combineMessages(messages) {
  const sorted = [...messages].sort((a, b) => {
    const tsA = a.created_at_ms || a.id
    const tsB = b.created_at_ms || b.id
    return tsA - tsB
  })

  return sorted.map((msg, idx) => {
    const role = formatRole(msg.role)
    const time = formatTimestamp(msg.created_at_ms)
    const header = `## From: ${role} | ${time}`
    const separator = idx === 0 ? '' : '\n---\n'
    return `${separator}${header}\n\n${msg.content}`
  }).join('\n')
}

async function copyToStore() {
  const selectedIds = Array.from(appState.selectedMessageIds)
  const selectedMsgs = props.messages.filter(m => selectedIds.includes(m.id))

  if (combineMode.value && selectedMsgs.length > 0) {
    const combined = combineMessages(selectedMsgs)
    try {
      await store.create(combined, null)
    } catch (e) {
      console.error('Failed to store combined messages:', e)
    }
  } else {
    for (const msg of selectedMsgs) {
      try {
        await store.create(msg.content, msg.id)
      } catch (e) {
        console.error('Failed to store message:', e)
      }
    }
  }

  clearSelection()
  combineMode.value = false
  emit('store-created')
}

function cancelSelection() {
  clearSelection()
  combineMode.value = false
}
</script>

<template>
  <Transition name="fade-up">
    <div v-if="hasSelection" class="floating-actions">
      <span class="selection-count">{{ selectionCount }} selected</span>
      <label class="combine-toggle" :class="{ active: combineMode }">
        <input type="checkbox" v-model="combineMode" />
        <span class="toggle-label">Combine</span>
      </label>
      <button
        class="action-btn store-btn"
        @click="copyToStore"
        :title="combineMode ? 'Combine & Store' : 'Store separately'"
      >{{ combineMode ? 'C+S' : 'S' }}</button>
      <button
        class="action-btn cancel-btn"
        @click="cancelSelection"
        title="Cancel selection"
      >&#x2715;</button>
    </div>
  </Transition>
</template>

<style scoped>
.floating-actions {
  position: fixed;
  bottom: 100px;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  padding: var(--space-sm) var(--space-md);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-lg);
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
  z-index: 100;
}

.selection-count {
  font-size: var(--text-sm);
  color: var(--text-secondary);
  padding-right: var(--space-sm);
  border-right: 1px solid var(--border-color);
}

.combine-toggle {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  padding: var(--space-xs) var(--space-sm);
  border-radius: var(--border-radius-sm);
  cursor: pointer;
  transition: all var(--transition-fast);
  background: var(--bg-tertiary);
  border: 1px solid transparent;
}

.combine-toggle:hover {
  background: var(--bg-hover);
}

.combine-toggle.active {
  background: var(--accent-glow);
  border-color: var(--accent-primary);
}

.combine-toggle input {
  display: none;
}

.toggle-label {
  font-size: var(--text-xs);
  color: var(--text-secondary);
  font-weight: 500;
}

.combine-toggle.active .toggle-label {
  color: var(--accent-primary);
}

.action-btn {
  font-family: var(--font-mono);
  font-size: var(--text-sm);
  font-weight: 600;
  padding: var(--space-xs) var(--space-sm);
  border-radius: var(--border-radius-sm);
  cursor: pointer;
  transition: all var(--transition-fast);
  border: 1px solid transparent;
}

.store-btn {
  background: var(--accent-primary);
  color: white;
}

.store-btn:hover {
  background: var(--accent-secondary);
}

.cancel-btn {
  background: transparent;
  color: var(--text-muted);
}

.cancel-btn:hover {
  background: var(--bg-hover);
  color: var(--text-primary);
}

.fade-up-enter-active,
.fade-up-leave-active {
  transition: all 0.2s ease;
}

.fade-up-enter-from,
.fade-up-leave-to {
  opacity: 0;
  transform: translateX(-50%) translateY(20px);
}
</style>
