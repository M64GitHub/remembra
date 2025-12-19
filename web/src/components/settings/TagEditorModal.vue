<script setup>
import { ref, onMounted } from 'vue'
import { tags as tagsApi } from '../../api/client.js'
import TagCircle from '../common/TagCircle.vue'

const emit = defineEmits(['close'])

const tagList = ref([])
const loading = ref(true)
const newTagName = ref('')
const selectedColor = ref('#ef4444')
const editingTag = ref(null)
const editName = ref('')
const editColor = ref('')

const colorPalette = [
  '#ef4444', '#f97316', '#eab308', '#22c55e', '#14b8a6',
  '#3b82f6', '#8b5cf6', '#ec4899', '#6b7280', '#a78bfa',
]

async function loadTags() {
  loading.value = true
  try {
    const data = await tagsApi.list()
    tagList.value = data.tags || []
  } catch (e) {
    console.error('Failed to load tags:', e)
  } finally {
    loading.value = false
  }
}

async function createTag() {
  if (!newTagName.value.trim()) return
  try {
    await tagsApi.create(newTagName.value.trim(), selectedColor.value)
    newTagName.value = ''
    await loadTags()
  } catch (e) {
    console.error('Failed to create tag:', e)
  }
}

function startEdit(tag) {
  editingTag.value = tag.id
  editName.value = tag.name
  editColor.value = tag.color
}

function cancelEdit() {
  editingTag.value = null
  editName.value = ''
  editColor.value = ''
}

async function saveEdit(tag) {
  if (!editName.value.trim()) return
  try {
    await tagsApi.update(tag.id, editName.value.trim(), editColor.value)
    editingTag.value = null
    await loadTags()
  } catch (e) {
    console.error('Failed to update tag:', e)
  }
}

async function deleteTag(tag) {
  if (!confirm(`Delete tag "${tag.name}"?`)) return
  try {
    await tagsApi.remove(tag.id)
    await loadTags()
  } catch (e) {
    console.error('Failed to delete tag:', e)
  }
}

onMounted(loadTags)
</script>

<template>
  <div class="modal-overlay" @click.self="emit('close')">
    <div class="modal-container">
      <div class="modal-header">
        <h2>Manage Tags</h2>
        <button class="close-btn" @click="emit('close')">&#x2715;</button>
      </div>

      <div class="modal-body">
        <div class="tag-list" v-if="!loading">
          <div
            v-for="tag in tagList"
            :key="tag.id"
            class="tag-item"
          >
            <template v-if="editingTag === tag.id">
              <div class="edit-row">
                <TagCircle :color="editColor" :size="12" />
                <input
                  v-model="editName"
                  class="edit-input"
                  @keyup.enter="saveEdit(tag)"
                  @keyup.escape="cancelEdit"
                />
                <div class="color-picker-mini">
                  <button
                    v-for="c in colorPalette"
                    :key="c"
                    class="color-btn"
                    :class="{ selected: editColor === c }"
                    :style="{ backgroundColor: c }"
                    @click="editColor = c"
                  ></button>
                </div>
                <button class="action-btn save" @click="saveEdit(tag)">
                  Save
                </button>
                <button class="action-btn cancel" @click="cancelEdit">
                  Cancel
                </button>
              </div>
            </template>
            <template v-else>
              <TagCircle :color="tag.color" :size="12" />
              <span class="tag-name">{{ tag.name }}</span>
              <div class="tag-actions">
                <button class="action-btn" @click="startEdit(tag)">
                  Edit
                </button>
                <button
                  class="action-btn delete"
                  @click="deleteTag(tag)"
                >
                  Delete
                </button>
              </div>
            </template>
          </div>

          <div v-if="tagList.length === 0" class="empty-state">
            No tags yet. Create one below.
          </div>
        </div>

        <div v-else class="loading">Loading...</div>

        <div class="add-tag-section">
          <h3>Add New Tag</h3>
          <div class="add-tag-form">
            <input
              v-model="newTagName"
              placeholder="Tag name"
              class="tag-input"
              @keyup.enter="createTag"
            />
            <div class="color-picker">
              <button
                v-for="c in colorPalette"
                :key="c"
                class="color-btn"
                :class="{ selected: selectedColor === c }"
                :style="{ backgroundColor: c }"
                @click="selectedColor = c"
              ></button>
            </div>
            <button
              class="create-btn"
              @click="createTag"
              :disabled="!newTagName.trim()"
            >
              Create Tag
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.7);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: var(--z-modal);
}

