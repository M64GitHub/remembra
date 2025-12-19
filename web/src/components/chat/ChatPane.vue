<script setup>
import { ref, onMounted, onUnmounted, nextTick } from 'vue'
import { chat, command, bookmarks } from '../../api/client.js'
import {
  appState,
  registerReload,
  reloadAllData,
  setBookmarkedIds,
} from '../../stores/appState.js'
import MessageList from './MessageList.vue'
import ChatInput from './ChatInput.vue'
import FloatingActions from './FloatingActions.vue'

const messages = ref([])
const isLoading = ref(false)
const isSending = ref(false)
const isStreaming = ref(false)
const hasMore = ref(true)
const error = ref(null)

let streamAbortController = null

function stopGeneration() {
  if (streamAbortController) {
    streamAbortController.abort()
    streamAbortController = null
  }
}

async function loadBookmarks() {
  try {
    const data = await bookmarks.list()
    setBookmarkedIds(data.bookmarked_ids || [])
  } catch (e) {
    console.error('Failed to load bookmarks:', e)
  }
}

async function loadMessages(before = null) {
  if (isLoading.value || (!hasMore.value && before)) return

  isLoading.value = true
  error.value = null

  try {
    const data = await chat.getMessages(50, before)
    const newMessages = data.messages || []

    if (before) {
      messages.value = [...newMessages, ...messages.value]
    } else {
      messages.value = newMessages
    }

    hasMore.value = data.has_more || false
  } catch (e) {
    error.value = e.message
    console.error('Failed to load messages:', e)
  } finally {
    isLoading.value = false
  }
}

async function loadMore() {
  if (messages.value.length === 0 || !hasMore.value) return
  const oldestId = messages.value[0]?.id
  if (oldestId) {
    await loadMessages(oldestId)
  }
}

