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
import { appState } from './stores/appState.js'

const leftSidebarOpen = ref(true)
const rightSidebarOpen = ref(true)
const leftSidebarMode = ref('memory')

function toggleLeftSidebar() {
  leftSidebarOpen.value = !leftSidebarOpen.value
}

function toggleRightSidebar() {
  rightSidebarOpen.value = !rightSidebarOpen.value
}

function setLeftSidebarMode(mode) {
  leftSidebarMode.value = mode
  appState.leftSidebarMode = mode
  localStorage.setItem('remembra-left-sidebar-mode', mode)
}

function scrollToMessage(messageId) {
  const el = document.querySelector(`[data-message-id="${messageId}"]`)
  if (el) {
    el.scrollIntoView({ behavior: 'smooth', block: 'center' })
    el.classList.add('highlight-flash')
    setTimeout(() => el.classList.remove('highlight-flash'), 2000)
  }
}

onMounted(() => {
  const savedLeft = localStorage.getItem('remembra-left-sidebar')
  const savedRight = localStorage.getItem('remembra-right-sidebar')
  const savedMode = localStorage.getItem('remembra-left-sidebar-mode')
  if (savedLeft !== null) leftSidebarOpen.value = savedLeft === 'true'
  if (savedRight !== null) rightSidebarOpen.value = savedRight === 'true'
  if (savedMode !== null) {
    leftSidebarMode.value = savedMode
    appState.leftSidebarMode = savedMode
  }
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

    <div class="app-body">
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
                      stroke-width="2.0"/>
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
          >★</button>
        </div>

        <template v-if="leftSidebarMode === 'memory'">
          <Panel title="Memory" icon="memory" :default-open="true">
            <MemoryInspector />
          </Panel>
          <Panel title="Thoughts" icon="thoughts" :default-open="false">
            <ThoughtsViewer />
          </Panel>
          <Panel title="Profiles" icon="profiles" :default-open="false">
            <ProfilesPane />
          </Panel>
        </template>

        <template v-else>
          <Panel title="Store" icon="memory" :default-open="true">
            <StorePane />
          </Panel>
          <Panel title="Bookmarks" icon="star" :default-open="true">
            <BookmarksPane @jump-to="scrollToMessage" />
          </Panel>
        </template>
      </Sidebar>

      <main class="main-content">
        <ChatPane />
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
</style>
