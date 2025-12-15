<script setup>
import { ref, onMounted } from 'vue'
import { health } from '../../api/client.js'
import { appState } from '../../stores/appState.js'

defineProps({
  leftOpen: Boolean,
  rightOpen: Boolean,
})

const emit = defineEmits(['toggle-left', 'toggle-right'])

const serverStatus = ref('checking')

async function checkHealth() {
  try {
    await health.check()
    serverStatus.value = 'online'
  } catch {
    serverStatus.value = 'offline'
  }
}

onMounted(() => {
  setTimeout(checkHealth, 500)
  setInterval(checkHealth, 30000)
})
</script>

<template>
  <header class="topbar">
    <div class="topbar-left">
      <button
        class="sidebar-toggle"
        :class="{ active: leftOpen }"
        @click="emit('toggle-left')"
        title="Toggle left sidebar"
      >
        <span class="icon">&#9776;</span>
      </button>
      <div class="brand">
        <img src="/remembra.svg" alt="REMEMBRA" class="brand-logo" />
        <span class="brand-name">REMEMBRA</span>
        <span class="brand-version">v0.1</span>
      </div>
    </div>

    <div class="topbar-center">
      <span class="ai-name">{{ appState.activeAiName }}</span>
    </div>

    <div class="topbar-right">
      <div class="status-indicator" :class="serverStatus">
        <span class="status-dot"></span>
        <span class="status-text">{{ serverStatus }}</span>
      </div>
      <button
        class="sidebar-toggle"
        :class="{ active: rightOpen }"
        @click="emit('toggle-right')"
        title="Toggle right sidebar"
      >
        <span class="icon">&#9776;</span>
      </button>
    </div>
  </header>
</template>

<style scoped>
.topbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  height: var(--topbar-height);
  padding: 0 var(--space-md);
  background: var(--bg-primary);
  border-bottom: var(--border-subtle);
}

.topbar-left,
.topbar-right {
  display: flex;
  align-items: center;
  gap: var(--space-md);
}

.topbar-center {
  flex: 1;
  display: flex;
  justify-content: center;
}

.sidebar-toggle {
  width: 36px;
  height: 36px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--border-radius-sm);
  color: var(--text-muted);
  transition: all var(--transition-fast);
}

.sidebar-toggle:hover {
  background: var(--bg-hover);
  color: var(--text-primary);
}

.sidebar-toggle.active {
  color: var(--accent-primary);
}

.sidebar-toggle .icon {
  font-size: 1.25rem;
}

.brand {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
}

.brand-logo {
  width: 28px;
  height: 28px;
}

.brand-name {
  font-weight: 600;
  font-size: var(--text-lg);
  background: var(--accent-gradient);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.brand-version {
  font-size: var(--text-xs);
  color: var(--text-dim);
}

.ai-name {
  font-size: var(--text-sm);
  color: var(--text-secondary);
  font-family: var(--font-mono);
}

.status-indicator {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  font-size: var(--text-xs);
  padding: var(--space-xs) var(--space-sm);
  border-radius: var(--border-radius-sm);
  background: var(--bg-secondary);
}

.status-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--text-dim);
}

.status-indicator.online .status-dot {
  background: var(--success);
  box-shadow: 0 0 6px var(--success);
}

.status-indicator.offline .status-dot {
  background: var(--error);
}

.status-indicator.checking .status-dot {
  background: var(--warning);
  animation: pulse 1s infinite;
}

.status-text {
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
</style>