async function sendMessage(text) {
  if (!text.trim() || isSending.value) return

  // Check for slash command
  if (text.startsWith('/')) {
    isSending.value = true
    appState.isChatBusy = true
    error.value = null
    let needsReload = false

    try {
      const data = await command.execute(text)
      console.log('[Chat] Command result:', data)

      // Show command output as system message
      if (data.output) {
        messages.value.push({
          id: Date.now(),
          role: 'system',
          content: data.output,
          created_at_ms: Date.now(),
        })
      }

      // Mark for reload after /db clear
      if (text.trim() === '/db clear') {
        needsReload = true
      }
    } catch (e) {
      error.value = e.message
      console.error('Command failed:', e)
    } finally {
      isSending.value = false
      appState.isChatBusy = false
    }

    // Trigger reload AFTER flags are cleared
    if (needsReload) {
      await reloadAllData()
    }
    return
  }

  // Regular chat message - use streaming
  isSending.value = true
  isStreaming.value = true
  appState.isChatBusy = true
  error.value = null

  const userMsgId = Date.now()
  messages.value.push({
    id: userMsgId,
    role: 'user',
    content: text,
    created_at_ms: userMsgId,
    pending: true,
  })

  const assistantMsgId = userMsgId + 1
  const reflectionMsgId = userMsgId + 2
  const streamStartTime = Date.now()
  messages.value.push({
    id: assistantMsgId,
    role: 'assistant',
    content: '',
    thinking: '',
    isThinking: true,
    created_at_ms: assistantMsgId,
    streaming: true,
    tokenCount: 0,
    liveTps: null,
  })

  await nextTick()

  streamAbortController = new AbortController()

  await chat.stream(
    text,
    streamAbortController.signal,
    // onChunk
    (chunk) => {
      // Handle message ID update event
      if (chunk.user_msg_id && chunk.assistant_msg_id) {
        const userIdx = messages.value.findIndex(m => m.id === userMsgId)
        if (userIdx >= 0) {
          messages.value[userIdx].id = chunk.user_msg_id
        }
        const assistantIdx = messages.value.findIndex(
          m => m.id === assistantMsgId
        )
        if (assistantIdx >= 0) {
          messages.value[assistantIdx].id = chunk.assistant_msg_id
        }
        return
      }

      const idx = messages.value.findIndex(m => m.id === assistantMsgId)
      if (idx >= 0) {
        const msg = messages.value[idx]
        if (chunk.content) {
          msg.content += chunk.content
          msg.isThinking = false
        }
        if (chunk.thinking) {
          msg.thinking = (msg.thinking || '') + chunk.thinking
          msg.isThinking = true
        }
        if (chunk.thinking || chunk.content) {
          msg.tokenCount = (msg.tokenCount || 0) + 1
          const elapsed = (Date.now() - streamStartTime) / 1000
          if (elapsed > 0) {
            msg.liveTps = (msg.tokenCount / elapsed).toFixed(1)
          }
        }
      }
    },
    // onComplete
    (final) => {
      // Mark user message as no longer pending
      const userIdx = messages.value.findIndex(m => m.id === userMsgId)
      if (userIdx >= 0) {
        messages.value[userIdx].pending = false
      }

      // Update assistant message with final stats
      const idx = messages.value.findIndex(m => m.id === assistantMsgId)
      if (idx >= 0) {
        const msg = messages.value[idx]
        msg.streaming = false
        msg.isThinking = false
        msg.liveTps = null
        if (!final.aborted) {
          msg.prompt_tokens = final.prompt_tokens
          msg.completion_tokens = final.completion_tokens
          msg.eval_duration_ms = final.eval_duration_ms
        }
      }

      isSending.value = false
      isStreaming.value = false
      streamAbortController = null

      // Only clear busy state if reflection is disabled
      if (!appState.reflectionEnabled) {
        appState.isChatBusy = false
      }
    },
    // onError
    (err) => {
      error.value = err.message
      console.error('Streaming failed:', err)

      const userIdx = messages.value.findIndex(m => m.id === userMsgId)
      if (userIdx >= 0) {
        messages.value[userIdx].error = true
      }

      const idx = messages.value.findIndex(m => m.id === assistantMsgId)
      if (idx >= 0) {
        messages.value[idx].streaming = false
        messages.value[idx].error = true
      }

      isSending.value = false
      isStreaming.value = false
      appState.isChatBusy = false
      streamAbortController = null
    },
    // onReflection
    (status) => {
      if (status === 'started') {
        messages.value.push({
          id: reflectionMsgId,
          role: 'reflection',
          content: 'Reflecting on conversation...',
          created_at_ms: Date.now(),
        })
      } else if (status === 'completed') {
        const idx = messages.value.findIndex(m => m.id === reflectionMsgId)
        if (idx >= 0) {
          messages.value.splice(idx, 1)
        }
        appState.isChatBusy = false
      }
    }
  )
}

let unregisterReload = null

onMounted(() => {
  loadMessages()
  loadBookmarks()

  // Register for persona change reloads
  unregisterReload = registerReload('chat', async () => {
    messages.value = []
    hasMore.value = true
    await loadMessages()
    await loadBookmarks()
  })
})

onUnmounted(() => {
  if (unregisterReload) unregisterReload()
})
</script>

<template>
  <div class="chat-pane">
    <div class="chat-error" v-if="error">
      <span class="error-icon">!</span>
      <span>{{ error }}</span>
      <button @click="error = null" class="error-dismiss">x</button>
    </div>

    <MessageList
      :messages="messages"
      :is-loading="isLoading"
      :has-more="hasMore"
      :is-sending="isSending"
      :is-streaming="isStreaming"
      :max-recent-messages="appState.maxRecentMessages"
      @load-more="loadMore"
    />

    <ChatInput
      :disabled="isSending"
      :is-streaming="isStreaming"
      @send="sendMessage"
      @stop="stopGeneration"
    />

    <FloatingActions :messages="messages" />
  </div>
</template>

<style scoped>
.chat-pane {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
}

.chat-error {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  padding: var(--space-sm) var(--space-md);
  background: var(--error-dim);
  color: var(--error);
  font-size: var(--text-sm);
}

.error-icon {
  width: 20px;
  height: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--error);
  color: var(--bg-deep);
  border-radius: 50%;
  font-weight: bold;
  font-size: var(--text-xs);
}

.error-dismiss {
  margin-left: auto;
  width: 20px;
  height: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--border-radius-sm);
  color: var(--error);
}

.error-dismiss:hover {
  background: rgba(248, 113, 113, 0.2);
}
</style>