.modal-container {
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-lg);
  width: 90%;
  max-width: 480px;
  max-height: 80vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: var(--space-md) var(--space-lg);
  border-bottom: var(--border-subtle);
}

.modal-header h2 {
  margin: 0;
  font-size: var(--text-base);
  font-weight: 600;
  color: var(--text-primary);
}

.close-btn {
  width: 28px;
  height: 28px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  border: none;
  color: var(--text-muted);
  cursor: pointer;
  border-radius: var(--border-radius-sm);
  transition: all var(--transition-fast);
}

.close-btn:hover {
  background: var(--bg-hover);
  color: var(--text-primary);
}

.modal-body {
  padding: var(--space-lg);
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: var(--space-lg);
}

.tag-list {
  display: flex;
  flex-direction: column;
  gap: var(--space-xs);
}

.tag-item {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  padding: var(--space-xs) var(--space-sm);
  background: var(--bg-tertiary);
  border-radius: var(--border-radius-sm);
}

.tag-name {
  flex: 1;
  font-size: var(--text-sm);
  color: var(--text-primary);
}

.tag-actions {
  display: flex;
  gap: var(--space-xs);
}

.action-btn {
  padding: 2px 8px;
  font-size: 10px;
  background: var(--bg-hover);
  border: none;
  border-radius: var(--border-radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  transition: all var(--transition-fast);
}

.action-btn:hover {
  background: var(--accent-primary);
  color: white;
}

.action-btn.delete:hover {
  background: var(--error);
}

.action-btn.save {
  background: var(--success);
  color: var(--bg-deep);
}

.action-btn.cancel {
  background: var(--bg-hover);
}

.edit-row {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  flex: 1;
  flex-wrap: wrap;
}

.edit-input {
  flex: 1;
  min-width: 80px;
  padding: 2px 6px;
  font-size: var(--text-sm);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  color: var(--text-primary);
}

.edit-input:focus {
  outline: none;
  border-color: var(--accent-primary);
}

.color-picker-mini {
  display: flex;
  gap: 2px;
}

.color-picker-mini .color-btn {
  width: 14px;
  height: 14px;
}

.empty-state {
  text-align: center;
  color: var(--text-muted);
  font-size: var(--text-sm);
  padding: var(--space-lg);
}

.loading {
  text-align: center;
  color: var(--text-muted);
  font-size: var(--text-sm);
  padding: var(--space-lg);
}

.add-tag-section {
  border-top: var(--border-subtle);
  padding-top: var(--space-lg);
}

.add-tag-section h3 {
  margin: 0 0 var(--space-sm) 0;
  font-size: var(--text-sm);
  font-weight: 500;
  color: var(--text-secondary);
}

.add-tag-form {
  display: flex;
  flex-direction: column;
  gap: var(--space-sm);
}

.tag-input {
  padding: var(--space-xs) var(--space-sm);
  font-size: var(--text-sm);
  background: var(--bg-tertiary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  color: var(--text-primary);
}

.tag-input:focus {
  outline: none;
  border-color: var(--accent-primary);
}

.color-picker {
  display: flex;
  gap: var(--space-xs);
  flex-wrap: wrap;
}

.color-btn {
  width: 24px;
  height: 24px;
  border-radius: 50%;
  border: 2px solid transparent;
  cursor: pointer;
  transition: all var(--transition-fast);
}

.color-btn:hover {
  transform: scale(1.1);
}

.color-btn.selected {
  border-color: var(--text-primary);
  box-shadow: 0 0 0 2px var(--bg-secondary);
}

.create-btn {
  padding: var(--space-xs) var(--space-md);
  background: var(--accent-primary);
  color: white;
  border: none;
  border-radius: var(--border-radius-sm);
  font-size: var(--text-sm);
  font-weight: 500;
  cursor: pointer;
  transition: all var(--transition-fast);
}

.create-btn:hover:not(:disabled) {
  background: var(--accent-secondary);
}

.create-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
</style>
