<script setup>
import { computed } from 'vue'

const props = defineProps({
  memory: {
    type: Object,
    required: true,
  },
})

const emit = defineEmits(['delete'])

const typeColors = {
  fact: 'var(--memory-fact)',
  preference: 'var(--memory-preference)',
  note: 'var(--memory-note)',
  episode: 'var(--memory-episode)',
  project: 'var(--memory-project)',
  thought: 'var(--event-thought)',
}

const typeColor = computed(() => {
  const subj = props.memory.subject?.toLowerCase() || ''
  const pred = props.memory.predicate?.toLowerCase() || ''

  if (subj === 'self' && pred === 'thought') return typeColors.thought
  if (pred === 'episode' || pred === 'summary') return typeColors.episode
  if (pred.includes('prefer') || pred.includes('like')) return typeColors.preference
  if (pred.includes('project') || pred.includes('work')) return typeColors.project
  if (pred === 'note' || pred === 'remember') return typeColors.note
  return typeColors.fact
})

const typeLabel = computed(() => {
  const subj = props.memory.subject?.toLowerCase() || ''
  const pred = props.memory.predicate?.toLowerCase() || ''

  if (subj === 'self' && pred === 'thought') return 'thought'
  if (pred === 'episode' || pred === 'summary') return 'episode'
  if (pred.includes('prefer') || pred.includes('like')) return 'pref'
  if (pred.includes('project') || pred.includes('work')) return 'project'
  if (pred === 'note' || pred === 'remember') return 'note'
  return 'fact'
})

const confidencePercent = computed(() => {
  return Math.round((props.memory.confidence || 0) * 100)
})

const formattedTime = computed(() => {
  // Try multiple possible field names
  const raw = props.memory.updated_at_ms
           || props.memory.created_at_ms
           || props.memory.updated_at
           || props.memory.created_at
           || props.memory.timestamp_ms
           || props.memory.timestamp

  let ts = Number(raw)
  if (!ts || ts <= 0) return ''

  // Detect seconds vs milliseconds (timestamps before 2001 in ms are likely seconds)
  if (ts < 1e12) {
    ts = ts * 1000
  }

  const date = new Date(ts)
  const now = new Date()
  const diff = now - date

  console.log('[MemoryCard] raw:', raw, 'ts:', ts, 'diff:', diff, 'keys:', Object.keys(props.memory))

  // Allow 4 hour clock skew (server/browser timezone mismatch)
  if (diff < -14400000) return 'future?'
  if (diff < 60000) return 'just now'
  if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`
  if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`
  return `${Math.floor(diff / 86400000)}d ago`
})

function handleDelete() {
  if (confirm(`Delete memory "${props.memory.subject}.${props.memory.predicate}"?`)) {
    emit('delete', props.memory.id)
  }
}
</script>

<template>
  <div class="memory-card" :class="{ inactive: !memory.is_active }">
    <div class="card-header">
      <span
        class="type-badge"
        :style="{ backgroundColor: typeColor }"
      >
        {{ typeLabel }}
      </span>
      <span class="memory-key">
        {{ memory.subject }}.{{ memory.predicate }}
      </span>
      <button
        class="delete-btn"
        @click.stop="handleDelete"
        title="Delete"
      >
        &times;
      </button>
    </div>

    <div class="card-content">
      {{ memory.object }}
    </div>

    <div class="card-footer">
      <div class="confidence">
        <div
          class="confidence-bar"
          :style="{ width: confidencePercent + '%' }"
        ></div>
        <span class="confidence-label">{{ confidencePercent }}%</span>
      </div>
      <span class="updated-time">{{ formattedTime }}</span>
    </div>
  </div>
</template>

<style scoped>
.memory-card {
  background: var(--bg-secondary);
  border-radius: var(--border-radius);
  padding: var(--space-sm);
  margin-bottom: var(--space-xs);
  border: var(--border-subtle);
  transition: all var(--transition-fast);
}

.memory-card:hover {
  border-color: var(--accent-primary);
}

.memory-card.inactive {
  opacity: 0.5;
}

.card-header {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  margin-bottom: var(--space-xs);
}

.type-badge {
  padding: 1px 6px;
  border-radius: 3px;
  font-size: 9px;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--bg-deep);
}

.memory-key {
  flex: 1;
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  color: var(--text-secondary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
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

.memory-card:hover .delete-btn {
  opacity: 1;
}

.delete-btn:hover {
  background: var(--error-dim);
  color: var(--error);
}

.card-content {
  font-size: var(--text-sm);
  color: var(--text-primary);
  line-height: var(--leading-normal);
  margin-bottom: var(--space-xs);
  word-break: break-word;
}

.card-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-sm);
}

.confidence {
  flex: 1;
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  max-width: 120px;
}

.confidence-bar {
  height: 4px;
  background: var(--accent-primary);
  border-radius: 2px;
  flex: 1;
}

.confidence-label {
  font-size: 10px;
  font-family: var(--font-mono);
  color: var(--text-dim);
  min-width: 28px;
}

.updated-time {
  font-size: 10px;
  color: var(--text-dim);
}
</style>
