<script setup>
import { ref, onMounted } from 'vue'
import TopBar from './components/layout/TopBar.vue'
import Sidebar from './components/layout/Sidebar.vue'
import Panel from './components/layout/Panel.vue'
import ChatPane from './components/chat/ChatPane.vue'
import EventTerminal from './components/events/EventTerminal.vue'
import ContextViewer from './components/context/ContextViewer.vue'
import MemoryInspector from './components/memory/MemoryInspector.vue'
import ThoughtsViewer from './components/thoughts/ThoughtsViewer.vue'
import ProfilesPane from './components/profiles/ProfilesPane.vue'
import StorePane from './components/store/StorePane.vue'
import BookmarksPane from './components/bookmarks/BookmarksPane.vue'
import SettingsPane from './components/settings/SettingsPane.vue'
import { appState } from './stores/appState.js'
import { connectEvents } from './stores/eventBus.js'
import { profiles as profilesApi } from './api/client.js'

const leftSidebarOpen = ref(true)
const rightSidebarOpen = ref(true)
const leftSidebarMode = ref('memory')
const chatPaneRef = ref(null)
const isReady = ref(false)

function toggleLeftSidebar() {
  leftSidebarOpen.value = !leftSidebarOpen.value
}

function toggleRightSidebar() {
  rightSidebarOpen.value = !rightSidebarOpen.value
  appState.rightSidebarOpen = rightSidebarOpen.value
}

function setLeftSidebarMode(mode) {
  leftSidebarMode.value = mode
  appState.leftSidebarMode = mode
  localStorage.setItem('remembra-left-sidebar-mode', mode)
}

function scrollToMessage(messageId) {
  if (chatPaneRef.value) {
    chatPaneRef.value.jumpToMessage(messageId)
  }
}

async function loadActiveProfile() {
  try {
    const [actData, persData] = await Promise.all([
      profilesApi.active.get(),
      profilesApi.personas.list(),
    ])
    const activeId = actData?.persona_id ?? null
    appState.activePersonaId = activeId
    const active = persData.personas?.find(p => p.id === activeId)
    appState.activeAiName = active?.ai_name || 'AI'
  } catch (e) {
    console.error('[App] Failed to load active profile:', e)
  }
}

onMounted(async () => {
  connectEvents()

  const savedLeft = localStorage.getItem('remembra-left-sidebar')
  const savedRight = localStorage.getItem('remembra-right-sidebar')
  const savedMode = localStorage.getItem('remembra-left-sidebar-mode')
  if (savedLeft !== null) leftSidebarOpen.value = savedLeft === 'true'
  if (savedRight !== null) rightSidebarOpen.value = savedRight === 'true'
  if (savedMode !== null) {
    leftSidebarMode.value = savedMode
    appState.leftSidebarMode = savedMode
  }
  appState.rightSidebarOpen = rightSidebarOpen.value

  await loadActiveProfile()
  isReady.value = true
})

function saveSidebarState() {
  localStorage.setItem('remembra-left-sidebar', leftSidebarOpen.value)
  localStorage.setItem('remembra-right-sidebar', rightSidebarOpen.value)
}
</script>

