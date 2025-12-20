<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { store, tags as tagsApi } from '../../api/client.js'
import { registerReload } from '../../stores/appState.js'
import { onEvent } from '../../stores/eventBus.js'
import StoreCard from './StoreCard.vue'
import StoreEditorModal from './StoreEditorModal.vue'
import TagCircle from '../common/TagCircle.vue'

const items = ref([])
const allTags = ref([])
const isLoading = ref(false)
const searchQuery = ref('')
const editingItem = ref(null)
const filterTagIds = ref(new Set())

async function loadItems() {
  isLoading.value = true
  try {
    const data = await store.list()
    items.value = data.items || []
  } catch (e) {
    console.error('Failed to load store items:', e)
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

function handleUpdate() {
  loadItems()
}

async function deleteItem(id) {
  try {
    await store.remove(id)
    items.value = items.value.filter(i => i.id !== id)
  } catch (e) {
    console.error('Failed to delete store item:', e)
  }
}

function openEditor(item) {
  editingItem.value = item
}

function closeEditor() {
  editingItem.value = null
}

async function saveItem(id, content) {
  try {
    await store.update(id, content)
    const idx = items.value.findIndex(i => i.id === id)
    if (idx >= 0) {
      items.value[idx] = { ...items.value[idx], content }
      editingItem.value = { ...items.value[idx] }
    }
  } catch (e) {
    console.error('Failed to save store item:', e)
  }
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
    result = result.filter(i => i.content.toLowerCase().includes(q))
  }

  if (filterTagIds.value.size > 0) {
    result = result.filter(i => {
      const itemTags = i.tag_ids || []
      return itemTags.some(tid => filterTagIds.value.has(tid))
    })
  }

  return result
})

let unregisterReload = null
let unsubscribeStore = null
let unsubscribeTags = null

onMounted(() => {
  loadItems()
  loadTags()
  unregisterReload = registerReload('store', loadItems)
  unsubscribeStore = onEvent('store_changed', loadItems)
  unsubscribeTags = onEvent('tags_changed', loadTags)
})

onUnmounted(() => {
  if (unregisterReload) unregisterReload()
  if (unsubscribeStore) unsubscribeStore()
  if (unsubscribeTags) unsubscribeTags()
})
</script>

<template>
  <div class="store-pane">
    <div class="store-toolbar">
      <input
        v-model="searchQuery"
        type="text"
        placeholder="Search..."
        class="store-search"
      />
      <button @click="loadItems" class="refresh-btn" title="Refresh">
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

    <div class="store-list">
      <div v-if="isLoading" class="loading">Loading...</div>
      <div v-else-if="filteredItems.length === 0" class="empty">
        No stored items
      </div>
      <StoreCard
        v-for="item in filteredItems"
        :key="item.id"
        :item="item"
        :all-tags="allTags"
        @click="openEditor(item)"
        @delete="deleteItem(item.id)"
        @update="handleUpdate"
      />
    </div>

    <div class="store-footer">
      {{ filteredItems.length }} / {{ items.length }} items
    </div>

    <StoreEditorModal
      v-if="editingItem"
      :item="editingItem"
      :all-tags="allTags"
      @close="closeEditor"
      @save="saveItem"
      @update="handleUpdate"
    />
  </div>
</template>

<style scoped>
.store-pane {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.store-toolbar {
  display: flex;
  gap: var(--space-xs);
  padding: var(--space-xs);
  background: var(--bg-secondary);
  border-bottom: var(--border-subtle);
}

.store-search {
  flex: 1;
  padding: var(--space-xs);
  font-size: var(--text-xs);
  background: var(--bg-primary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  color: var(--text-primary);
}

.store-search:focus {
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

.store-list {
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

.store-footer {
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
