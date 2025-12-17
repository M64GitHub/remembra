<script setup>
import { computed } from 'vue'

const props = defineProps({
  bookmark: {
    type: Object,
    required: true,
  },
  message: {
    type: Object,
    default: null,
  },
})

const emit = defineEmits(['delete'])

const preview = computed(() => {
  if (!props.message) return 'Loading...'
  const maxLen = 60
  const text = props.message.content || ''
  if (text.length <= maxLen) return text
  return text.substring(0, maxLen) + '...'
})

const formattedDate = computed(() => {
  const ts = props.bookmark.created_at_ms
  if (!ts) return ''
  const date = new Date(ts)
  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  })
})

const roleLabel = computed(() => {
  if (!props.message) return ''
  return props.message.role === 'user' ? 'You' : 'AI'
})

function handleDelete(event) {
  event.stopPropagation()
  emit('delete')
}
</script>

<template>
  <div class="bookmark-card">
    <div class="card-main">
      <span class="msg-label">Msg #{{ bookmark.message_id }}</span>
      <span class="date-label">{{ formattedDate }}</span>
    </div>
    <div class="card-preview">
      <span class="role-badge" :class="message?.role">{{ roleLabel }}</span>
      <span class="preview-text">{{ preview }}</span>
    </div>
    <button
      class="delete-btn"
      @click="handleDelete"
      title="Remove bookmark"
    >&#x2715;</button>
  </div>
</template>

<style scoped>
.bookmark-card {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: var(--space-xs) var(--space-sm);
  background: var(--bg-tertiary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  cursor: pointer;
  transition: all var(--transition-fast);
  position: relative;
}

.bookmark-card:hover {
  background: var(--bg-hover);
  border-color: var(--accent-primary);
}

.card-main {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.msg-label {
  font-size: var(--text-xs);
  font-family: var(--font-mono);
  color: var(--accent-primary);
  font-weight: 600;
}

.date-label {
  font-size: 10px;
  color: var(--text-dim);
}

.card-preview {
  display: flex;
  align-items: flex-start;
  gap: var(--space-xs);
}

.role-badge {
  font-size: 9px;
  padding: 1px 4px;
  border-radius: 2px;
  text-transform: uppercase;
  font-weight: 600;
  flex-shrink: 0;
}

.role-badge.user {
  background: var(--accent-primary);
  color: white;
}

.role-badge.assistant {
  background: var(--bg-secondary);
  color: var(--text-secondary);
  border: 1px solid var(--border-color);
}

.preview-text {
  font-size: 10px;
  color: var(--text-muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  flex: 1;
}

.delete-btn {
  position: absolute;
  top: var(--space-xs);
  right: var(--space-xs);
  font-size: 10px;
  color: var(--text-dim);
  padding: 2px 4px;
  border-radius: var(--border-radius-sm);
  opacity: 0;
  transition: all var(--transition-fast);
}

.bookmark-card:hover .delete-btn {
  opacity: 1;
}

.delete-btn:hover {
  background: var(--error-dim);
  color: var(--error);
}
</style>
