<script setup>
import { computed } from 'vue'

const props = defineProps({
  thought: {
    type: Object,
    required: true,
  },
  referenceTime: {
    type: Number,
    default: () => Date.now(),
  },
})

const confidencePercent = computed(() => {
  return Math.round((props.thought.confidence || 0) * 100)
})

const formattedTime = computed(() => {
  const raw = props.thought.created_at_ms
           || props.thought.updated_at_ms
           || props.thought.timestamp_ms

  let ts = Number(raw)
  if (!ts || ts <= 0) return ''

  if (ts < 1e12) {
    ts = ts * 1000
  }

  const date = new Date(ts)
  const diff = props.referenceTime - date

  if (diff < -14400000) return 'future?'
  if (diff < 60000) return 'just now'
  if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`
  if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`
  return `${Math.floor(diff / 86400000)}d ago`
})
</script>

<template>
  <div class="thought-card">
    <div class="thought-content">
      {{ thought.object }}
    </div>

    <div class="thought-footer">
      <div class="confidence" v-if="confidencePercent > 0">
        <div
          class="confidence-bar"
          :style="{ width: confidencePercent + '%' }"
        ></div>
        <span class="confidence-label">{{ confidencePercent }}%</span>
      </div>
      <span class="thought-time">{{ formattedTime }}</span>
    </div>
  </div>
</template>

<style scoped>
.thought-card {
  background: var(--bg-secondary);
  border-radius: var(--border-radius);
  padding: var(--space-sm);
  margin-bottom: var(--space-xs);
  border-left: 3px solid #6ba8a4;
  transition: all var(--transition-fast);
}

.thought-card:hover {
  background: var(--bg-tertiary);
}

.thought-content {
  font-size: var(--text-sm);
  color: var(--text-primary);
  line-height: var(--leading-relaxed);
  margin-bottom: var(--space-xs);
  word-break: break-word;
  font-style: italic;
}

.thought-footer {
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
  max-width: 100px;
}

.confidence-bar {
  height: 3px;
  background: #6ba8a4;
  border-radius: 2px;
  flex: 1;
  opacity: 0.6;
}

.confidence-label {
  font-size: 10px;
  font-family: var(--font-mono);
  color: var(--text-dim);
  min-width: 28px;
}

.thought-time {
  font-size: 10px;
  color: var(--text-dim);
}
</style>
