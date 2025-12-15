<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  disabled: Boolean,
})

const emit = defineEmits(['send'])

const inputText = ref('')
const textareaRef = ref(null)

const canSend = computed(() => inputText.value.trim() && !props.disabled)

function handleSend() {
  if (!canSend.value) return
  emit('send', inputText.value)
  inputText.value = ''
  resizeTextarea()
}

function handleKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault()
    handleSend()
  }
}

function resizeTextarea() {
  if (!textareaRef.value) return
  textareaRef.value.style.height = 'auto'
  textareaRef.value.style.height = `${Math.min(textareaRef.value.scrollHeight, 150)}px`
}
</script>

<template>
  <div class="chat-input-container">
    <div class="input-wrapper">
      <textarea
        ref="textareaRef"
        v-model="inputText"
        @keydown="handleKeydown"
        @input="resizeTextarea"
        :disabled="disabled"
        placeholder="Type a message... (Enter to send, Shift+Enter for new line)"
        rows="1"
        class="chat-textarea"
      ></textarea>

      <button
        @click="handleSend"
        :disabled="!canSend"
        class="send-btn"
        title="Send message"
      >
        <span class="send-icon">&#x27A4;</span>
      </button>
    </div>

    <div class="input-hint">
      <span v-if="disabled" class="hint-sending">
        <span class="hint-dot"></span>
        Thinking...
      </span>
      <span v-else class="hint-shortcut">
        Press <kbd>Enter</kbd> to send
      </span>
    </div>
  </div>
</template>

<style scoped>
.chat-input-container {
  padding: var(--space-md) var(--space-lg);
  background: var(--bg-secondary);
  border-top: var(--border-subtle);
}

.input-wrapper {
  display: flex;
  gap: var(--space-sm);
  align-items: flex-end;
}

.chat-textarea {
  flex: 1;
  min-height: 44px;
  max-height: 150px;
  padding: var(--space-sm) var(--space-md);
  background: var(--bg-primary);
  border: var(--border-subtle);
  border-radius: var(--border-radius);
  resize: none;
  font-family: inherit;
  font-size: var(--text-base);
  line-height: var(--leading-normal);
  color: var(--text-primary);
  transition: border-color var(--transition-fast),
              box-shadow var(--transition-fast);
}

.chat-textarea:focus {
  outline: none;
  border-color: var(--accent-primary);
  box-shadow: 0 0 0 3px var(--accent-glow);
}

.chat-textarea::placeholder {
  color: var(--text-dim);
}

.chat-textarea:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.send-btn {
  width: 44px;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--accent-gradient);
  border-radius: var(--border-radius);
  color: white;
  transition: all var(--transition-fast);
}

.send-btn:hover:not(:disabled) {
  transform: scale(1.05);
  box-shadow: var(--shadow-glow);
}

.send-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.send-icon {
  font-size: 1.25rem;
}

.input-hint {
  margin-top: var(--space-xs);
  font-size: var(--text-xs);
  color: var(--text-dim);
  text-align: center;
}

.hint-sending {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-xs);
  color: var(--accent-primary);
}

.hint-dot {
  width: 6px;
  height: 6px;
  background: var(--accent-primary);
  border-radius: 50%;
  animation: pulse 1s infinite;
}

kbd {
  padding: 2px 6px;
  background: var(--bg-tertiary);
  border-radius: var(--border-radius-sm);
  font-family: var(--font-mono);
  font-size: var(--text-xs);
}
</style>
