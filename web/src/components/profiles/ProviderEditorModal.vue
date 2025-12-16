<script setup>
import { ref, watch, computed, onMounted } from 'vue'
import { ollama } from '../../api/client.js'

const props = defineProps({
  provider: {
    type: Object,
    default: null,
  },
  mode: {
    type: String,
    default: 'edit',
  },
})

const modalTitle = computed(() =>
  props.mode === 'create' ? 'New Provider' : 'Edit Provider'
)

const emit = defineEmits(['cancel', 'save'])

const form = ref({
  name: '',
  ollama_url: '',
  model: '',
  size: 0,
  digest: '',
  modified_at: '',
})

const availableModels = ref([])
const loadingModels = ref(false)
const modelLoadError = ref(null)
const manualEntry = ref(false)

watch(() => props.provider, (p) => {
  if (p) {
    form.value = {
      name: p.name || '',
      ollama_url: p.ollama_url || 'http://127.0.0.1:11434',
      model: p.model || 'llama3.2',
      size: p.size || 0,
      digest: p.digest || '',
      modified_at: p.modified_at || '',
    }
  }
}, { immediate: true })

async function refreshModels() {
  loadingModels.value = true
  modelLoadError.value = null
  availableModels.value = []

  try {
    const resp = await ollama.listModels(form.value.ollama_url)
    availableModels.value = resp.models || []
    manualEntry.value = false
    if (availableModels.value.length === 0) {
      modelLoadError.value = 'No models found'
    } else {
      // Auto-select first model if current is empty or not in list
      const currentInList = availableModels.value.some(
        m => m.name === form.value.model
      )
      if (!form.value.model || !currentInList) {
        selectModel(availableModels.value[0].name)
      }
    }
  } catch (e) {
    console.error('[ProviderEditor] Model discovery failed:', e)
    modelLoadError.value = 'Could not connect to Ollama'
    manualEntry.value = true
  } finally {
    loadingModels.value = false
  }
}

function selectModel(modelName) {
  form.value.model = modelName
  const selected = availableModels.value.find(m => m.name === modelName)
  if (selected) {
    form.value.size = selected.size || 0
    form.value.digest = selected.digest || ''
    form.value.modified_at = selected.modified_at || ''
  }
}

function formatSize(bytes) {
  if (!bytes || bytes === 0) return '-'
  const gb = bytes / (1024 * 1024 * 1024)
  if (gb >= 1) return gb.toFixed(1) + ' GB'
  const mb = bytes / (1024 * 1024)
  return mb.toFixed(0) + ' MB'
}

function handleSave() {
  if (!form.value.name.trim()) {
    alert('Provider name is required')
    return
  }
  if (!form.value.ollama_url.trim()) {
    alert('Ollama URL is required')
    return
  }
  if (!form.value.model.trim()) {
    alert('Model name is required')
    return
  }

  const data = {
    id: props.provider?.id,
    name: form.value.name,
    ollama_url: form.value.ollama_url,
    model: form.value.model,
    size: form.value.size,
    digest: form.value.digest,
    modified_at: form.value.modified_at,
  }

  emit('save', data)
}

onMounted(() => {
  refreshModels()
})
</script>

<template>
  <div class="modal-overlay" @click.self="emit('cancel')">
    <div class="modal-container">
      <div class="modal-header">
        <h2 class="modal-title">{{ modalTitle }}</h2>
        <button class="close-btn" @click="emit('cancel')">&times;</button>
      </div>

      <div class="modal-body">
        <div class="form-group">
          <label>Provider Name</label>
          <input
            type="text"
            v-model="form.name"
            placeholder="e.g. local-ollama"
          />
        </div>
        <div class="form-group">
          <label>Ollama URL</label>
          <div class="url-row">
            <input
              type="text"
              v-model="form.ollama_url"
              placeholder="e.g. http://127.0.0.1:11434"
              @blur="refreshModels"
            />
            <button
              class="refresh-btn"
              @click="refreshModels"
              :disabled="loadingModels"
              title="Refresh models"
            >
              {{ loadingModels ? '...' : '\u21BB' }}
            </button>
          </div>
        </div>
        <div class="form-group">
          <label>Model</label>
          <div v-if="!manualEntry && availableModels.length > 0">
            <select
              :value="form.model"
              @change="selectModel($event.target.value)"
              class="model-select"
            >
              <option value="" disabled>Select a model</option>
              <option
                v-for="m in availableModels"
                :key="m.name"
                :value="m.name"
              >
                {{ m.name }} ({{ formatSize(m.size) }})
              </option>
            </select>
          </div>
          <div v-else>
            <input
              type="text"
              v-model="form.model"
              placeholder="e.g. llama3.2"
            />
            <div v-if="modelLoadError" class="model-error">
              {{ modelLoadError }}
              <button class="switch-btn" @click="manualEntry = !manualEntry">
                {{ manualEntry ? 'Try dropdown' : 'Enter manually' }}
              </button>
            </div>
          </div>
          <div v-if="form.model && form.size > 0" class="model-meta">
            <span class="meta-item">Size: {{ formatSize(form.size) }}</span>
            <span class="meta-item" v-if="form.digest">
              Digest: {{ form.digest.slice(0, 12) }}...
            </span>
          </div>
        </div>
      </div>

      <div class="modal-footer">
        <div class="footer-spacer"></div>
        <button class="cancel-btn" @click="emit('cancel')">Cancel</button>
        <button class="save-btn" @click="handleSave">Save</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.7);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}

