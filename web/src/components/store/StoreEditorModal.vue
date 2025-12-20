<script setup>
import { ref, computed, onMounted } from 'vue'
import { useMarkdown } from '../../composables/useMarkdown.js'
import { store as storeApi } from '../../api/client.js'
import TagCircle from '../common/TagCircle.vue'
import TagSelector from '../common/TagSelector.vue'

const { renderMarkdown } = useMarkdown()

const props = defineProps({
  item: { type: Object, required: true },
  allTags: { type: Array, default: () => [] },
})

const emit = defineEmits(['close', 'save', 'update'])

const content = ref('')
const viewMode = ref('split')
const copied = ref(false)
const saved = ref(false)
const showTagSelector = ref(false)
const localTagIds = ref([])

const renderedContent = computed(() => renderMarkdown(content.value))

const wordCount = computed(() => {
  const text = content.value.trim()
  if (!text) return 0
  return text.split(/\s+/).length
})

const charCount = computed(() => content.value.length)

const createdDate = computed(() => {
  const ts = props.item.created_at_ms
  if (!ts) return null
  return new Date(ts).toLocaleDateString(undefined, {
    year: 'numeric', month: 'short', day: 'numeric'
  })
})

const modifiedDate = computed(() => {
  const ts = props.item.updated_at_ms
  if (!ts || ts === props.item.created_at_ms) return null
  return new Date(ts).toLocaleDateString(undefined, {
    year: 'numeric', month: 'short', day: 'numeric'
  })
})

const assignedTags = computed(() => {
  return props.allTags.filter(t => localTagIds.value.includes(t.id))
})

onMounted(() => {
  content.value = props.item.content || ''
  localTagIds.value = props.item.tag_ids || []
})

function cycleViewMode() {
  if (viewMode.value === 'split') viewMode.value = 'edit'
  else if (viewMode.value === 'edit') viewMode.value = 'preview'
  else viewMode.value = 'split'
}

function handleSave() {
  emit('save', props.item.id, content.value)
  saved.value = true
  setTimeout(() => (saved.value = false), 2000)
}

function handleOverlayClick(event) {
  if (event.target === event.currentTarget) {
    emit('close')
  }
}

async function copyContent() {
  try {
    await navigator.clipboard.writeText(content.value)
    copied.value = true
    setTimeout(() => (copied.value = false), 2000)
  } catch (e) {
    console.error('Failed to copy:', e)
  }
}

function downloadMarkdown() {
  const blob = new Blob([content.value], { type: 'text/markdown' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `store-${props.item.id}.md`
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

async function handleTagUpdate(tagIds) {
  try {
    await storeApi.setTags(props.item.id, tagIds)
    localTagIds.value = tagIds
    emit('update')
  } catch (e) {
    console.error('Failed to update tags:', e)
  }
  showTagSelector.value = false
}
</script>

<template>
  <div class="modal-overlay" @click="handleOverlayClick">
    <div class="modal-content">
      <div class="modal-header">
        <div class="header-left">
          <h3>Stored Content</h3>
          <div class="header-meta">
            <span v-if="createdDate">Created: {{ createdDate }}</span>
            <span v-if="modifiedDate"> · Modified: {{ modifiedDate }}</span>
            <span v-if="item.source_msg_id" class="source-link">
              · from msg #{{ item.source_msg_id }}
            </span>
          </div>
        </div>
        <div class="header-actions">
          <button
            class="action-btn"
            @click="copyContent"
            :title="copied ? 'Copied!' : 'Copy to clipboard'"
          >{{ copied ? '&#x2713;' : '&#x29C9;' }}</button>
          <button
            class="view-mode-btn"
            @click="cycleViewMode"
            :title="`View: ${viewMode}`"
          >{{ viewMode === 'split' ? '⫿' : viewMode === 'edit' ? '✎' : 'md' }}</button>
          <button
            class="action-btn"
            @click="downloadMarkdown"
            title="Download as .md"
          >&#x2B73;</button>
          <button class="close-btn" @click="$emit('close')">&#x2715;</button>
        </div>
      </div>

      <div class="tags-bar">
        <div class="tags-display">
          <TagCircle
            v-for="tag in assignedTags"
            :key="tag.id"
            :color="tag.color"
            :size="10"
            :title="tag.name"
          />
          <span v-if="assignedTags.length === 0" class="no-tags">No tags</span>
        </div>
        <div class="tag-add-wrapper">
          <button
            class="add-tag-btn"
            @click.stop="showTagSelector = !showTagSelector"
            title="Manage tags"
          >+</button>
          <TagSelector
            v-if="showTagSelector"
            :selected-ids="localTagIds"
            @update="handleTagUpdate"
            @close="showTagSelector = false"
          />
        </div>
      </div>

      <div class="modal-body" :class="viewMode">
        <div
          v-if="viewMode !== 'preview'"
          class="editor-pane"
        >
          <div class="pane-label">Edit</div>
          <textarea
            v-model="content"
            class="content-editor"
            placeholder="Enter markdown content..."
          ></textarea>
        </div>
        <div
          v-if="viewMode !== 'edit'"
          class="preview-pane"
        >
          <div class="pane-label">Preview</div>
          <div
            class="content-view markdown-content"
            v-html="renderedContent"
          ></div>
        </div>
      </div>

      <div class="modal-footer">
        <div class="footer-stats">
          {{ wordCount }} words · {{ charCount }} characters
        </div>
        <div class="footer-actions">
          <button class="cancel-btn" @click="$emit('close')">Cancel</button>
          <button
            class="save-btn"
            :class="{ saved: saved }"
            @click="handleSave"
          >{{ saved ? 'Saved!' : 'Save' }}</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.6);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 200;
}

.modal-content {
  width: 90vw;
  max-width: 1400px;
  height: 90vh;
  background: var(--bg-primary);
  border-radius: var(--border-radius-lg);
  border: var(--border-subtle);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  padding: var(--space-md);
  border-bottom: var(--border-subtle);
}

.header-left {
  display: flex;
  flex-direction: column;
  gap: var(--space-xs);
}

.modal-header h3 {
  margin: 0;
  font-size: var(--text-base);
  color: var(--text-primary);
}

.header-meta {
  font-size: var(--text-xs);
  color: var(--text-dim);
}

.source-link {
  font-family: var(--font-mono);
  color: var(--accent-primary);
}

.header-actions {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
}

.action-btn {
  font-size: var(--text-sm);
  padding: 4px 8px;
  border-radius: var(--border-radius-sm);
  color: var(--text-muted);
  background: transparent;
  border: none;
  cursor: pointer;
  transition: all var(--transition-fast);
}

.action-btn:hover {
  background: var(--bg-hover);
  color: var(--text-primary);
}

.view-mode-btn {
  font-family: var(--font-mono);
  font-size: var(--text-sm);
  padding: 4px 8px;
  border-radius: var(--border-radius-sm);
  color: var(--accent-primary);
  background: var(--accent-glow);
  border: 1px solid var(--accent-primary);
  cursor: pointer;
  transition: all var(--transition-fast);
}

.view-mode-btn:hover {
  background: var(--accent-primary);
  color: white;
}

.close-btn {
  font-size: var(--text-sm);
  color: var(--text-muted);
  padding: var(--space-xs);
  border-radius: var(--border-radius-sm);
}

.close-btn:hover {
  background: var(--bg-hover);
  color: var(--text-primary);
}

.tags-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--space-sm) var(--space-md);
  background: var(--bg-secondary);
  border-bottom: var(--border-subtle);
}

