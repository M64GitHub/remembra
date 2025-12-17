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
const hasMore = ref(true)
const error = ref(null)

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

  // Regular chat message
  isSending.value = true
  appState.isChatBusy = true
  error.value = null

  const msgId = Date.now()
  messages.value.push({
    id: msgId,
    role: 'user',
    content: text,
    created_at_ms: msgId,
    pending: true,
  })

  await nextTick()

  try {
    const data = await chat.send(text)

    // Update through reactive array to trigger re-render
    const userMsgIndex = messages.value.findIndex(m => m.id === msgId)
    if (userMsgIndex >= 0) {
      messages.value[userMsgIndex] = {
        ...messages.value[userMsgIndex],
        pending: false,
      }
    }

    messages.value.push({
      id: Date.now() + 1,
      role: 'assistant',
      content: data.message.content,
      created_at_ms: Date.now(),
      prompt_tokens: data.prompt_tokens,
      completion_tokens: data.completion_tokens,
      eval_duration_ms: data.eval_duration_ms,
      thinking: data.thinking,
    })
  } catch (e) {
    error.value = e.message
    // Update through reactive array
    const userMsgIndex = messages.value.findIndex(m => m.id === msgId)
    if (userMsgIndex >= 0) {
      messages.value[userMsgIndex] = {
        ...messages.value[userMsgIndex],
        error: true,
      }
    }
    console.error('Failed to send message:', e)
  } finally {
    isSending.value = false
    appState.isChatBusy = false
  }
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
      :max-recent-messages="appState.maxRecentMessages"
      @load-more="loadMore"
    />

    <ChatInput
      :disabled="isSending"
      @send="sendMessage"
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
