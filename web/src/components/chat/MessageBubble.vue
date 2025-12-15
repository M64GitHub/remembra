<script setup>
import { computed, ref } from 'vue'
import { appState } from '../../stores/appState.js'

const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
})

const showTimestamp = ref(false)
const copied = ref(false)

const isUser = computed(() => props.message.role === 'user')
const isSystem = computed(() => props.message.role === 'system')

const formattedTime = computed(() => {
  // Try multiple possible field names
  const raw = props.message.created_at_ms
           || props.message.timestamp_ms
           || props.message.timestamp
           || props.message.created_at

  let ts = Number(raw)
  if (!ts || ts <= 0) return 'no timestamp'

  // Detect seconds vs milliseconds (timestamps before 2001 in ms are likely seconds)
  if (ts < 1e12) {
    ts = ts * 1000
  }

  const date = new Date(ts)
  const now = new Date()
  const diff = now - date

  console.log('[Message] raw:', raw, 'ts:', ts, 'diff:', diff)

  // Allow 4 hour clock skew (server/browser timezone mismatch)
  if (diff < -14400000) return 'future?'
  if (diff < 60000) return 'just now'
  if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`
  if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`

  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
})

async function copyContent() {
  try {
    await navigator.clipboard.writeText(props.message.content)
    copied.value = true
    setTimeout(() => (copied.value = false), 2000)
  } catch (e) {
    console.error('Failed to copy:', e)
  }
}
</script>

<template>
  <div
    class="message-bubble"
    :class="{
      user: isUser,
      assistant: !isUser && !isSystem,
      system: isSystem,
      pending: message.pending,
      error: message.error,
    }"
    @click="showTimestamp = !showTimestamp"
  >
    <div class="message-header" v-if="!isUser">
      <span class="message-role">{{ isSystem ? 'SYSTEM' : appState.activeAiName }}</span>
    </div>

    <div class="message-content">
      {{ message.content }}
    </div>

    <div class="message-footer" :class="{ visible: showTimestamp }">
      <span class="message-time">{{ formattedTime }}</span>
      <button
        class="copy-btn"
        @click.stop="copyContent"
        :title="copied ? 'Copied!' : 'Copy'"
      >
        {{ copied ? '&#x2713;' : '&#x2398;' }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.message-bubble {
  max-width: 80%;
  padding: var(--space-md) var(--space-lg);
  border-radius: var(--border-radius-lg);
  position: relative;
  cursor: pointer;
  transition: all var(--transition-fast);
}

.message-bubble.user {
  align-self: flex-end;
  background: var(--accent-primary);
  color: white;
  border-bottom-right-radius: var(--border-radius-sm);
}

.message-bubble.assistant {
  align-self: flex-start;
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-bottom-left-radius: var(--border-radius-sm);
}

.message-bubble.system {
  align-self: center;
  max-width: 90%;
  background: var(--bg-tertiary);
  border: 1px solid var(--accent-primary);
  border-radius: var(--border-radius);
  font-family: var(--font-mono);
  font-size: var(--text-sm);
}

.message-bubble.system .message-role {
  color: var(--info);
}

.message-bubble.system .message-content {
  color: var(--text-secondary);
}

.message-bubble.pending {
  opacity: 0.7;
}

.message-bubble.error {
  border-color: var(--error);
  background: var(--error-dim);
}

.message-bubble:hover {
  transform: translateY(-1px);
}

.message-header {
  margin-bottom: var(--space-xs);
}

.message-role {
  font-size: var(--text-xs);
  font-weight: 600;
  color: var(--accent-primary);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.message-content {
  font-size: var(--text-base);
  line-height: var(--leading-relaxed);
  white-space: pre-wrap;
  word-break: break-word;
}

.message-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-sm);
  margin-top: var(--space-sm);
  height: 0;
  overflow: hidden;
  opacity: 0;
  transition: all var(--transition-fast);
}

.message-footer.visible,
.message-bubble:hover .message-footer {
  height: auto;
  opacity: 1;
  padding-top: var(--space-xs);
}

.message-time {
  font-size: var(--text-xs);
  color: var(--text-dim);
}

.user .message-time {
  color: rgba(255, 255, 255, 0.6);
}

.copy-btn {
  font-size: var(--text-sm);
  padding: 2px 6px;
  border-radius: var(--border-radius-sm);
  color: var(--text-dim);
  transition: all var(--transition-fast);
}

.copy-btn:hover {
  background: var(--bg-tertiary);
  color: var(--text-secondary);
}

.user .copy-btn {
  color: rgba(255, 255, 255, 0.6);
}

.user .copy-btn:hover {
  background: rgba(255, 255, 255, 0.2);
  color: white;
}
</style>
