<script setup>
import { ref, onMounted } from 'vue'

const props = defineProps({
  title: {
    type: String,
    required: true,
  },
  icon: {
    type: String,
    default: null,
  },
  defaultOpen: {
    type: Boolean,
    default: true,
  },
})

const isOpen = ref(props.defaultOpen)

const iconMap = {
  memory: '\u{2B21}',
  thoughts: '\u{25C7}',
  profiles: 'P',
  context: '\u{25CB}',
  star: '\u{2606}',
}

function toggle() {
  isOpen.value = !isOpen.value
}

function getIcon(name) {
  return iconMap[name] || null
}
</script>

<template>
  <div class="panel" :class="{ collapsed: !isOpen }">
    <button class="panel-header" @click="toggle">
      <span class="panel-icon" v-if="icon && icon !== 'star'">{{ getIcon(icon) }}</span>
      <svg v-if="icon === 'star'" class="panel-icon-svg"
           xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
           fill="none" stroke="currentColor" stroke-width="1"
           stroke-linecap="round" stroke-linejoin="round">
        <polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02
                         12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26"/>
      </svg>
      <span class="panel-title">{{ title }}</span>
      <span class="panel-toggle">{{ isOpen ? '\u25BC' : '\u25B6' }}</span>
    </button>
    <div class="panel-body" v-show="isOpen">
      <slot></slot>
    </div>
  </div>
</template>

<style scoped>
.panel {
  background: var(--bg-primary);
  border-radius: var(--border-radius);
  border: var(--border-subtle);
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.panel:not(.collapsed) {
  flex: 1;
  min-height: 120px;
}

.panel.collapsed {
  flex: none;
}

.panel-header {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  padding: var(--space-sm) var(--space-md);
  background: var(--bg-secondary);
  border-bottom: var(--border-subtle);
  text-align: left;
  width: 100%;
  transition: background var(--transition-fast);
}

.panel-header:hover {
  background: var(--bg-tertiary);
}

.panel.collapsed .panel-header {
  border-bottom: none;
}

.panel-icon {
  font-size: var(--text-sm);
  font-weight: 700;
  opacity: 0.8;
}

.panel-icon-svg {
  width: 14px;
  height: 14px;
  opacity: 0.8;
}

.panel-title {
  flex: 1;
  font-size: var(--text-sm);
  font-weight: 500;
  color: var(--text-secondary);
}

.panel-toggle {
  font-size: var(--text-xs);
  color: var(--text-dim);
  transition: transform var(--transition-fast);
}

.panel-body {
  flex: 1;
  overflow-y: auto;
  overflow-x: hidden;
}
</style>