<template>
  <div class="app-container">
    <TopBar
      @toggle-left="toggleLeftSidebar(); saveSidebarState()"
      @toggle-right="toggleRightSidebar(); saveSidebarState()"
      :left-open="leftSidebarOpen"
      :right-open="rightSidebarOpen"
    />

    <div v-if="!isReady" class="loading-screen">
      <div class="loading-spinner"></div>
      <span>Loading...</span>
    </div>

    <div v-else class="app-body">
      <Sidebar
        side="left"
        :open="leftSidebarOpen"
        @toggle="toggleLeftSidebar(); saveSidebarState()"
      >
        <div class="sidebar-mode-toggle">
          <button
            class="mode-tab"
            :class="{ active: leftSidebarMode === 'memory' }"
            @click="setLeftSidebarMode('memory')"
            title="AI Mind"
          >
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"
                 class="remembra-icon">
              <circle cx="50" cy="50" r="45" fill="none" stroke="currentColor"
                      stroke-width="3.0"/>
              <g transform="translate(7, 0)">
                <rect x="22" y="38" width="6" height="28" rx="1"
                      fill="currentColor"/>
                <path d="M26 44 Q28 38 34 38 Q42 38 42 46" stroke="currentColor"
                      stroke-width="5" fill="none" stroke-linecap="round"/>
              </g>
              <g transform="translate(71, 48) scale(-0.7, 0.7)">
                <rect x="0" y="0" width="5" height="24" rx="1"
                      fill="currentColor"/>
                <path d="M4 5 Q5 0 10 0 Q17 0 17 7" stroke="currentColor"
                      stroke-width="4" fill="none" stroke-linecap="round"/>
              </g>
            </svg>
          </button>
          <button
            class="mode-tab"
            :class="{ active: leftSidebarMode === 'store' }"
            @click="setLeftSidebarMode('store')"
            title="Saved Items"
          >
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
                 fill="none" stroke="currentColor" stroke-width="1"
                 stroke-linecap="round" stroke-linejoin="round"
                 class="star-icon">
              <polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02
                               12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26"/>
            </svg>
          </button>
          <button
            class="mode-tab"
            :class="{ active: leftSidebarMode === 'settings' }"
            @click="setLeftSidebarMode('settings')"
            title="Settings"
          >
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
                 fill="none" stroke="currentColor" stroke-width="1"
                 stroke-linecap="round" stroke-linejoin="round"
                 class="gear-icon">
              <circle cx="12" cy="12" r="3"/>
              <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0
                       0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65
                       0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0
                       1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65
                       1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0
                       1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65
                       0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65
                       1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2
                       2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0
                       0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2
                       2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0
                       0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0
                       2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0
                       0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65
                       1.65 0 0 0-1.51 1z"/>
            </svg>
          </button>
        </div>

        <template v-if="leftSidebarMode === 'memory'">
          <Panel title="Memory" icon="memory" :default-open="true">
            <MemoryInspector />
          </Panel>
          <Panel title="Thoughts" icon="thoughts" :default-open="false">
            <ThoughtsViewer />
          </Panel>
        </template>

        <template v-else-if="leftSidebarMode === 'store'">
          <Panel title="Store" icon="memory" :default-open="true">
            <StorePane />
          </Panel>
          <Panel title="Bookmarks" icon="star" :default-open="true">
            <BookmarksPane @jump-to="scrollToMessage" />
          </Panel>
        </template>

        <template v-else-if="leftSidebarMode === 'settings'">
          <Panel title="Settings" icon="settings" :default-open="true">
            <SettingsPane />
          </Panel>
          <Panel title="Profiles" icon="profiles" :default-open="true">
            <ProfilesPane />
          </Panel>
        </template>
      </Sidebar>

      <main class="main-content">
        <ChatPane ref="chatPaneRef" />
      </main>

      <Sidebar
        side="right"
        :open="rightSidebarOpen"
        @toggle="toggleRightSidebar(); saveSidebarState()"
      >
        <Panel title="Context" icon="context" :default-open="true">
          <ContextViewer />
        </Panel>
        <Panel title="Events" :default-open="true">
          <EventTerminal />
        </Panel>
      </Sidebar>
    </div>
  </div>
</template>

<style scoped>
.app-container {
  display: flex;
  flex-direction: column;
  height: 100vh;
  overflow: hidden;
}

.app-body {
  display: flex;
  flex: 1;
  overflow: hidden;
  gap: var(--panel-gap);
  padding: var(--panel-gap);
  padding-top: 0;
}

.main-content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  background: var(--bg-primary);
  border-radius: var(--border-radius);
  border: var(--border-subtle);
  overflow: hidden;
}

.placeholder {
  padding: var(--space-lg);
  color: var(--text-dim);
  font-size: var(--text-sm);
  text-align: center;
}

.loading-screen {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: var(--space-md);
  color: var(--text-dim);
  font-size: var(--text-sm);
}

.loading-spinner {
  width: 32px;
  height: 32px;
  border: 3px solid var(--bg-tertiary);
  border-top-color: var(--accent-primary);
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.sidebar-mode-toggle {
  padding: var(--space-xs) var(--space-sm);
  border-bottom: var(--border-subtle);
  display: flex;
  gap: var(--space-xs);
}

.mode-tab {
  padding: var(--space-xs);
  border-radius: var(--border-radius-sm);
  color: var(--text-dim);
  background: transparent;
  border: none;
  cursor: pointer;
  transition: all var(--transition-fast);
  font-size: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.mode-tab:hover {
  color: var(--text-secondary);
}

.mode-tab.active {
  color: var(--accent-primary);
}

.remembra-icon {
  width: 18px;
  height: 18px;
}

.gear-icon {
  width: 16px;
  height: 16px;
}

.star-icon {
  width: 16px;
  height: 16px;
}
</style>
