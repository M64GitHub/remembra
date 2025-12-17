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
            class="mode-btn"
            @click="setLeftSidebarMode('memory')"
            v-if="leftSidebarMode !== 'memory'"
          >Memory</button>
          <button
            class="mode-btn"
            @click="setLeftSidebarMode('store')"
            v-if="leftSidebarMode !== 'store'"
          >Store</button>
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
          <Panel title="Bookmarks" icon="context" :default-open="true">
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

.mode-btn {
  font-size: var(--text-xs);
  padding: var(--space-xs) var(--space-sm);
  border-radius: var(--border-radius-sm);
  color: var(--text-muted);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  cursor: pointer;
  transition: all var(--transition-fast);
  flex: 1;
}

.mode-btn:hover {
  background: var(--bg-hover);
  color: var(--text-primary);
}

.mode-btn.active {
  background: var(--accent-primary);
  color: white;
  border-color: var(--accent-primary);
}
</style>
