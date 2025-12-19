<script setup>
import { ref, computed, onMounted } from 'vue'
import { reflection } from '../../api/client.js'
import { appState } from '../../stores/appState.js'

const props = defineProps({
  disabled: Boolean,
  isStreaming: Boolean,
})

const emit = defineEmits(['send', 'stop'])

const inputText = ref('')
const textareaRef = ref(null)
const reflectionEnabled = ref(true)

const canSend = computed(() => inputText.value.trim() && !props.disabled)

onMounted(async () => {
  try {
    const data = await reflection.get()
    reflectionEnabled.value = data.enabled
    appState.reflectionEnabled = data.enabled
  } catch (e) {
    console.error('Failed to get reflection status:', e)
  }
})

async function toggleReflection() {
  try {
    const data = await reflection.set(!reflectionEnabled.value)
    reflectionEnabled.value = data.enabled
    appState.reflectionEnabled = data.enabled
  } catch (e) {
    console.error('Failed to toggle reflection:', e)
  }
}

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
      <button
        class="reflection-toggle"
        :class="{ disabled: !reflectionEnabled }"
        @click="toggleReflection"
        :title="reflectionEnabled ? 'Reflection ON' : 'Reflection OFF'"
      >
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"
             class="reflection-logo">
          <circle cx="50" cy="50" r="45" fill="none" stroke="currentColor"
                  stroke-width="2.0"/>
          <g transform="translate(7, 0)">
            <rect x="22" y="38" width="6" height="28" rx="1"
                  fill="currentColor"/>
            <path d="M26 44 Q28 38 34 38 Q42 38 42 46" stroke="currentColor"
                  stroke-width="5" fill="none" stroke-linecap="round"/>
          </g>
          <g transform="translate(71, 48) scale(-0.7, 0.7)">
            <rect x="0" y="0" width="5" height="24" rx="1" fill="currentColor"/>
            <path d="M4 5 Q5 0 10 0 Q17 0 17 7" stroke="currentColor"
                  stroke-width="4" fill="none" stroke-linecap="round"/>
          </g>
        </svg>
      </button>

      <button
        class="thinking-live-toggle"
        :class="{ disabled: !appState.showThinkingLive }"
        @click="appState.showThinkingLive = !appState.showThinkingLive"
        :title="appState.showThinkingLive ? 'Live thinking ON' : 'Live thinking OFF'"
      >
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
             class="thinking-icon" fill="none" stroke="currentColor"
             stroke-width="1">
          <circle cx="12" cy="8" r="5"/>
          <path d="M12 13 C6 13 4 18 4 21 L20 21 C20 18 18 13 12 13"/>
          <circle cx="17" cy="4" r="1.2" fill="currentColor" stroke="none"/>
          <circle cx="20" cy="6" r="0.8" fill="currentColor" stroke="none"/>
        </svg>
      </button>

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
        v-if="isStreaming"
        @click="emit('stop')"
        class="stop-btn"
        title="Stop generation"
      >
        <span class="stop-icon">&#x25A0;</span>
      </button>
      <button
        v-else
        @click="handleSend"
        :disabled="!canSend"
        class="send-btn"
        title="Send message"
      >
        <span class="send-icon">&#x25B6;</span>
      </button>
    </div>

    <div class="input-hint">
      <span v-if="isStreaming" class="hint-streaming">
        <span class="hint-dot"></span>
        Streaming... click stop to cancel
      </span>
      <span v-else-if="disabled" class="hint-sending">
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

.stop-btn {
  width: 44px;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  border: 1px solid #7a3545;
  border-radius: var(--border-radius);
  color: #7a3545;
  transition: all var(--transition-fast);
}

.stop-btn:hover {
  background: rgba(122, 53, 69, 0.15);
  transform: scale(1.05);
}

.stop-icon {
  font-size: 1rem;
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

.hint-streaming {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-xs);
  color: var(--text-secondary);
}

.hint-dot {
  width: 6px;
  height: 6px;
  background: var(--accent-primary);
  border-radius: 50%;
  animation: pulse 1s infinite;
}

.hint-streaming .hint-dot {
  background: var(--text-secondary);
}

kbd {
  padding: 2px 6px;
  background: var(--bg-tertiary);
  border-radius: var(--border-radius-sm);
  font-family: var(--font-mono);
  font-size: var(--text-xs);
}

.reflection-toggle {
  width: 28px;
  height: 28px;
  padding: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  border: none;
  cursor: pointer;
  transition: all var(--transition-fast);
  align-self: center;
  color: #667eea;
}

.reflection-logo {
  width: 100%;
  height: 100%;
}

.reflection-toggle:hover {
  filter: brightness(1.2);
  transform: scale(1.1);
}

.reflection-toggle.disabled {
  color: var(--text-dim);
  opacity: 0.6;
}

.reflection-toggle.disabled:hover {
  filter: brightness(1.1);
}

.thinking-live-toggle {
  width: 24px;
  height: 24px;
  padding: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  border: none;
  cursor: pointer;
  transition: all var(--transition-fast);
  align-self: center;
  color: var(--accent-primary);
}

.thinking-icon {
  width: 100%;
  height: 100%;
}

.thinking-live-toggle:hover {
  filter: brightness(1.2);
  transform: scale(1.1);
}

.thinking-live-toggle.disabled {
  color: var(--text-dim);
  opacity: 0.6;
}

.thinking-live-toggle.disabled:hover {
  filter: brightness(1.1);
}
</style>