.modal-container {
  background: var(--bg-primary);
  border-radius: var(--border-radius-lg);
  border: var(--border-subtle);
  width: 90%;
  max-width: 400px;
  display: flex;
  flex-direction: column;
  box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--space-md) var(--space-lg);
  border-bottom: var(--border-subtle);
}

.modal-title {
  font-size: var(--text-lg);
  font-weight: 600;
  color: var(--text-primary);
  margin: 0;
}

.close-btn {
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--border-radius);
  color: var(--text-dim);
  font-size: 24px;
  transition: all var(--transition-fast);
}

.close-btn:hover {
  background: var(--bg-tertiary);
  color: var(--text-primary);
}

.modal-body {
  padding: var(--space-lg);
  display: flex;
  flex-direction: column;
  gap: var(--space-md);
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: var(--space-xs);
}

.form-group label {
  font-size: var(--text-sm);
  font-weight: 500;
  color: var(--text-secondary);
}

.form-group input[type="text"] {
  padding: var(--space-sm);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius);
  color: var(--text-primary);
  font-size: var(--text-sm);
}

.form-group input[type="text"]:focus {
  outline: none;
  border-color: var(--accent-primary);
}

.url-row {
  display: flex;
  gap: var(--space-xs);
}

.url-row input {
  flex: 1;
}

.refresh-btn {
  padding: var(--space-sm);
  background: var(--bg-tertiary);
  border: var(--border-subtle);
  border-radius: var(--border-radius);
  color: var(--text-secondary);
  font-size: var(--text-md);
  transition: all var(--transition-fast);
  min-width: 40px;
}

.refresh-btn:hover:not(:disabled) {
  background: var(--bg-secondary);
  color: var(--accent-primary);
  border-color: var(--accent-primary);
}

.refresh-btn:disabled {
  opacity: 0.5;
}

.model-select {
  width: 100%;
  padding: var(--space-sm);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius);
  color: var(--text-primary);
  font-size: var(--text-sm);
}

.model-select:focus {
  outline: none;
  border-color: var(--accent-primary);
}

.model-error {
  margin-top: var(--space-xs);
  font-size: var(--text-xs);
  color: var(--text-dim);
  display: flex;
  align-items: center;
  gap: var(--space-sm);
}

.switch-btn {
  padding: 2px 8px;
  background: var(--bg-tertiary);
  border-radius: var(--border-radius-sm);
  color: var(--accent-primary);
  font-size: var(--text-xs);
}

.switch-btn:hover {
  background: var(--bg-secondary);
}

.model-meta {
  margin-top: var(--space-xs);
  padding: var(--space-xs);
  background: var(--bg-tertiary);
  border-radius: var(--border-radius-sm);
  font-size: var(--text-xs);
  display: flex;
  gap: var(--space-md);
}

.meta-item {
  color: var(--text-dim);
  font-family: var(--font-mono);
}

.modal-footer {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  padding: var(--space-md) var(--space-lg);
  border-top: var(--border-subtle);
  background: var(--bg-secondary);
}

.footer-spacer {
  flex: 1;
}

.cancel-btn,
.save-btn {
  padding: var(--space-xs) var(--space-md);
  border-radius: var(--border-radius-sm);
  font-size: var(--text-sm);
  transition: all var(--transition-fast);
}

.cancel-btn {
  background: var(--bg-tertiary);
  color: var(--text-secondary);
}

.cancel-btn:hover {
  background: var(--bg-tertiary);
  color: var(--text-primary);
}

.save-btn {
  background: var(--accent-primary);
  color: white;
}

.save-btn:hover {
  background: var(--accent-secondary);
}
</style>
