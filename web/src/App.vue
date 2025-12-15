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

const leftSidebarOpen = ref(true)
const rightSidebarOpen = ref(true)

function toggleLeftSidebar() {
  leftSidebarOpen.value = !leftSidebarOpen.value
}

function toggleRightSidebar() {
  rightSidebarOpen.value = !rightSidebarOpen.value
}

onMounted(() => {
  const savedLeft = localStorage.getItem('remembra-left-sidebar')
  const savedRight = localStorage.getItem('remembra-right-sidebar')
  if (savedLeft !== null) leftSidebarOpen.value = savedLeft === 'true'
  if (savedRight !== null) rightSidebarOpen.value = savedRight === 'true'
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
        <Panel title="Memory" icon="memory" :default-open="true">
          <MemoryInspector />
        </Panel>
        <Panel title="Thoughts" icon="thoughts" :default-open="false">
          <ThoughtsViewer />
        </Panel>
        <Panel title="Profiles" icon="profiles" :default-open="false">
          <ProfilesPane />
        </Panel>
      </Sidebar>

      <main class="main-content">
        <ChatPane />
      </main>

      <Sidebar
        side="right"
        :open="rightSidebarOpen"
        @toggle="toggleRightSidebar(); saveSidebarState()"
      >
        <Panel title="Context" :default-open="true">
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
</style>
