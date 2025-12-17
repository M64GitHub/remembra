<script setup>
import { computed } from 'vue'

const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
})

const emit = defineEmits(['delete'])

const preview = computed(() => {
  const maxLen = 120
  const text = props.item.content || ''
  if (text.length <= maxLen) return text
  return text.substring(0, maxLen) + '...'
})

const formattedTime = computed(() => {
  const ts = props.item.updated_at_ms || props.item.created_at_ms
  if (!ts) return ''
  const date = new Date(ts)
  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  })
})

function handleDelete(event) {
  event.stopPropagation()
  emit('delete')
}
</script>

<template>
  <div class="store-card">
    <div class="card-header">
      <span class="card-id">#{{ item.id }}</span>
      <button
        class="delete-btn"
        @click="handleDelete"
        title="Delete"
      >&#x2715;</button>
    </div>
    <div class="card-content">{{ preview }}</div>
    <div class="card-footer">
      <span class="card-time">{{ formattedTime }}</span>
      <span v-if="item.source_msg_id" class="card-source">
        from msg #{{ item.source_msg_id }}
      </span>
    </div>
  </div>
</template>

<style scoped>
.store-card {
  padding: var(--space-sm);
  background: var(--bg-tertiary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  cursor: pointer;
  transition: all var(--transition-fast);
}

.store-card:hover {
  background: var(--bg-hover);
  border-color: var(--accent-primary);
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: var(--space-xs);
}

.card-id {
  font-size: var(--text-xs);
  font-family: var(--font-mono);
  color: var(--accent-primary);
  font-weight: 600;
}

.delete-btn {
  font-size: var(--text-xs);
  color: var(--text-dim);
  padding: 2px 4px;
  border-radius: var(--border-radius-sm);
  opacity: 0;
  transition: all var(--transition-fast);
}

.store-card:hover .delete-btn {
  opacity: 1;
}

.delete-btn:hover {
  background: var(--error-dim);
  color: var(--error);
}

.card-content {
  font-size: var(--text-xs);
  color: var(--text-secondary);
  line-height: var(--leading-relaxed);
  white-space: pre-wrap;
  word-break: break-word;
}

.card-footer {
  display: flex;
  justify-content: space-between;
  margin-top: var(--space-xs);
  font-size: 10px;
  color: var(--text-dim);
}

.card-source {
  font-family: var(--font-mono);
}
</style>
