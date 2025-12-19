<script setup>
import { ref } from 'vue'
import TagEditorModal from './TagEditorModal.vue'

const showTagEditor = ref(false)
</script>

<template>
  <div class="settings-pane">
    <section class="settings-section">
      <h3 class="section-title">Tags</h3>
      <p class="section-desc">
        Create and manage tags to organize your bookmarks and store items.
      </p>
      <button class="manage-btn" @click="showTagEditor = true">
        Manage Tags
      </button>
    </section>

    <section class="settings-section future-placeholder">
      <h3 class="section-title">More settings coming soon...</h3>
    </section>

    <TagEditorModal
      v-if="showTagEditor"
      @close="showTagEditor = false"
    />
  </div>
</template>

<style scoped>
.settings-pane {
  display: flex;
  flex-direction: column;
  gap: var(--space-lg);
  padding: var(--space-sm);
}

.settings-section {
  background: var(--bg-tertiary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  padding: var(--space-md);
}

.section-title {
  font-size: var(--text-sm);
  font-weight: 600;
  color: var(--text-primary);
  margin: 0 0 var(--space-xs) 0;
}

.section-desc {
  font-size: var(--text-xs);
  color: var(--text-muted);
  margin: 0 0 var(--space-sm) 0;
  line-height: var(--leading-normal);
}

.manage-btn {
  padding: var(--space-xs) var(--space-md);
  background: var(--accent-primary);
  color: white;
  border: none;
  border-radius: var(--border-radius-sm);
  font-size: var(--text-xs);
  font-weight: 500;
  cursor: pointer;
  transition: all var(--transition-fast);
}

.manage-btn:hover {
  background: var(--accent-secondary);
}

.future-placeholder {
  opacity: 0.5;
}

.future-placeholder .section-title {
  font-weight: 400;
  font-style: italic;
  color: var(--text-dim);
}
</style>
