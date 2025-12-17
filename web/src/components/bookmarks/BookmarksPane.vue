<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { bookmarks, chat } from '../../api/client.js'
import {
  registerReload,
  setBookmarkedIds,
  removeBookmarkedId,
} from '../../stores/appState.js'
import BookmarkCard from './BookmarkCard.vue'

const emit = defineEmits(['jump-to'])

const items = ref([])
const messageMap = ref({})
const isLoading = ref(false)

async function loadBookmarks() {
  isLoading.value = true
  try {
    const data = await bookmarks.list()
    items.value = data.bookmarks || []
    setBookmarkedIds(data.bookmarked_ids || [])

    // Load message previews for bookmarks
    await loadMessagePreviews()
  } catch (e) {
    console.error('Failed to load bookmarks:', e)
  } finally {
    isLoading.value = false
  }
}

async function loadMessagePreviews() {
  // Get unique message IDs
  const msgIds = items.value.map(b => b.message_id)
  if (msgIds.length === 0) return

  try {
    // Load messages that contain our bookmarked IDs
    const data = await chat.getMessages(200, null)
    const msgs = data.messages || []

    const map = {}
    for (const msg of msgs) {
      if (msgIds.includes(msg.id)) {
        map[msg.id] = msg
      }
    }
    messageMap.value = map
  } catch (e) {
    console.error('Failed to load message previews:', e)
  }
}

async function deleteBookmark(id, messageId) {
  try {
    await bookmarks.remove(id)
    items.value = items.value.filter(b => b.id !== id)
    removeBookmarkedId(messageId)
  } catch (e) {
    console.error('Failed to delete bookmark:', e)
  }
}

function handleJumpTo(messageId) {
  emit('jump-to', messageId)
}

let unregisterReload = null

onMounted(() => {
  loadBookmarks()
  unregisterReload = registerReload('bookmarks', loadBookmarks)
})

onUnmounted(() => {
  if (unregisterReload) unregisterReload()
})
</script>

<template>
  <div class="bookmarks-pane">
    <div class="bookmarks-toolbar">
      <span class="toolbar-label">Bookmarks</span>
      <button @click="loadBookmarks" class="refresh-btn" title="Refresh">
        &#x21BB;
      </button>
    </div>

    <div class="bookmarks-list">
      <div v-if="isLoading" class="loading">Loading...</div>
      <div v-else-if="items.length === 0" class="empty">
        No bookmarks yet
      </div>
      <BookmarkCard
        v-for="bookmark in items"
        :key="bookmark.id"
        :bookmark="bookmark"
        :message="messageMap[bookmark.message_id]"
        @click="handleJumpTo(bookmark.message_id)"
        @delete="deleteBookmark(bookmark.id, bookmark.message_id)"
      />
    </div>

    <div class="bookmarks-footer">
      {{ items.length }} bookmarks
    </div>
  </div>
</template>

<style scoped>
.bookmarks-pane {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.bookmarks-toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: var(--space-xs) var(--space-sm);
  background: var(--bg-secondary);
  border-bottom: var(--border-subtle);
}

.toolbar-label {
  font-size: var(--text-xs);
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.refresh-btn {
  padding: var(--space-xs);
  font-size: var(--text-sm);
  color: var(--text-muted);
  border-radius: var(--border-radius-sm);
}

.refresh-btn:hover {
  background: var(--bg-hover);
  color: var(--text-primary);
}

.bookmarks-list {
  flex: 1;
  overflow-y: auto;
  padding: var(--space-xs);
  display: flex;
  flex-direction: column;
  gap: var(--space-xs);
}

.loading,
.empty {
  padding: var(--space-md);
  text-align: center;
  color: var(--text-dim);
  font-size: var(--text-sm);
}

.bookmarks-footer {
  padding: var(--space-xs);
  font-size: var(--text-xs);
  color: var(--text-dim);
  text-align: center;
  border-top: var(--border-subtle);
}
</style>
