<script setup>
defineProps({
  color: {
    type: String,
    required: true,
  },
  size: {
    type: Number,
    default: 8,
  },
  title: {
    type: String,
    default: '',
  },
})
</script>

<template>
  <span
    class="tag-circle"
    :style="{
      backgroundColor: color,
      width: size + 'px',
      height: size + 'px',
    }"
    :title="title"
  ></span>
</template>

<style scoped>
.tag-circle {
  display: inline-block;
  border-radius: 50%;
  flex-shrink: 0;
}
</style>
