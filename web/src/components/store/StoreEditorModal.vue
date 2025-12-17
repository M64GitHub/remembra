<script setup>
import { ref, computed, onMounted } from 'vue'
import { useMarkdown } from '../../composables/useMarkdown.js'

const { renderMarkdown } = useMarkdown()

const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
})

const emit = defineEmits(['close', 'save'])

const content = ref('')
const mdEnabled = ref(true)

const renderedContent = computed(() => renderMarkdown(content.value))

onMounted(() => {
  content.value = props.item.content || ''
})

function handleSave() {
  emit('save', props.item.id, content.value)
}

function handleOverlayClick(event) {
  if (event.target === event.currentTarget) {
    emit('close')
  }
}
</script>

<template>
  <div class="modal-overlay" @click="handleOverlayClick">
    <div class="modal-content">
      <div class="modal-header">
        <h3>Stored Content</h3>
        <div class="header-actions">
          <button
            class="md-toggle"
            :class="{ disabled: !mdEnabled }"
            @click="mdEnabled = !mdEnabled"
            :title="mdEnabled ? 'Edit mode' : 'View mode'"
          >md</button>
          <button class="close-btn" @click="$emit('close')">&#x2715;</button>
        </div>
      </div>
      <div class="modal-body">
        <div
          v-if="mdEnabled"
          class="content-view markdown-content"
          v-html="renderedContent"
        ></div>
        <textarea
          v-else
          v-model="content"
          class="content-editor"
          placeholder="Enter content..."
        ></textarea>
      </div>
      <div class="modal-footer">
        <button class="cancel-btn" @click="$emit('close')">Cancel</button>
        <button class="save-btn" @click="handleSave">Save</button>
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
  width: 90%;
  max-width: 600px;
  max-height: 80vh;
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
  align-items: center;
  padding: var(--space-md);
  border-bottom: var(--border-subtle);
}

.modal-header h3 {
  margin: 0;
  font-size: var(--text-base);
  color: var(--text-primary);
}

.header-actions {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
}

.md-toggle {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  padding: 2px 6px;
  border-radius: var(--border-radius-sm);
  color: var(--text-dim);
  background: transparent;
  border: 1px solid transparent;
  cursor: pointer;
  transition: all var(--transition-fast);
}

.md-toggle:hover {
  color: var(--text-secondary);
  background: var(--bg-tertiary);
  border-color: var(--border-color);
}

.md-toggle.disabled {
  color: var(--warning);
  border-color: var(--warning);
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

.modal-body {
  flex: 1;
  padding: var(--space-md);
  overflow: auto;
  display: flex;
}

.content-view {
  width: 100%;
  min-height: 300px;
  padding: var(--space-sm);
  font-size: var(--text-sm);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  color: var(--text-primary);
  overflow-y: auto;
  line-height: var(--leading-relaxed);
}

.content-editor {
  width: 100%;
  min-height: 300px;
  padding: var(--space-sm);
  font-size: var(--text-sm);
  font-family: var(--font-mono);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  color: var(--text-primary);
  resize: vertical;
}

.content-editor:focus {
  outline: none;
  border-color: var(--accent-primary);
}

.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: var(--space-sm);
  padding: var(--space-md);
  border-top: var(--border-subtle);
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
</style>
