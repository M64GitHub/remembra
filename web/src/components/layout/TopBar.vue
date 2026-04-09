<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { appState, checkHealth, reloadAllData, registerReload } from '../../stores/appState.js'
import { onEvent } from '../../stores/eventBus.js'
import { profiles } from '../../api/client.js'

defineProps({
  leftOpen: Boolean,
  rightOpen: Boolean,
})

const emit = defineEmits(['toggle-left', 'toggle-right', 'open-search'])

const personas = ref([])
const showPersonaDropdown = ref(false)
const dropdownRef = ref(null)

async function loadPersonas() {
  try {
    const data = await profiles.personas.list()
    personas.value = data.personas || []
  } catch (e) {
    console.error('Failed to load personas:', e)
  }
}

async function switchPersona(personaId) {
  if (personaId === appState.activePersonaId) {
    showPersonaDropdown.value = false
    return
  }

  try {
    await profiles.active.set(null, personaId)
    appState.activePersonaId = personaId
    const persona = personas.value.find(p => p.id === personaId)
    if (persona) {
      appState.activeAiName = persona.name
    }
    showPersonaDropdown.value = false
    await reloadAllData()
  } catch (e) {
    console.error('Failed to switch persona:', e)
  }
}

function toggleDropdown() {
  showPersonaDropdown.value = !showPersonaDropdown.value
}

function handleClickOutside(event) {
  if (dropdownRef.value && !dropdownRef.value.contains(event.target)) {
    showPersonaDropdown.value = false
  }
}

let unregisterReload = null
let unsubscribePersonas = null

onMounted(() => {
  setTimeout(checkHealth, 500)
  setInterval(checkHealth, 30000)
  loadPersonas()
  document.addEventListener('click', handleClickOutside)
  unregisterReload = registerReload('topbar-personas', loadPersonas)
  unsubscribePersonas = onEvent('personas_changed', loadPersonas)
})

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside)
  if (unregisterReload) unregisterReload()
  if (unsubscribePersonas) unsubscribePersonas()
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

    <div class="topbar-center" ref="dropdownRef">
      <button
        class="persona-selector"
        @click.stop="toggleDropdown"
        :title="personas.length > 1 ? 'Switch persona' : 'Current persona'"
      >
        <span class="ai-name">{{ appState.activeAiName }}</span>
        <span class="dropdown-arrow" v-if="personas.length > 1">
          {{ showPersonaDropdown ? '\u25B2' : '\u25BC' }}
        </span>
      </button>
      <div class="persona-dropdown" v-if="showPersonaDropdown && personas.length > 1">
        <div
          v-for="persona in personas"
          :key="persona.id"
          class="persona-option"
          :class="{ active: persona.id === appState.activePersonaId }"
          @click="switchPersona(persona.id)"
        >
          <span class="persona-name">{{ persona.name }}</span>
          <span class="persona-check" v-if="persona.id === appState.activePersonaId">
            &#x2713;
          </span>
        </div>
      </div>
    </div>

    <div class="topbar-right">
      <button
        class="search-btn"
        @click="emit('open-search')"
        title="Search messages (Ctrl+F)"
      >
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
             fill="none" stroke="currentColor" stroke-width="2"
             stroke-linecap="round" stroke-linejoin="round"
             class="search-icon">
          <circle cx="11" cy="11" r="8"/>
          <path d="m21 21-4.35-4.35"/>
        </svg>
      </button>
      <div class="status-indicator" :class="appState.serverStatus">
        <span class="status-dot"></span>
        <span class="status-text">{{ appState.serverStatus }}</span>
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
  position: relative;
}

.persona-selector {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  padding: var(--space-xs) var(--space-sm);
  border-radius: var(--border-radius-sm);
  background: transparent;
  cursor: pointer;
  transition: all var(--transition-fast);
}

.persona-selector:hover {
  background: var(--bg-hover);
}

.dropdown-arrow {
  font-size: 8px;
  color: var(--text-dim);
}

.persona-dropdown {
  position: absolute;
  top: 100%;
  left: 50%;
  transform: translateX(-50%);
  margin-top: var(--space-xs);
  min-width: 160px;
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius);
  box-shadow: var(--shadow-lg);
  z-index: 100;
  overflow: hidden;
}

.persona-option {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--space-sm) var(--space-md);
  cursor: pointer;
  transition: all var(--transition-fast);
}

.persona-option:hover {
  background: var(--bg-hover);
}

.persona-option.active {
  background: var(--accent-glow);
}

.persona-name {
  font-size: var(--text-sm);
  color: var(--text-secondary);
}

.persona-option.active .persona-name {
  color: var(--accent-primary);
}

.persona-check {
  color: var(--accent-primary);
  font-size: var(--text-sm);
}

.search-btn {
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--border-radius-sm);
  color: var(--text-muted);
  background: transparent;
  transition: all var(--transition-fast);
}

.search-btn:hover {
  background: var(--bg-hover);
  color: var(--accent-primary);
}

.search-icon {
  width: 16px;
  height: 16px;
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
