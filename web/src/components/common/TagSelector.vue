<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { tags as tagsApi } from '../../api/client.js'
import TagCircle from './TagCircle.vue'

const props = defineProps({
  selectedIds: {
    type: Array,
    default: () => [],
  },
})

const emit = defineEmits(['update', 'close'])

const tagList = ref([])
const loading = ref(true)
const popoverRef = ref(null)

const localSelected = ref(new Set(props.selectedIds))

const isSelected = computed(() => (id) => localSelected.value.has(id))

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

function toggleTag(tagId) {
  if (localSelected.value.has(tagId)) {
    localSelected.value.delete(tagId)
  } else {
    localSelected.value.add(tagId)
  }
  localSelected.value = new Set(localSelected.value)
  emit('update', Array.from(localSelected.value))
}

function handleClickOutside(e) {
  if (popoverRef.value && !popoverRef.value.contains(e.target)) {
    emit('close')
  }
}

onMounted(() => {
  loadTags()
  setTimeout(() => {
    document.addEventListener('click', handleClickOutside)
  }, 0)
})

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside)
})
</script>

<template>
  <div class="tag-selector" ref="popoverRef" @click.stop>
    <div class="selector-header">Select Tags</div>
    <div class="tag-options" v-if="!loading">
      <div
        v-for="tag in tagList"
        :key="tag.id"
        class="tag-option"
        :class="{ selected: isSelected(tag.id) }"
        @click="toggleTag(tag.id)"
      >
        <TagCircle :color="tag.color" :size="10" />
        <span class="tag-label">{{ tag.name }}</span>
      </div>
      <div v-if="tagList.length === 0" class="empty-state">
        No tags available
      </div>
    </div>
    <div v-else class="loading">Loading...</div>
  </div>
</template>

<style scoped>
.tag-selector {
  position: absolute;
  top: 100%;
  right: 0;
  margin-top: 4px;
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  box-shadow: var(--shadow-md);
  min-width: 160px;
  max-width: 220px;
  z-index: var(--z-dropdown);
}

.selector-header {
  padding: var(--space-xs) var(--space-sm);
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--text-muted);
  border-bottom: var(--border-subtle);
}

.tag-options {
  padding: var(--space-xs);
  max-height: 200px;
  overflow-y: auto;
}

.tag-option {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  padding: var(--space-xs);
  border-radius: var(--border-radius-sm);
  cursor: pointer;
  transition: background var(--transition-fast);
}

.tag-option:hover {
  background: var(--bg-hover);
}

.tag-option.selected {
  background: var(--accent-glow);
}

.tag-label {
  font-size: var(--text-xs);
  color: var(--text-primary);
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.empty-state {
  padding: var(--space-sm);
  text-align: center;
  font-size: var(--text-xs);
  color: var(--text-muted);
}

.loading {
  padding: var(--space-sm);
  text-align: center;
  font-size: var(--text-xs);
  color: var(--text-muted);
}
</style>
