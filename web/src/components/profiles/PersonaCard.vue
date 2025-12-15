<script setup>
import { ref } from 'vue'

const props = defineProps({
  persona: {
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
  if (confirm(`Delete persona "${props.persona.name}"?`)) {
    emit('delete', props.persona.id)
  }
}

function formatConfidence(val) {
  return (val * 100).toFixed(0) + '%'
}
</script>

<template>
  <div class="persona-card" :class="{ active: isActive }">
    <div class="card-header">
      <span class="persona-name">{{ persona.name }}</span>
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

    <div class="card-summary">
      <div class="summary-row">
        <span class="ai-name">{{ persona.ai_name }}</span>
        <span class="tone">{{ persona.tone }}</span>
      </div>
    </div>

    <button
      class="details-toggle"
      @click="showDetails = !showDetails"
    >
      {{ showDetails ? 'Hide details' : 'Show details' }}
      <span class="toggle-icon">{{ showDetails ? '\u25B2' : '\u25BC' }}</span>
    </button>

    <div class="card-details" v-if="showDetails">
      <div class="details-section">
        <div class="section-title">LLM Parameters</div>
        <div class="params-grid">
          <div class="param-item">
            <span class="param-label">Chat</span>
            <span class="param-value">t={{ persona.llm_chat_temp }} max={{ persona.llm_chat_tokens }}</span>
          </div>
          <div class="param-item">
            <span class="param-label">Reflect</span>
            <span class="param-value">t={{ persona.llm_reflect_temp }} max={{ persona.llm_reflect_tokens }}</span>
          </div>
          <div class="param-item">
            <span class="param-label">Idle</span>
            <span class="param-value">t={{ persona.llm_idle_temp }} max={{ persona.llm_idle_tokens }}</span>
          </div>
          <div class="param-item">
            <span class="param-label">Episode</span>
            <span class="param-value">t={{ persona.llm_episode_temp }} max={{ persona.llm_episode_tokens }}</span>
          </div>
        </div>
      </div>

      <div class="details-section">
        <div class="section-title">Confidence Thresholds</div>
        <div class="conf-grid">
          <span class="conf-item">Notes: {{ formatConfidence(persona.conf_user_notes) }}</span>
          <span class="conf-item">Episodes: {{ formatConfidence(persona.conf_episodes) }}</span>
          <span class="conf-item">Idle: {{ formatConfidence(persona.conf_idle) }}</span>
          <span class="conf-item">Governor: {{ formatConfidence(persona.conf_governor) }}</span>
        </div>
      </div>
    </div>

    <div class="card-actions">
      <button
        class="edit-btn"
        @click="emit('edit', persona)"
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
.persona-card {
  background: var(--bg-secondary);
  border-radius: var(--border-radius);
  padding: var(--space-sm);
  border: var(--border-subtle);
  transition: all var(--transition-fast);
}

.persona-card:hover {
  border-color: var(--accent-primary);
}

.card-header {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  margin-bottom: var(--space-xs);
}

.persona-name {
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

.persona-card:hover .delete-btn {
  opacity: 1;
}

.delete-btn:hover {
  background: var(--error-dim);
  color: var(--error);
}

.card-summary {
  margin-bottom: var(--space-xs);
}

.summary-row {
  display: flex;
  gap: var(--space-sm);
  font-size: var(--text-xs);
}

.ai-name {
  color: var(--accent-primary);
  font-weight: 500;
}

.tone {
  color: var(--text-dim);
  font-style: italic;
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

.card-details {
  margin-top: var(--space-xs);
  padding-top: var(--space-xs);
  border-top: var(--border-subtle);
}

.details-section {
  margin-bottom: var(--space-xs);
}

.section-title {
  font-size: 9px;
  font-weight: 600;
  color: var(--text-dim);
  text-transform: uppercase;
  margin-bottom: 4px;
}

.params-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 2px;
}

.param-item {
  display: flex;
  gap: var(--space-xs);
  font-size: 10px;
}

.param-label {
  color: var(--text-dim);
  min-width: 45px;
}

.param-value {
  color: var(--text-secondary);
  font-family: var(--font-mono);
}

.conf-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 2px;
  font-size: 10px;
}

.conf-item {
  color: var(--text-secondary);
  font-family: var(--font-mono);
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
