<script setup>
import { ref, watch, computed, onMounted } from 'vue'
import { ollama, openrouter } from '../../api/client.js'

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

const OR_DEFAULT_URL = 'https://openrouter.ai/api/v1'
const OLLAMA_DEFAULT_URL = 'http://127.0.0.1:11434'

const form = ref({
  name: '',
  provider_type: 'ollama',
  ollama_url: OLLAMA_DEFAULT_URL,
  base_url: OLLAMA_DEFAULT_URL,
  api_key: '',
  model: '',
  size: 0,
  digest: '',
  modified_at: '',
})

const availableModels = ref([])
const loadingModels = ref(false)
const modelLoadError = ref(null)
const manualEntry = ref(false)

const isOpenRouter = computed(
  () => form.value.provider_type === 'openrouter'
)
const isOllama = computed(
  () => form.value.provider_type === 'ollama'
)
const canDiscoverOr = computed(
  () => isOpenRouter.value && !!props.provider?.id
)

watch(() => props.provider, (p) => {
  if (p) {
    const ptype = p.provider_type || 'ollama'
    const bu = p.base_url || p.ollama_url ||
      (ptype === 'openrouter' ? OR_DEFAULT_URL : OLLAMA_DEFAULT_URL)
    form.value = {
      name: p.name || '',
      provider_type: ptype,
      ollama_url: p.ollama_url || bu,
      base_url: bu,
      api_key: '',
      model: p.model || '',
      size: p.size || 0,
      digest: p.digest || '',
      modified_at: p.modified_at || '',
    }
  }
}, { immediate: true })

watch(() => form.value.provider_type, (t, prev) => {
  if (t === prev) return
  availableModels.value = []
  modelLoadError.value = null
  manualEntry.value = false
  if (t === 'openrouter') {
    if (!form.value.base_url ||
        form.value.base_url === OLLAMA_DEFAULT_URL) {
      form.value.base_url = OR_DEFAULT_URL
    }
  } else {
    if (!form.value.base_url ||
        form.value.base_url === OR_DEFAULT_URL) {
      form.value.base_url = OLLAMA_DEFAULT_URL
      form.value.ollama_url = OLLAMA_DEFAULT_URL
    }
  }
})

async function refreshModels() {
  loadingModels.value = true
  modelLoadError.value = null
  availableModels.value = []

  try {
    if (isOpenRouter.value) {
      if (!props.provider?.id) {
        modelLoadError.value =
          'Save the profile once with your API key, then refresh'
        manualEntry.value = true
        return
      }
      const resp = await openrouter.listModels(props.provider.id)
      availableModels.value = resp.models || []
    } else {
      const resp = await ollama.listModels(form.value.ollama_url)
      availableModels.value = resp.models || []
    }
    manualEntry.value = false
    if (availableModels.value.length === 0) {
      modelLoadError.value = 'No models found'
      manualEntry.value = true
    } else {
      const key = isOpenRouter.value ? 'id' : 'name'
      const currentInList = availableModels.value.some(
        m => m[key] === form.value.model
      )
      if (!form.value.model || !currentInList) {
        selectModel(availableModels.value[0][key])
      }
    }
  } catch (e) {
    console.error('[ProviderEditor] Model discovery failed:', e)
    modelLoadError.value = isOpenRouter.value
      ? 'Could not fetch OpenRouter models (check API key)'
      : 'Could not connect to Ollama'
    manualEntry.value = true
  } finally {
    loadingModels.value = false
  }
}

