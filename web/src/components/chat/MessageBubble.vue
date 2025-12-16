<script setup>
import { computed, ref, onMounted, onUnmounted } from 'vue'
import { appState } from '../../stores/appState.js'
import { useMarkdown } from '../../composables/useMarkdown.js'

const { renderMarkdown } = useMarkdown()

const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
  inContext: {
    type: Boolean,
    default: true,
  },
})

const showTimestamp = ref(false)
const copied = ref(false)
const bubbleRef = ref(null)
const mdEnabled = ref(true)

const isUser = computed(() => props.message.role === 'user')
const isSystem = computed(() => props.message.role === 'system')
const isAssistant = computed(() => !isUser.value && !isSystem.value)

const renderedContent = computed(() => {
  if (!isSystem.value) {
    return renderMarkdown(props.message.content)
  }
  return null
})

const formattedStats = computed(() => {
  const pt = props.message.prompt_tokens
  const ct = props.message.completion_tokens
  const ms = props.message.eval_duration_ms

  if (!pt && !ct && !ms) return null

  const parts = []
  if (pt != null && ct != null) {
    parts.push(`${pt} in / ${ct} out`)
  } else if (ct != null) {
    parts.push(`${ct} tokens`)
  }

  if (ms != null) {
    const secs = (ms / 1000).toFixed(1)
    parts.push(`${secs}s`)
  }

  return parts.join(' | ')
})

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

function toggleMarkdown(event) {
  event.stopPropagation()
  mdEnabled.value = !mdEnabled.value
}

function handleCodeCopy(event) {
  const btn = event.target.closest('.md-code-copy')
  if (!btn) return

  event.stopPropagation()
  const code = decodeURIComponent(btn.dataset.code)

  navigator.clipboard.writeText(code).then(() => {
    btn.textContent = 'Copied!'
    btn.classList.add('copied')
    setTimeout(() => {
      btn.textContent = 'Copy'
      btn.classList.remove('copied')
    }, 2000)
  })
}

onMounted(() => {
  if (bubbleRef.value) {
    bubbleRef.value.addEventListener('click', handleCodeCopy)
  }
})

onUnmounted(() => {
  if (bubbleRef.value) {
    bubbleRef.value.removeEventListener('click', handleCodeCopy)
  }
})
</script>

<template>
  <div
    ref="bubbleRef"
    class="message-bubble"
    :class="{
      user: isUser,
      assistant: isAssistant,
      system: isSystem,
      pending: message.pending,
      error: message.error,
      'out-of-context': !inContext,
    }"
    @click="showTimestamp = !showTimestamp"
  >
    <div class="message-header" v-if="!isUser">
      <span class="message-role">{{ isSystem ? 'SYSTEM' : appState.activeAiName }}</span>
      <button
        v-if="isAssistant"
        class="md-toggle"
        :class="{ disabled: !mdEnabled }"
        @click="toggleMarkdown"
        :title="mdEnabled ? 'Disable markdown' : 'Enable markdown'"
      >md</button>
      <span class="context-indicator" v-if="inContext" title="In context window">&#x25CB;</span>
    </div>
    <div class="message-header user-header" v-else>
      <button
        class="md-toggle"
        :class="{ disabled: !mdEnabled }"
        @click="toggleMarkdown"
        :title="mdEnabled ? 'Disable markdown' : 'Enable markdown'"
      >md</button>
      <span class="context-indicator" v-if="inContext" title="In context window">&#x25CB;</span>
    </div>

    <!-- Markdown rendered content for user and assistant -->
    <div
      v-if="!isSystem && renderedContent && mdEnabled"
      class="message-content markdown-content"
      v-html="renderedContent"
    ></div>

    <!-- Plain text for system messages or when markdown disabled -->
    <div v-else class="message-content">
      {{ message.content }}
    </div>

    <div class="message-footer" :class="{ visible: showTimestamp }">
      <span class="message-time">{{ formattedTime }}</span>
      <span v-if="isAssistant && formattedStats" class="message-stats">
        {{ formattedStats }}
      </span>
      <button
        class="copy-btn"
        @click.stop="copyContent"
        :title="copied ? 'Copied!' : 'Copy'"
      >
        {{ copied ? '&#x2713;' : '&#x29C9;' }}
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

.message-bubble.out-of-context {
  opacity: 0.6;
}

.message-bubble.error {
  border-color: var(--error);
  background: var(--error-dim);
}

.message-bubble:hover {
  transform: translateY(-1px);
}

.message-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: var(--space-xs);
}

.message-header.user-header {
  justify-content: flex-end;
  margin-bottom: 0;
}

.context-indicator {
  font-size: var(--text-xs);
  color: var(--accent-primary);
  opacity: 0.7;
}

.user .context-indicator {
  color: rgba(255, 255, 255, 0.7);
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
  color: var(--text-muted);
}

.user .message-time {
  color: rgba(255, 255, 255, 0.6);
}

.message-stats {
  font-size: var(--text-xs);
  font-family: var(--font-mono);
  color: var(--text-dim);
  padding: 0 var(--space-sm);
  border-left: 1px solid rgba(255, 255, 255, 0.1);
  border-right: 1px solid rgba(255, 255, 255, 0.1);
}

.copy-btn {
  font-size: var(--text-sm);
  padding: 2px 6px;
  border-radius: var(--border-radius-sm);
  color: var(--text-muted);
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

.md-toggle {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  padding: 1px 4px;
  border-radius: var(--border-radius-sm);
  color: var(--text-dim);
  background: transparent;
  border: 1px solid transparent;
  cursor: pointer;
  opacity: 0;
  transition: all var(--transition-fast);
  text-transform: lowercase;
}

.message-bubble:hover .md-toggle,
.md-toggle.disabled {
  opacity: 1;
}

.md-toggle:hover {
  color: var(--text-secondary);
  background: var(--bg-tertiary);
  border-color: rgba(255, 255, 255, 0.1);
}

.md-toggle.disabled {
  color: var(--warning);
  border-color: var(--warning);
  opacity: 0.8;
}

.user .md-toggle {
  color: rgba(255, 255, 255, 0.5);
}

.user .md-toggle:hover {
  color: white;
  background: rgba(255, 255, 255, 0.2);
  border-color: rgba(255, 255, 255, 0.3);
}

.user .md-toggle.disabled {
  color: var(--warning);
  border-color: var(--warning);
}
</style>
