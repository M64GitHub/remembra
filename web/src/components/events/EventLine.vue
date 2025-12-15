<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  event: {
    type: Object,
    required: true,
  },
})

const expanded = ref(false)

const timestamp = computed(() => {
  const date = new Date(props.event.timestamp_ms)
  return date.toLocaleTimeString('en-US', {
    hour12: false,
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
})

const kindLabel = computed(() => {
  const kind = props.event.kind || 'unknown'
  return kind.replace(/_/g, ' ')
})

const colorClass = computed(() => {
  return `color-${props.event.color || 'blue'}`
})
</script>

<template>
  <div
    class="event-line"
    :class="{ expanded }"
    @click="expanded = !expanded"
  >
    <span class="event-time">{{ timestamp }}</span>
    <span class="event-kind" :class="colorClass">{{ kindLabel }}</span>
    <span class="event-subject">{{ event.subject }}</span>

    <div class="event-details" v-if="expanded && event.details">
      {{ event.details }}
    </div>
  </div>
</template>

<style scoped>
.event-line {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: var(--space-xs);
  padding: 2px var(--space-xs);
  border-radius: var(--border-radius-sm);
  cursor: pointer;
  transition: background var(--transition-fast);
}

.event-line:hover {
  background: var(--bg-secondary);
}

.event-time {
  color: var(--text-dim);
  flex-shrink: 0;
}

.event-kind {
  padding: 1px 4px;
  border-radius: 2px;
  font-size: 9px;
  text-transform: uppercase;
  letter-spacing: 0.03em;
  flex-shrink: 0;
}

.event-kind.color-purple {
  background: rgba(167, 139, 250, 0.2);
  color: #a78bfa;
}

.event-kind.color-green {
  background: rgba(52, 211, 153, 0.2);
  color: #34d399;
}

.event-kind.color-orange {
  background: rgba(251, 191, 36, 0.2);
  color: #fbbf24;
}

.event-kind.color-yellow {
  background: rgba(252, 211, 77, 0.2);
  color: #fcd34d;
}

.event-kind.color-red {
  background: rgba(248, 113, 113, 0.2);
  color: #f87171;
}

.event-kind.color-blue {
  background: rgba(96, 165, 250, 0.2);
  color: #60a5fa;
}

.event-subject {
  color: var(--text-secondary);
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.event-details {
  width: 100%;
  margin-top: var(--space-xs);
  padding: var(--space-xs);
  background: var(--bg-tertiary);
  border-radius: var(--border-radius-sm);
  color: var(--text-muted);
  white-space: pre-wrap;
  word-break: break-word;
}
</style>