.tags-display {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
}

.no-tags {
  font-size: var(--text-xs);
  color: var(--text-dim);
}

.tag-add-wrapper {
  position: relative;
}

.add-tag-btn {
  width: 24px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--bg-tertiary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  color: var(--text-secondary);
  font-size: var(--text-sm);
  cursor: pointer;
  transition: all var(--transition-fast);
}

.add-tag-btn:hover {
  background: var(--accent-primary);
  color: white;
  border-color: var(--accent-primary);
}

.modal-body {
  flex: 1;
  padding: var(--space-md);
  overflow: hidden;
  display: flex;
  gap: var(--space-md);
  min-height: 0;
}

.modal-body.split {
  flex-direction: row;
}

.modal-body.edit,
.modal-body.preview {
  flex-direction: row;
}

.editor-pane,
.preview-pane {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-width: 0;
  min-height: 0;
}

.pane-label {
  font-size: var(--text-xs);
  color: var(--text-dim);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-bottom: var(--space-xs);
  padding-left: var(--space-xs);
}

.content-view {
  flex: 1;
  padding: var(--space-md);
  font-size: var(--text-sm);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  color: var(--text-primary);
  overflow-y: auto;
  line-height: var(--leading-relaxed);
}

.content-editor {
  flex: 1;
  padding: var(--space-md);
  font-size: var(--text-sm);
  font-family: var(--font-mono);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  color: var(--text-primary);
  resize: none;
  line-height: var(--leading-relaxed);
}

.content-editor:focus {
  outline: none;
  border-color: var(--accent-primary);
}

.modal-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: var(--space-md);
  border-top: var(--border-subtle);
}

.footer-stats {
  font-size: var(--text-xs);
  color: var(--text-dim);
  font-family: var(--font-mono);
}

.footer-actions {
  display: flex;
  gap: var(--space-sm);
}

.cancel-btn,
.save-btn {
  padding: var(--space-xs) var(--space-md);
  font-size: var(--text-sm);
  border-radius: var(--border-radius-sm);
  cursor: pointer;
}

.cancel-btn {
  background: transparent;
  color: var(--text-muted);
  border: var(--border-subtle);
}

.cancel-btn:hover {
  background: var(--bg-hover);
  color: var(--text-primary);
}

.save-btn {
  background: var(--accent-primary);
  color: white;
  border: none;
}

.save-btn:hover {
  background: var(--accent-secondary);
}

.save-btn.saved {
  background: var(--success);
}
</style>