function selectModel(modelKey) {
  form.value.model = modelKey
  const key = isOpenRouter.value ? 'id' : 'name'
  const selected = availableModels.value.find(m => m[key] === modelKey)
  if (!selected) return
  if (isOpenRouter.value) {
    form.value.size = 0
    form.value.digest = ''
    form.value.modified_at = ''
  } else {
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

function formatContext(len) {
  if (!len || len === 0) return ''
  if (len >= 1000) return (len / 1000).toFixed(0) + 'k ctx'
  return len + ' ctx'
}

function handleSave() {
  if (!form.value.name.trim()) {
    alert('Provider name is required')
    return
  }
  const url = form.value.base_url || form.value.ollama_url
  if (!url.trim()) {
    alert('URL is required')
    return
  }
  if (isOpenRouter.value && !form.value.model.trim()) {
    if (!props.provider?.id) {
      // Allow save with empty model on first create so user can
      // refresh models afterwards.
    }
  } else if (!form.value.model.trim()) {
    alert('Model name is required')
    return
  }

  const data = {
    id: props.provider?.id,
    name: form.value.name,
    provider_type: form.value.provider_type,
    ollama_url: isOllama.value ? url : '',
    base_url: url,
    api_key: form.value.api_key,
    model: form.value.model,
    size: form.value.size,
    digest: form.value.digest,
    modified_at: form.value.modified_at,
  }

  emit('save', data)
}

onMounted(() => {
  if (isOllama.value) refreshModels()
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
          <label>Provider Type</label>
          <select v-model="form.provider_type" class="model-select">
            <option value="ollama">Ollama (local)</option>
            <option value="openrouter">OpenRouter</option>
          </select>
        </div>

        <div class="form-group" v-if="isOllama">
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

        <div class="form-group" v-if="isOpenRouter">
          <label>Base URL</label>
          <input
            type="text"
            v-model="form.base_url"
            placeholder="https://openrouter.ai/api/v1"
          />
        </div>

        <div class="form-group" v-if="isOpenRouter">
          <label>API Key</label>
          <input
            type="password"
            v-model="form.api_key"
            :placeholder="
              props.provider?.has_api_key
                ? 'Leave blank to keep existing key'
                : 'sk-or-v1-...'
            "
          />
          <div class="hint" v-if="props.provider?.has_api_key">
            A key is stored. Paste a new one only to replace it.
          </div>
        </div>

        <div class="form-group">
          <label>
            Model
            <button
              v-if="isOpenRouter"
              class="refresh-btn inline"
              @click="refreshModels"
              :disabled="loadingModels || !canDiscoverOr"
              title="Refresh models"
            >
              {{ loadingModels ? '...' : '\u21BB' }}
            </button>
          </label>
          <div v-if="!manualEntry && availableModels.length > 0">
            <select
              :value="form.model"
              @change="selectModel($event.target.value)"
              class="model-select"
            >
              <option value="" disabled>Select a model</option>
              <template v-if="isOpenRouter">
                <option
                  v-for="m in availableModels"
                  :key="m.id"
                  :value="m.id"
                >
                  {{ m.name || m.id }}
                  <template v-if="m.context_length">
                    ({{ formatContext(m.context_length) }})
                  </template>
                </option>
              </template>
              <template v-else>
                <option
                  v-for="m in availableModels"
                  :key="m.name"
                  :value="m.name"
                >
                  {{ m.name }} ({{ formatSize(m.size) }})
                </option>
              </template>
            </select>
          </div>
          <div v-else>
            <input
              type="text"
              v-model="form.model"
              :placeholder="
                isOpenRouter
                  ? 'e.g. openai/gpt-4o-mini'
                  : 'e.g. llama3.2'
              "
            />
            <div v-if="modelLoadError" class="model-error">
              {{ modelLoadError }}
              <button
                v-if="availableModels.length > 0 || isOllama"
                class="switch-btn"
                @click="manualEntry = !manualEntry"
              >
                {{ manualEntry ? 'Try dropdown' : 'Enter manually' }}
              </button>
            </div>
          </div>
          <div
            v-if="isOllama && form.model && form.size > 0"
            class="model-meta"
          >
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
  display: flex;
  align-items: center;
  gap: var(--space-xs);
}

.form-group input[type="text"],
.form-group input[type="password"] {
  padding: var(--space-sm);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius);
  color: var(--text-primary);
  font-size: var(--text-sm);
}

.form-group input[type="text"]:focus,
.form-group input[type="password"]:focus {
  outline: none;
  border-color: var(--accent-primary);
}

.hint {
  font-size: var(--text-xs);
  color: var(--text-dim);
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

.refresh-btn.inline {
  padding: 2px 6px;
  min-width: auto;
  font-size: var(--text-sm);
  margin-left: auto;
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
