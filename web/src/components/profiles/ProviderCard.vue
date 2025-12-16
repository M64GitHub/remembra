<script setup>
import { ref } from 'vue'

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

const emit = defineEmits(['activate', 'delete', 'edit'])
const showDetails = ref(false)

function handleDelete() {
  if (confirm(`Delete provider "${props.provider.name}"?`)) {
    emit('delete', props.provider.id)
  }
}

function formatSize(bytes) {
  if (!bytes || bytes === 0) return '-'
  const gb = bytes / (1024 * 1024 * 1024)
  if (gb >= 1) return gb.toFixed(1) + ' GB'
  const mb = bytes / (1024 * 1024)
  return mb.toFixed(0) + ' MB'
}

function formatDate(isoStr) {
  if (!isoStr) return '-'
  try {
    const d = new Date(isoStr)
    return d.toLocaleDateString()
  } catch {
    return isoStr.slice(0, 10)
  }
}

function truncateDigest(digest) {
  if (!digest) return '-'
  return digest.slice(0, 12) + '...'
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
      class="details-toggle"
      @click="showDetails = !showDetails"
    >
      {{ showDetails ? 'Hide details' : 'Show details' }}
      <span class="toggle-icon">{{ showDetails ? '\u25B2' : '\u25BC' }}</span>
    </button>

    <div class="extended-details" v-if="showDetails">
      <div class="detail-row">
        <span class="detail-label">Size</span>
        <span class="detail-value">{{ formatSize(provider.size) }}</span>
      </div>
      <div class="detail-row">
        <span class="detail-label">Modified</span>
        <span class="detail-value">{{ formatDate(provider.modified_at) }}</span>
      </div>
      <div class="detail-row">
        <span class="detail-label">Digest</span>
        <span class="detail-value" :title="provider.digest">
          {{ truncateDigest(provider.digest) }}
        </span>
      </div>
    </div>

    <div class="card-actions">
      <button
        class="edit-btn"
        @click="emit('edit', provider)"
        title="Edit"
      >
        Edit
      </button>
      <button
        v-if="!isActive"
        class="activate-btn"
        @click="emit('activate')"
      >
        Set Active
      </button>
    </div>
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

.details-toggle {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-xs);
  width: 100%;
  padding: 3px;
  background: transparent;
  color: var(--text-dim);
  font-size: 10px;
  transition: color var(--transition-fast);
}

.details-toggle:hover {
  color: var(--text-secondary);
}

.toggle-icon {
  font-size: 8px;
}

.extended-details {
  margin-top: var(--space-xs);
  padding-top: var(--space-xs);
  border-top: var(--border-subtle);
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

.card-actions {
  display: flex;
  gap: var(--space-xs);
  margin-top: var(--space-xs);
}

.edit-btn,
.activate-btn {
  flex: 1;
  padding: 4px 8px;
  background: var(--bg-tertiary);
  border-radius: var(--border-radius-sm);
  color: var(--text-secondary);
  font-size: var(--text-xs);
  transition: all var(--transition-fast);
}

.edit-btn:hover {
  background: var(--bg-tertiary);
  color: var(--text-primary);
  border: 1px solid var(--accent-primary);
}

.activate-btn:hover {
  background: var(--accent-primary);
  color: white;
}
</style>
