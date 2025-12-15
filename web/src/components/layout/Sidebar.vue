<script setup>
defineProps({
  side: {
    type: String,
    required: true,
    validator: (v) => ['left', 'right'].includes(v),
  },
  open: {
    type: Boolean,
    default: true,
  },
})

defineEmits(['toggle'])
</script>

<template>
  <aside
    class="sidebar"
    :class="[side, { collapsed: !open }]"
  >
    <div class="sidebar-content" v-show="open">
      <slot></slot>
    </div>
  </aside>
</template>

<style scoped>
.sidebar {
  width: var(--sidebar-width);
  display: flex;
  flex-direction: column;
  gap: var(--panel-gap);
  transition: width var(--transition-slow);
  overflow: hidden;
}

.sidebar.collapsed {
  width: 0;
}

.sidebar-content {
  display: flex;
  flex-direction: column;
  gap: var(--panel-gap);
  width: var(--sidebar-width);
  height: 100%;
  overflow-y: auto;
  overflow-x: hidden;
}

.sidebar.left .sidebar-content {
  padding-right: 0;
}

.sidebar.right .sidebar-content {
  padding-left: 0;
}
</style>
