<script setup>
const props = defineProps({
  provider: {
    type: Object,
    required: true,
  },
  isActive: {
    type: Boolean,
    default: false,
  },
  canDelete: {
    type: Boolean,
    default: true,
  },
})

const emit = defineEmits(['activate', 'delete'])

function handleDelete() {
  if (confirm(`Delete provider "${props.provider.name}"?`)) {
    emit('delete', props.provider.name)
  }
}
</script>

<template>
  <div class="provider-card" :class="{ active: isActive }">
    <div class="card-header">
      <span class="provider-name">{{ provider.name }}</span>
      <span class="active-badge" v-if="isActive">active</span>
      <button
        v-if="canDelete"
        class="delete-btn"
        @click.stop="handleDelete"
        title="Delete"
      >
        &times;
      </button>
    </div>

    <div class="card-details">
      <div class="detail-row">
        <span class="detail-label">URL</span>
        <span class="detail-value">{{ provider.ollama_url }}</span>
      </div>
      <div class="detail-row">
        <span class="detail-label">Model</span>
        <span class="detail-value">{{ provider.model }}</span>
      </div>
    </div>

    <button
      v-if="!isActive"
      class="activate-btn"
      @click="emit('activate')"
    >
      Set Active
    </button>
  </div>
</template>

<style scoped>
.provider-card {
  background: var(--bg-secondary);
  border-radius: var(--border-radius);
  padding: var(--space-sm);
  border: var(--border-subtle);
  transition: all var(--transition-fast);
}

.provider-card:hover {
  border-color: var(--accent-primary);
}

.provider-card.active {
  border-color: var(--success);
  border-left: 3px solid var(--success);
}

.card-header {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  margin-bottom: var(--space-xs);
}

.provider-name {
  flex: 1;
  font-weight: 600;
  color: var(--text-primary);
  font-size: var(--text-sm);
}

.active-badge {
  padding: 1px 6px;
  background: var(--success);
  color: var(--bg-deep);
  border-radius: 3px;
  font-size: 9px;
  font-weight: 600;
  text-transform: uppercase;
}

.delete-btn {
  width: 20px;
  height: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--border-radius-sm);
  color: var(--text-dim);
  font-size: 16px;
  opacity: 0;
  transition: all var(--transition-fast);
}

.provider-card:hover .delete-btn {
  opacity: 1;
}

.delete-btn:hover {
  background: var(--error-dim);
  color: var(--error);
}

.card-details {
  margin-bottom: var(--space-xs);
}

.detail-row {
  display: flex;
  gap: var(--space-xs);
  font-size: var(--text-xs);
  margin-bottom: 2px;
}

.detail-label {
  color: var(--text-dim);
  min-width: 40px;
}

.detail-value {
  color: var(--text-secondary);
  font-family: var(--font-mono);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.activate-btn {
  width: 100%;
  padding: 4px 8px;
  background: var(--bg-tertiary);
  border-radius: var(--border-radius-sm);
  color: var(--text-secondary);
  font-size: var(--text-xs);
  transition: all var(--transition-fast);
}

.activate-btn:hover {
  background: var(--accent-primary);
  color: white;
}
</style>
