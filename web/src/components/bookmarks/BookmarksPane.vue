<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { bookmarks, tags as tagsApi } from '../../api/client.js'
import {
  registerReload,
  setBookmarkedIds,
  removeBookmarkedId,
} from '../../stores/appState.js'
import { onEvent } from '../../stores/eventBus.js'
import BookmarkCard from './BookmarkCard.vue'
import TagCircle from '../common/TagCircle.vue'

const emit = defineEmits(['jump-to'])

const items = ref([])
const allTags = ref([])
const isLoading = ref(false)
const searchQuery = ref('')
const filterTagIds = ref(new Set())

async function loadBookmarks() {
  isLoading.value = true
  try {
    const data = await bookmarks.list()
    items.value = data.bookmarks || []
    setBookmarkedIds(data.bookmarked_ids || [])
  } catch (e) {
    console.error('Failed to load bookmarks:', e)
  } finally {
    isLoading.value = false
  }
}

async function loadTags() {
  try {
    const data = await tagsApi.list()
    allTags.value = data.tags || []
  } catch (e) {
    console.error('Failed to load tags:', e)
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

function handleUpdate() {
  loadBookmarks()
}

function toggleFilterTag(tagId) {
  if (filterTagIds.value.has(tagId)) {
    filterTagIds.value.delete(tagId)
  } else {
    filterTagIds.value.add(tagId)
  }
  filterTagIds.value = new Set(filterTagIds.value)
}

function isFilterActive(tagId) {
  return filterTagIds.value.has(tagId)
}

const filteredItems = computed(() => {
  let result = items.value

  if (searchQuery.value) {
    const q = searchQuery.value.toLowerCase()
    result = result.filter(b => {
      const label = b.label || ''
      return label.toLowerCase().includes(q)
    })
  }

  if (filterTagIds.value.size > 0) {
    result = result.filter(b => {
      const bookmarkTags = b.tag_ids || []
      return bookmarkTags.some(tid => filterTagIds.value.has(tid))
    })
  }

  return result
})

let unregisterReload = null
let unsubscribeBookmarks = null
let unsubscribeTags = null

onMounted(() => {
  loadBookmarks()
  loadTags()
  unregisterReload = registerReload('bookmarks', loadBookmarks)
  unsubscribeBookmarks = onEvent('bookmarks_changed', loadBookmarks)
  unsubscribeTags = onEvent('tags_changed', loadTags)
})

onUnmounted(() => {
  if (unregisterReload) unregisterReload()
  if (unsubscribeBookmarks) unsubscribeBookmarks()
  if (unsubscribeTags) unsubscribeTags()
})
</script>

<template>
  <div class="bookmarks-pane">
    <div class="bookmarks-toolbar">
      <input
        v-model="searchQuery"
        type="text"
        placeholder="Search..."
        class="bookmarks-search"
      />
      <button @click="loadBookmarks" class="refresh-btn" title="Refresh">
        &#x21BB;
      </button>
    </div>

    <div class="tag-filter" v-if="allTags.length > 0">
      <span class="filter-label">Filter:</span>
      <div
        v-for="tag in allTags"
        :key="tag.id"
        class="filter-tag"
        :class="{ active: isFilterActive(tag.id) }"
        @click="toggleFilterTag(tag.id)"
        :title="tag.name"
      >
        <TagCircle :color="tag.color" :size="10" />
        <span class="filter-tag-name">{{ tag.name }}</span>
      </div>
    </div>

    <div class="bookmarks-list">
      <div v-if="isLoading" class="loading">Loading...</div>
      <div v-else-if="filteredItems.length === 0" class="empty">
        <p>No bookmarks yet</p>
        <p class="hint">Click the star on any message to save it here</p>
      </div>
      <BookmarkCard
        v-for="bookmark in filteredItems"
        :key="bookmark.id"
        :bookmark="bookmark"
        :all-tags="allTags"
        @click="handleJumpTo(bookmark.message_id)"
        @delete="deleteBookmark(bookmark.id, bookmark.message_id)"
        @update="handleUpdate"
      />
    </div>

    <div class="bookmarks-footer">
      {{ filteredItems.length }} / {{ items.length }} bookmarks
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
  gap: var(--space-xs);
  padding: var(--space-xs);
  background: var(--bg-secondary);
  border-bottom: var(--border-subtle);
}

.bookmarks-search {
  flex: 1;
  padding: var(--space-xs);
  font-size: var(--text-xs);
  background: var(--bg-primary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  color: var(--text-primary);
}

.bookmarks-search:focus {
  outline: none;
  border-color: var(--accent-primary);
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

.empty .hint {
  font-size: var(--text-xs);
  margin-top: var(--space-xs);
  opacity: 0.7;
}

.bookmarks-footer {
  padding: var(--space-xs);
  font-size: var(--text-xs);
  color: var(--text-dim);
  text-align: center;
  border-top: var(--border-subtle);
}

.tag-filter {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  padding: var(--space-xs);
  background: var(--bg-secondary);
  border-bottom: var(--border-subtle);
  flex-wrap: wrap;
}

.filter-label {
  font-size: var(--text-xs);
  color: var(--text-dim);
}

.filter-tag {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 2px 6px;
  border-radius: var(--border-radius-sm);
  cursor: pointer;
  transition: all var(--transition-fast);
  opacity: 0.5;
}

.filter-tag:hover {
  opacity: 0.8;
  background: var(--bg-hover);
}

.filter-tag.active {
  opacity: 1;
  background: var(--accent-glow);
}

.filter-tag-name {
  font-size: 10px;
  color: var(--text-secondary);
}
</style>
