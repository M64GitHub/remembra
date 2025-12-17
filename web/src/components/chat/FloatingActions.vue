<script setup>
import { computed } from 'vue'
import { appState, clearSelection } from '../../stores/appState.js'
import { store } from '../../api/client.js'

const props = defineProps({
  messages: {
    type: Array,
    default: () => [],
  },
})

const emit = defineEmits(['store-created'])

const selectionCount = computed(() => appState.selectedMessageIds.size)
const hasSelection = computed(() => selectionCount.value > 0)

async function copyToStore() {
  const selectedIds = Array.from(appState.selectedMessageIds)
  const selectedMsgs = props.messages.filter(m => selectedIds.includes(m.id))

  for (const msg of selectedMsgs) {
    try {
      await store.create(msg.content, msg.id)
    } catch (e) {
      console.error('Failed to store message:', e)
    }
  }

  clearSelection()
  emit('store-created')
}

function cancelSelection() {
  clearSelection()
}
</script>

<template>
  <Transition name="fade-up">
    <div v-if="hasSelection" class="floating-actions">
      <span class="selection-count">{{ selectionCount }} selected</span>
      <button
        class="action-btn store-btn"
        @click="copyToStore"
        title="Copy to Store"
      >S</button>
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
