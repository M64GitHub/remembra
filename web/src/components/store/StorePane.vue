<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { store } from '../../api/client.js'
import { registerReload } from '../../stores/appState.js'
import { onEvent } from '../../stores/eventBus.js'
import StoreCard from './StoreCard.vue'
import StoreEditorModal from './StoreEditorModal.vue'

const items = ref([])
const isLoading = ref(false)
const searchQuery = ref('')
const editingItem = ref(null)

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
    }
    closeEditor()
  } catch (e) {
    console.error('Failed to save store item:', e)
  }
}

const filteredItems = computed(() => {
  if (!searchQuery.value) return items.value
  const q = searchQuery.value.toLowerCase()
  return items.value.filter(i => i.content.toLowerCase().includes(q))
})

let unregisterReload = null
let unsubscribeEvent = null

onMounted(() => {
  loadItems()
  unregisterReload = registerReload('store', loadItems)
  unsubscribeEvent = onEvent('store_changed', loadItems)
})

onUnmounted(() => {
  if (unregisterReload) unregisterReload()
  if (unsubscribeEvent) unsubscribeEvent()
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

    <div class="store-list">
      <div v-if="isLoading" class="loading">Loading...</div>
      <div v-else-if="filteredItems.length === 0" class="empty">
        No stored items
      </div>
      <StoreCard
        v-for="item in filteredItems"
        :key="item.id"
        :item="item"
        @click="openEditor(item)"
        @delete="deleteItem(item.id)"
      />
    </div>

    <div class="store-footer">
      {{ filteredItems.length }} / {{ items.length }} items
    </div>

    <StoreEditorModal
      v-if="editingItem"
      :item="editingItem"
      @close="closeEditor"
      @save="saveItem"
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
</style>
