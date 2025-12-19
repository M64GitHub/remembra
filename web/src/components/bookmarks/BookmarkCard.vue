<script setup>
import { ref, computed } from 'vue'
import { bookmarks as bookmarksApi } from '../../api/client.js'
import TagCircle from '../common/TagCircle.vue'
import TagSelector from '../common/TagSelector.vue'

const props = defineProps({
  bookmark: {
    type: Object,
    required: true,
  },
  allTags: {
    type: Array,
    default: () => [],
  },
})

const emit = defineEmits(['delete', 'update'])

const isEditingLabel = ref(false)
const editLabelValue = ref('')
const showTagSelector = ref(false)

const displayLabel = computed(() => {
  if (props.bookmark.label) return props.bookmark.label
  return `Message #${props.bookmark.message_id}`
})

const formattedDate = computed(() => {
  const ts = props.bookmark.created_at_ms
  if (!ts) return ''
  const date = new Date(ts)
  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  })
})

const assignedTags = computed(() => {
  const tagIds = props.bookmark.tag_ids || []
  return props.allTags.filter(t => tagIds.includes(t.id))
})

const visibleTags = computed(() => assignedTags.value.slice(0, 5))
const overflowCount = computed(() =>
  Math.max(0, assignedTags.value.length - 5)
)

function startEditLabel() {
  editLabelValue.value = props.bookmark.label || ''
  isEditingLabel.value = true
}

async function saveLabel() {
  try {
    await bookmarksApi.updateLabel(props.bookmark.id, editLabelValue.value)
    emit('update')
  } catch (e) {
    console.error('Failed to update label:', e)
  }
  isEditingLabel.value = false
}

function cancelEditLabel() {
  isEditingLabel.value = false
}

async function handleTagUpdate(tagIds) {
  try {
    await bookmarksApi.setTags(props.bookmark.id, tagIds)
    emit('update')
  } catch (e) {
    console.error('Failed to update tags:', e)
  }
}

function handleDelete(event) {
  event.stopPropagation()
  emit('delete')
}
</script>

<template>
  <div class="bookmark-card">
    <div class="card-main">
      <span class="msg-label">Msg #{{ bookmark.message_id }}</span>
      <span class="date-label">{{ formattedDate }}</span>
    </div>

    <div class="card-label" v-if="!isEditingLabel" @click="startEditLabel">
      <span class="label-text">{{ displayLabel }}</span>
    </div>
    <div class="card-label-edit" v-else>
      <input
        v-model="editLabelValue"
        class="label-input"
        placeholder="Enter label..."
        @keyup.enter="saveLabel"
        @keyup.escape="cancelEditLabel"
        autofocus
      />
      <button class="label-btn save" @click="saveLabel">Save</button>
      <button class="label-btn" @click="cancelEditLabel">Cancel</button>
    </div>

    <div class="card-footer">
      <div class="tags-row">
        <TagCircle
          v-for="tag in visibleTags"
          :key="tag.id"
          :color="tag.color"
          :size="8"
          :title="tag.name"
        />
        <span v-if="overflowCount > 0" class="overflow-badge">
          +{{ overflowCount }}
        </span>
      </div>
      <div class="tag-add-wrapper">
        <button
          class="add-tag-btn"
          @click.stop="showTagSelector = !showTagSelector"
          title="Add tags"
        >+</button>
        <TagSelector
          v-if="showTagSelector"
          :selected-ids="bookmark.tag_ids || []"
          @update="handleTagUpdate"
          @close="showTagSelector = false"
        />
      </div>
    </div>

    <button
      class="delete-btn"
      @click="handleDelete"
      title="Remove bookmark"
    >&#x2715;</button>
  </div>
</template>

<style scoped>
.bookmark-card {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: var(--space-xs) var(--space-sm);
  background: var(--bg-tertiary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  cursor: pointer;
  transition: all var(--transition-fast);
  position: relative;
}

.bookmark-card:hover {
  background: var(--bg-hover);
  border-color: var(--accent-primary);
}

.card-main {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.msg-label {
  font-size: var(--text-xs);
  font-family: var(--font-mono);
  color: var(--accent-primary);
  font-weight: 600;
}

.date-label {
  font-size: 10px;
  color: var(--text-dim);
}

.card-label {
  padding: 2px 0;
}

.label-text {
  font-size: 10px;
  color: var(--text-muted);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.card-label-edit {
  display: flex;
  gap: var(--space-xs);
  align-items: center;
}

.label-input {
  flex: 1;
  padding: 2px 4px;
  font-size: 10px;
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  color: var(--text-primary);
}

.label-input:focus {
  outline: none;
  border-color: var(--accent-primary);
}

.label-btn {
  padding: 2px 6px;
  font-size: 9px;
  background: var(--bg-hover);
  border: none;
  border-radius: var(--border-radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
}

.label-btn.save {
  background: var(--accent-primary);
  color: white;
}

.card-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 2px;
}

.tags-row {
  display: flex;
  align-items: center;
  gap: 3px;
}

.overflow-badge {
  font-size: 8px;
  color: var(--text-dim);
  padding: 0 2px;
}

.tag-add-wrapper {
  position: relative;
}

.add-tag-btn {
  width: 16px;
  height: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--bg-hover);
  border: none;
  border-radius: var(--border-radius-sm);
  color: var(--text-secondary);
  font-size: 12px;
  cursor: pointer;
  transition: all var(--transition-fast);
  opacity: 0;
}

.bookmark-card:hover .add-tag-btn {
  opacity: 1;
}

.add-tag-btn:hover {
  background: var(--accent-primary);
  color: white;
}

.delete-btn {
  position: absolute;
  top: var(--space-xs);
  right: var(--space-xs);
  font-size: 10px;
  color: var(--text-dim);
  padding: 2px 4px;
  border-radius: var(--border-radius-sm);
  background: transparent;
  border: none;
  cursor: pointer;
  opacity: 0;
  transition: all var(--transition-fast);
}

.bookmark-card:hover .delete-btn {
  opacity: 1;
}

.delete-btn:hover {
  background: var(--error-dim);
  color: var(--error);
}
</style>
