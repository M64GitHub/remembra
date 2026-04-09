<script setup>
import { ref, watch, nextTick, onMounted, onUnmounted, computed } from 'vue'
import MessageBubble from './MessageBubble.vue'

const props = defineProps({
  messages: {
    type: Array,
    required: true,
  },
  isLoading: Boolean,
  hasMore: Boolean,
  isSending: Boolean,
  isStreaming: Boolean,
  maxRecentMessages: {
    type: Number,
    default: 24,
  },
})

const inContextFlags = computed(() => {
  const total = props.messages.length
  const contextStart = Math.max(0, total - props.maxRecentMessages)
  return props.messages.map((_, index) => index >= contextStart)
})

const emit = defineEmits(['load-more'])

const listRef = ref(null)
const isAtBottom = ref(true)
const showScrollButton = ref(false)
let scrollInterval = null

function checkScroll() {
  if (!listRef.value) return
  const { scrollTop, scrollHeight, clientHeight } = listRef.value
  isAtBottom.value = scrollHeight - scrollTop - clientHeight < 50
  showScrollButton.value = !isAtBottom.value

  if (scrollTop < 100 && props.hasMore && !props.isLoading) {
    emit('load-more')
  }
}

function scrollToBottom(smooth = true) {
  if (!listRef.value) return
  listRef.value.scrollTo({
    top: listRef.value.scrollHeight,
    behavior: smooth ? 'smooth' : 'instant',
  })
}

watch(
  () => props.messages.length,
  async () => {
    await nextTick()
    if (isAtBottom.value) {
      scrollToBottom(false)
    }
  }
)

watch(
  () => props.isStreaming,
  (streaming) => {
    if (streaming) {
      scrollInterval = setInterval(() => {
        if (isAtBottom.value) {
          scrollToBottom(false)
        }
      }, 100)
    } else {
      if (scrollInterval) {
        clearInterval(scrollInterval)
        scrollInterval = null
      }
    }
  }
)

onMounted(() => {
  nextTick(() => scrollToBottom(false))
})

onUnmounted(() => {
  if (scrollInterval) {
    clearInterval(scrollInterval)
    scrollInterval = null
  }
})
</script>

<template>
  <div class="message-list" ref="listRef" @scroll="checkScroll">
    <div class="load-more" v-if="hasMore">
      <button
        v-if="!isLoading"
        @click="emit('load-more')"
        class="load-more-btn"
      >
        Load earlier messages
      </button>
      <div v-else class="loading-indicator">
        <span class="loading-dot"></span>
        <span class="loading-dot"></span>
        <span class="loading-dot"></span>
      </div>
    </div>

    <div class="messages-container">
      <MessageBubble
        v-for="(msg, index) in messages"
        :key="msg.id"
        :message="msg"
        :in-context="inContextFlags[index]"
      />
    </div>

    <div class="typing-indicator" v-if="isSending">
      <span class="typing-dot"></span>
      <span class="typing-dot"></span>
      <span class="typing-dot"></span>
    </div>

    <div class="empty-state" v-if="!isLoading && messages.length === 0">
      <div class="empty-icon">&#x1F4AD;</div>
      <p>No messages yet</p>
      <p class="hint">Type below to start a conversation</p>
    </div>

    <button
      v-if="showScrollButton"
      @click="scrollToBottom()"
      class="scroll-bottom-btn"
    >
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
           fill="none" stroke="currentColor" stroke-width="2"
           stroke-linecap="round" stroke-linejoin="round">
        <polyline points="6 9 12 15 18 9"/>
      </svg>
    </button>
  </div>
</template>

<style scoped>
.message-list {
  flex: 1;
  overflow-y: auto;
  overflow-x: hidden;
  padding: var(--space-lg);
  position: relative;
  display: flex;
  flex-direction: column;
}

.messages-container {
  display: flex;
  flex-direction: column;
  gap: var(--space-md);
}

.load-more {
  display: flex;
  justify-content: center;
  padding: var(--space-md);
  margin-bottom: var(--space-md);
}

.load-more-btn {
  padding: var(--space-xs) var(--space-md);
  font-size: var(--text-xs);
  color: var(--text-muted);
  background: var(--bg-secondary);
  border-radius: var(--border-radius);
  transition: all var(--transition-fast);
}

.load-more-btn:hover {
  background: var(--bg-tertiary);
  color: var(--text-secondary);
}

.loading-indicator,
.typing-indicator {
  display: flex;
  gap: 4px;
  justify-content: center;
  padding: var(--space-md);
}

.loading-dot,
.typing-dot {
  width: 8px;
  height: 8px;
  background: var(--accent-primary);
  border-radius: 50%;
  animation: bounce 1.4s ease-in-out infinite;
}

.loading-dot:nth-child(2),
.typing-dot:nth-child(2) {
  animation-delay: 0.2s;
}

.loading-dot:nth-child(3),
.typing-dot:nth-child(3) {
  animation-delay: 0.4s;
}

@keyframes bounce {
  0%, 80%, 100% {
    transform: translateY(0);
    opacity: 0.5;
  }
  40% {
    transform: translateY(-6px);
    opacity: 1;
  }
}

.empty-state {
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  text-align: center;
  color: var(--text-muted);
}

.empty-icon {
  font-size: 3rem;
  margin-bottom: var(--space-md);
  opacity: 0.5;
}

.empty-state p {
  margin: var(--space-xs) 0;
}

.empty-state .hint {
  font-size: var(--text-xs);
  opacity: 0.7;
}

.scroll-bottom-btn {
  position: sticky;
  bottom: var(--space-lg);
  align-self: flex-end;
  margin-top: auto;
  width: 36px;
  height: 36px;
  background: var(--bg-tertiary);
  border: var(--border-light);
  color: var(--text-secondary);
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: var(--shadow-md);
  transition: all var(--transition-fast);
  flex-shrink: 0;
}

.scroll-bottom-btn svg {
  width: 18px;
  height: 18px;
}

.scroll-bottom-btn:hover {
  background: var(--bg-elevated);
  color: var(--text-primary);
  border-color: var(--accent-primary);
  transform: scale(1.1);
}
</style>
