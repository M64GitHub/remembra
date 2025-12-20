<script setup>
import { ref, computed } from 'vue'
import { store as storeApi } from '../../api/client.js'
import TagCircle from '../common/TagCircle.vue'
import TagSelector from '../common/TagSelector.vue'

const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
  allTags: {
    type: Array,
    default: () => [],
  },
})

const emit = defineEmits(['delete', 'update'])

const showTagSelector = ref(false)

const preview = computed(() => {
  const maxLen = 120
  const text = props.item.content || ''
  if (text.length <= maxLen) return text
  return text.substring(0, maxLen) + '...'
})

const formattedTime = computed(() => {
  const ts = props.item.updated_at_ms || props.item.created_at_ms
  if (!ts) return ''
  const date = new Date(ts)
  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  })
})

const assignedTags = computed(() => {
  const tagIds = props.item.tag_ids || []
  return props.allTags.filter(t => tagIds.includes(t.id))
})

const visibleTags = computed(() => assignedTags.value.slice(0, 5))
const overflowCount = computed(() =>
  Math.max(0, assignedTags.value.length - 5)
)

async function handleTagUpdate(tagIds) {
  try {
    await storeApi.setTags(props.item.id, tagIds)
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
  <div class="store-card">
    <div class="card-header">
      <span class="card-id">#{{ item.id }}</span>
      <button
        class="delete-btn"
        @click="handleDelete"
        title="Delete"
      >&#x2715;</button>
    </div>
    <div class="card-content">{{ preview }}</div>
    <div class="card-footer">
      <div class="footer-left">
        <span class="card-time">{{ formattedTime }}</span>
        <span v-if="item.source_msg_id" class="card-source">
          from msg #{{ item.source_msg_id }}
        </span>
      </div>
      <div class="footer-right">
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
            :selected-ids="item.tag_ids || []"
            @update="handleTagUpdate"
            @close="showTagSelector = false"
          />
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.store-card {
  padding: var(--space-sm);
  background: var(--bg-tertiary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  cursor: pointer;
  transition: all var(--transition-fast);
}

.store-card:hover {
  background: var(--bg-hover);
  border-color: var(--accent-primary);
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: var(--space-xs);
}

.card-id {
  font-size: var(--text-xs);
  font-family: var(--font-mono);
  color: var(--accent-primary);
  font-weight: 600;
}

.delete-btn {
  font-size: var(--text-xs);
  color: var(--text-dim);
  padding: 2px 4px;
  border-radius: var(--border-radius-sm);
  opacity: 0;
  transition: all var(--transition-fast);
}

.store-card:hover .delete-btn {
  opacity: 1;
}

.delete-btn:hover {
  background: var(--error-dim);
  color: var(--error);
}

.card-content {
  font-size: var(--text-xs);
  color: var(--text-secondary);
  line-height: var(--leading-relaxed);
  white-space: pre-wrap;
  word-break: break-word;
  max-height: 5.5em;
  overflow: hidden;
}

.card-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: var(--space-xs);
  font-size: 10px;
  color: var(--text-dim);
}

.footer-left {
  display: flex;
  gap: var(--space-sm);
}

.footer-right {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
}

.card-source {
  font-family: var(--font-mono);
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

.store-card:hover .add-tag-btn {
  opacity: 1;
}

.add-tag-btn:hover {
  background: var(--accent-primary);
  color: white;
}
</style>
