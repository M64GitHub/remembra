<script setup>
import { computed, ref, onMounted, onUnmounted } from 'vue'
import {
  appState,
  toggleMessageSelection,
  addBookmarkedId,
  removeBookmarkedId,
} from '../../stores/appState.js'
import { bookmarks } from '../../api/client.js'
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

const emit = defineEmits(['bookmark-changed'])

const showTimestamp = ref(false)
const showThinking = ref(false)
const copied = ref(false)
const bubbleRef = ref(null)
const mdEnabled = ref(true)

const isUser = computed(() => props.message.role === 'user')
const isSystem = computed(() => props.message.role === 'system')
const isAssistant = computed(() => !isUser.value && !isSystem.value)

const isSelected = computed(() =>
  appState.selectedMessageIds.has(props.message.id)
)

const isBookmarked = computed(() =>
  appState.bookmarkedMessageIds.has(props.message.id)
)

function handleSelectionClick(event) {
  event.stopPropagation()
  toggleMessageSelection(props.message.id)
}

async function toggleBookmark(event) {
  event.stopPropagation()
  try {
    if (isBookmarked.value) {
      await bookmarks.removeByMessage(props.message.id)
      removeBookmarkedId(props.message.id)
    } else {
      await bookmarks.createSingle(props.message.id)
      addBookmarkedId(props.message.id)
    }
    emit('bookmark-changed')
  } catch (e) {
    console.error('Bookmark toggle failed:', e)
  }
}

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
  <div class="message-row" :class="{ selected: isSelected, user: isUser }">
    <!-- Selection circle -->
    <button
      v-if="!isSystem"
      class="selection-circle"
      :class="{ filled: isSelected }"
      @click="handleSelectionClick"
      title="Select message"
    >
      <span v-if="isSelected">&#x2713;</span>
    </button>
    <div v-else class="selection-spacer"></div>

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
        bookmarked: isBookmarked,
      }"
      :data-message-id="message.id"
      @click="showTimestamp = !showTimestamp"
    >
      <!-- Assistant/System header -->
      <div class="message-header" v-if="!isUser">
        <span class="message-role">
          {{ isSystem ? 'SYSTEM' : appState.activeAiName }}
        </span>
        <div class="header-center" v-if="!isSystem">
          <button
            class="md-toggle"
            :class="{ disabled: !mdEnabled }"
            @click="toggleMarkdown"
            :title="mdEnabled ? 'Disable markdown' : 'Enable markdown'"
          >md</button>
          <button
            class="bookmark-btn"
            :class="{ active: isBookmarked }"
            @click="toggleBookmark"
            :title="isBookmarked ? 'Remove bookmark' : 'Add bookmark'"
          >{{ isBookmarked ? '★' : '☆' }}</button>
        </div>
        <span
          class="context-indicator"
          v-if="inContext && !isSystem"
          title="In context window"
        >&#x25CB;</span>
      </div>
      <!-- User header -->
      <div class="message-header user-header" v-if="isUser">
        <span class="header-spacer"></span>
        <div class="header-center">
          <button
            class="md-toggle"
            :class="{ disabled: !mdEnabled }"
            @click="toggleMarkdown"
            :title="mdEnabled ? 'Disable markdown' : 'Enable markdown'"
          >md</button>
          <button
            class="bookmark-btn"
            :class="{ active: isBookmarked }"
            @click="toggleBookmark"
            :title="isBookmarked ? 'Remove bookmark' : 'Add bookmark'"
          >{{ isBookmarked ? '★' : '☆' }}</button>
        </div>
        <span
          class="context-indicator"
          v-if="inContext"
          title="In context window"
        >&#x25CB;</span>
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

    <!-- Collapsible thinking section for CoT models -->
    <div v-if="isAssistant && message.thinking" class="thinking-section">
      <button
        class="thinking-toggle"
        @click.stop="showThinking = !showThinking"
      >
        {{ showThinking ? 'Hide thinking' : 'Show thinking' }}
        <span class="toggle-icon">{{ showThinking ? '\u25B2' : '\u25BC' }}</span>
      </button>
      <div v-if="showThinking" class="thinking-content">
        {{ message.thinking }}
      </div>
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
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  margin-bottom: var(--space-xs);
}

.message-header.user-header {
  margin-bottom: 0;
}

.message-header .message-role {
  justify-self: start;
}

.header-center {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  justify-self: center;
}

.message-header .context-indicator {
  justify-self: end;
}

.header-spacer {
  /* Empty spacer for left column in user messages */
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

.thinking-section {
  margin-top: var(--space-sm);
  border-top: var(--border-subtle);
  padding-top: var(--space-xs);
}

.thinking-toggle {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  color: var(--text-dim);
  font-size: 10px;
  background: transparent;
  border: none;
  cursor: pointer;
  padding: 2px 0;
  transition: color var(--transition-fast);
}

.thinking-toggle:hover {
  color: var(--text-secondary);
}

.toggle-icon {
  font-size: 8px;
}

.thinking-content {
  margin-top: var(--space-xs);
  color: var(--text-muted);
  font-size: var(--text-xs);
  font-style: italic;
  white-space: pre-wrap;
  line-height: var(--leading-relaxed);
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

.message-row {
  display: flex;
  align-items: flex-start;
  gap: var(--space-sm);
  width: 100%;
}

.message-row.user {
  flex-direction: row-reverse;
}

.message-row.selected .message-bubble {
  outline: 2px solid var(--accent-primary);
  outline-offset: 2px;
}

.selection-circle {
  width: 20px;
  height: 20px;
  min-width: 20px;
  border-radius: 50%;
  border: 2px solid var(--text-dim);
  background: transparent;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all var(--transition-fast);
  margin-top: var(--space-md);
  font-size: 10px;
}

.selection-circle:hover {
  border-color: var(--accent-primary);
}

.selection-circle.filled {
  background: var(--accent-primary);
  border-color: var(--accent-primary);
  color: white;
}

.selection-spacer {
  width: 20px;
  min-width: 20px;
}


.bookmark-btn {
  font-size: 14px;
  padding: 2px 4px;
  border-radius: var(--border-radius-sm);
  color: var(--text-dim);
  background: transparent;
  border: none;
  cursor: pointer;
  opacity: 0;
  transition: all var(--transition-fast);
}

.message-bubble:hover .bookmark-btn,
.bookmark-btn.active {
  opacity: 1;
}

.bookmark-btn:hover {
  color: var(--accent-primary);
  transform: scale(1.1);
}

.bookmark-btn.active {
  color: var(--accent-primary);
}

.user .bookmark-btn {
  color: rgba(255, 255, 255, 0.6);
}

.user .bookmark-btn:hover,
.user .bookmark-btn.active {
  color: white;
}

.message-bubble.bookmarked {
  border-left: 3px solid var(--accent-primary);
}

.message-bubble.user.bookmarked {
  border-right: 3px solid white;
  border-left: none;
}

@keyframes highlight-flash {
  0% { background-color: var(--accent-primary); opacity: 0.3; }
  100% { background-color: transparent; opacity: 1; }
}

.message-bubble.highlight-flash {
  animation: highlight-flash 2s ease-out;
}
</style>
