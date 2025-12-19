<script setup>
import { ref, watch, computed } from 'vue'
import { prompts as promptsApi, identityPresets as presetsApi } from '../../api/client.js'

const props = defineProps({
  persona: {
    type: Object,
    default: null,
  },
  mode: {
    type: String,
    default: 'edit',
  },
  reflectionEnabled: {
    type: Boolean,
    default: true,
  },
})

const modalTitle = computed(() =>
  props.mode === 'create' ? 'New Persona' : 'Edit Persona'
)

const emit = defineEmits(['cancel', 'save'])

const promptTemplates = ref({
  system_spine: '',
  reflector_system: '',
  reflector_no_ops: '',
  idle_thinker: '',
  episode_compactor: '',
})

const promptsLoading = ref(false)
const promptsError = ref(null)

const presets = ref([])
const selectedPreset = ref(null)
const presetsLoading = ref(false)

const defaults = {
  llm_chat: { temperature: 0.7, max_tokens: 256 },
  llm_reflection: { temperature: 0.2, max_tokens: 512 },
  llm_idle: { temperature: 0.4, max_tokens: 160 },
  llm_episode: { temperature: 0.2, max_tokens: 512 },
  conf_user_notes: 0.70,
  conf_episodes: 0.85,
  conf_idle: 0.55,
  conf_governor: 0.60,
}


const form = ref({
  name: '',
  ai_name: '',
  tone: '',
  persona_kernel: '',
  include_ai_name: true,
  llm_chat_temp: 0.7,
  llm_chat_tokens: 256,
  llm_reflection_temp: 0.2,
  llm_reflection_tokens: 512,
  llm_idle_temp: 0.4,
  llm_idle_tokens: 160,
  llm_episode_temp: 0.2,
  llm_episode_tokens: 512,
  conf_user_notes: 0.70,
  conf_episodes: 0.85,
  conf_idle: 0.55,
  conf_governor: 0.60,
  idle_threshold_min: 15,
  thought_interval_min: 60,
  compaction_threshold: 6,
})

const activeSection = ref('basic')

watch(() => props.persona, async (p) => {
  if (p) {
    form.value = {
      name: p.name || '',
      ai_name: p.ai_name || '',
      tone: p.tone || '',
      persona_kernel: p.persona_kernel || '',
      include_ai_name: p.include_ai_name ?? true,
      llm_chat_temp: p.llm_chat_temp,
      llm_chat_tokens: p.llm_chat_tokens,
      llm_reflection_temp: p.llm_reflect_temp,
      llm_reflection_tokens: p.llm_reflect_tokens,
      llm_idle_temp: p.llm_idle_temp,
      llm_idle_tokens: p.llm_idle_tokens,
      llm_episode_temp: p.llm_episode_temp,
      llm_episode_tokens: p.llm_episode_tokens,
      conf_user_notes: p.conf_user_notes,
      conf_episodes: p.conf_episodes,
      conf_idle: p.conf_idle,
      conf_governor: p.conf_governor,
      idle_threshold_min: p.idle_threshold_min ?? 15,
      thought_interval_min: p.thought_interval_min ?? 60,
      compaction_threshold: p.compaction_threshold ?? 6,
    }

    if (p.id) {
      await loadPrompts(p.id)
    } else {
      // Create mode - fetch defaults from API
      await loadDefaultPrompts()
    }

    await loadPresets()
  }
}, { immediate: true })

async function loadPrompts(personaId) {
  promptsLoading.value = true
  promptsError.value = null
  try {
    const data = await promptsApi.get(personaId)
    if (data.prompts) {
      promptTemplates.value = {
        system_spine: data.prompts.system_spine || '',
        reflector_system: data.prompts.reflector_system || '',
        reflector_no_ops: data.prompts.reflector_no_ops || '',
        idle_thinker: data.prompts.idle_thinker || '',
        episode_compactor: data.prompts.episode_compactor || '',
      }
    }
  } catch (e) {
    console.error('[Prompts] Load error:', e)
    promptsError.value = e.message
  } finally {
    promptsLoading.value = false
  }
}

async function loadDefaultPrompts() {
  promptsLoading.value = true
  promptsError.value = null
  try {
    const data = await promptsApi.getDefaults()
    if (data.prompts) {
      promptTemplates.value = {
        system_spine: data.prompts.system_spine || '',
        reflector_system: data.prompts.reflector_system || '',
        reflector_no_ops: data.prompts.reflector_no_ops || '',
        idle_thinker: data.prompts.idle_thinker || '',
        episode_compactor: data.prompts.episode_compactor || '',
      }
    }
  } catch (e) {
    console.error('[Prompts] Error loading defaults:', e)
    promptsError.value = e.message
  } finally {
    promptsLoading.value = false
  }
}

async function loadPresets() {
  presetsLoading.value = true
  try {
    const data = await presetsApi.list()
    presets.value = data.presets || []
  } catch (e) {
    console.error('[Presets] Load error:', e)
  } finally {
    presetsLoading.value = false
  }
}

function applyPreset() {
  if (!selectedPreset.value) return
  const preset = presets.value.find(p => p.id === selectedPreset.value)
  if (preset) {
    form.value.persona_kernel = preset.text
    selectedPreset.value = null
  }
}

async function handleSave() {
  if (!form.value.name.trim()) {
    alert('Persona name is required')
    return
  }

  const data = {
    id: props.persona?.id,
    name: form.value.name,
    ai_name: form.value.ai_name,
    tone: form.value.tone,
    persona_kernel: form.value.persona_kernel || '',
    include_ai_name: form.value.include_ai_name,
    llm_chat_temp: form.value.llm_chat_temp,
    llm_chat_tokens: form.value.llm_chat_tokens,
    llm_reflect_temp: form.value.llm_reflection_temp,
    llm_reflect_tokens: form.value.llm_reflection_tokens,
    llm_idle_temp: form.value.llm_idle_temp,
    llm_idle_tokens: form.value.llm_idle_tokens,
    llm_episode_temp: form.value.llm_episode_temp,
    llm_episode_tokens: form.value.llm_episode_tokens,
    conf_user_notes: form.value.conf_user_notes,
    conf_episodes: form.value.conf_episodes,
    conf_idle: form.value.conf_idle,
    conf_governor: form.value.conf_governor,
    idle_threshold_min: form.value.idle_threshold_min,
    thought_interval_min: form.value.thought_interval_min,
    compaction_threshold: form.value.compaction_threshold,
    prompts: promptTemplates.value,
  }

  emit('save', data)
}

function resetToDefaults() {
  if (confirm('Reset all values to defaults?')) {
    form.value.llm_chat_temp = defaults.llm_chat.temperature
    form.value.llm_chat_tokens = defaults.llm_chat.max_tokens
    form.value.llm_reflection_temp = defaults.llm_reflection.temperature
    form.value.llm_reflection_tokens = defaults.llm_reflection.max_tokens
    form.value.llm_idle_temp = defaults.llm_idle.temperature
    form.value.llm_idle_tokens = defaults.llm_idle.max_tokens
    form.value.llm_episode_temp = defaults.llm_episode.temperature
    form.value.llm_episode_tokens = defaults.llm_episode.max_tokens
    form.value.conf_user_notes = defaults.conf_user_notes
    form.value.conf_episodes = defaults.conf_episodes
    form.value.conf_idle = defaults.conf_idle
    form.value.conf_governor = defaults.conf_governor
  }
}

function formatPercent(val) {
  return (val * 100).toFixed(0) + '%'
}
</script>

<template>
  <div class="modal-overlay" @click.self="emit('cancel')">
    <div class="modal-container">
      <div class="modal-header">
        <h2 class="modal-title">{{ modalTitle }}</h2>
        <button class="close-btn" @click="emit('cancel')">&times;</button>
      </div>

      <!-- Simplified view when reflection is disabled -->
      <div v-if="!reflectionEnabled" class="modal-body">
        <div class="section">
          <p class="section-desc">
            Simple chat mode - configure basic persona settings.
          </p>

          <div class="form-group">
            <label>Persona Name</label>
            <input type="text" v-model="form.name" placeholder="e.g. Default" />
          </div>

          <div class="form-group">
            <label>AI Name</label>
            <div class="ai-name-row">
              <input
                type="text"
                v-model="form.ai_name"
                placeholder="e.g. REMEMBRA"
              />
              <label class="checkbox-label">
                <input
                  type="checkbox"
                  v-model="form.include_ai_name"
                />
                Include in system prompt
              </label>
            </div>
          </div>

          <div class="form-group">
            <label>System Prompt</label>
            <textarea
              v-model="form.persona_kernel"
              rows="12"
              placeholder="Define the AI's behavior and personality..."
              class="kernel-textarea"
            ></textarea>
            <small class="field-help">
              This text is sent as the system prompt to the LLM.
              <span v-if="form.include_ai_name">
                It will be prefixed with "You are {{ form.ai_name }}."
              </span>
            </small>
          </div>
        </div>
      </div>

      <!-- Full view when reflection is enabled -->
      <div v-if="reflectionEnabled" class="modal-nav">
        <button
          class="nav-btn"
          :class="{ active: activeSection === 'basic' }"
          @click="activeSection = 'basic'"
        >Basic</button>
        <button
          class="nav-btn"
          :class="{ active: activeSection === 'identity' }"
          @click="activeSection = 'identity'"
        >Identity</button>
        <button
          class="nav-btn"
          :class="{ active: activeSection === 'llm' }"
          @click="activeSection = 'llm'"
        >LLM</button>
        <button
          class="nav-btn"
          :class="{ active: activeSection === 'confidence' }"
          @click="activeSection = 'confidence'"
        >Confidence</button>
        <button
          class="nav-btn"
          :class="{ active: activeSection === 'prompts' }"
          @click="activeSection = 'prompts'"
        >Prompts</button>
        <button
          class="nav-btn"
          :class="{ active: activeSection === 'reflection' }"
          @click="activeSection = 'reflection'"
        >Reflection</button>
      </div>

      <div v-if="reflectionEnabled" class="modal-body">
        <div v-show="activeSection === 'basic'" class="section">
          <div class="form-group">
            <label>Persona Name</label>
            <input type="text" v-model="form.name" placeholder="e.g. Default" />
          </div>
          <div class="form-group">
            <label>AI Name</label>
            <input type="text" v-model="form.ai_name" placeholder="e.g. REMEMBRA" />
          </div>
          <div class="form-group">
            <label>Tone</label>
            <input
              type="text"
              v-model="form.tone"
              placeholder="e.g. helpful, concise, grounded"
            />
          </div>
        </div>

        <div v-show="activeSection === 'identity'" class="section">
          <p class="section-desc">
            Define the AI's core personality traits and values.
            This text is prepended with the AI name in the system prompt.
          </p>

          <div class="preset-row">
            <select v-model="selectedPreset" class="preset-select">
              <option :value="null">Load preset...</option>
              <option
                v-for="p in presets"
                :key="p.id"
                :value="p.id"
              >
                {{ p.name }}
              </option>
            </select>
            <button
              @click="applyPreset"
              :disabled="!selectedPreset"
              class="preset-apply-btn"
            >
              Apply
            </button>
          </div>

          <div class="form-group">
            <label>Persona Kernel</label>
            <textarea
              v-model="form.persona_kernel"
              rows="10"
              placeholder=" is a thoughtful, observant conversational presence..."
              class="kernel-textarea"
            ></textarea>
          </div>
        </div>

        <div v-show="activeSection === 'llm'" class="section">
          <div class="llm-group">
            <div class="llm-label">Chat</div>
            <div class="llm-controls">
              <div class="control-item">
                <span class="control-label">Temperature</span>
                <input
                  type="range"
                  min="0"
                  max="1"
                  step="0.1"
                  v-model.number="form.llm_chat_temp"
                />
                <span class="control-value">{{ form.llm_chat_temp }}</span>
              </div>
              <div class="control-item">
                <span class="control-label">Max Tokens</span>
                <input
                  type="number"
                  min="64"
                  max="4096"
                  v-model.number="form.llm_chat_tokens"
                />
              </div>
            </div>
          </div>

          <div class="llm-group">
            <div class="llm-label">Reflection</div>
            <div class="llm-controls">
              <div class="control-item">
                <span class="control-label">Temperature</span>
                <input
                  type="range"
                  min="0"
                  max="1"
                  step="0.1"
                  v-model.number="form.llm_reflection_temp"
                />
                <span class="control-value">{{ form.llm_reflection_temp }}</span>
              </div>
              <div class="control-item">
                <span class="control-label">Max Tokens</span>
                <input
                  type="number"
                  min="64"
                  max="4096"
                  v-model.number="form.llm_reflection_tokens"
                />
              </div>
            </div>
          </div>

          <div class="llm-group">
            <div class="llm-label">Idle Thinking</div>
            <div class="llm-controls">
              <div class="control-item">
                <span class="control-label">Temperature</span>
                <input
                  type="range"
                  min="0"
                  max="1"
                  step="0.1"
                  v-model.number="form.llm_idle_temp"
                />
                <span class="control-value">{{ form.llm_idle_temp }}</span>
              </div>
              <div class="control-item">
                <span class="control-label">Max Tokens</span>
                <input
                  type="number"
                  min="64"
                  max="4096"
                  v-model.number="form.llm_idle_tokens"
                />
              </div>
            </div>
          </div>

          <div class="llm-group">
            <div class="llm-label">Episode Compaction</div>
            <div class="llm-controls">
              <div class="control-item">
                <span class="control-label">Temperature</span>
                <input
                  type="range"
                  min="0"
                  max="1"
                  step="0.1"
                  v-model.number="form.llm_episode_temp"
                />
                <span class="control-value">{{ form.llm_episode_temp }}</span>
              </div>
              <div class="control-item">
                <span class="control-label">Max Tokens</span>
                <input
                  type="number"
                  min="64"
                  max="4096"
                  v-model.number="form.llm_episode_tokens"
                />
              </div>
            </div>
          </div>
        </div>

        <div v-show="activeSection === 'confidence'" class="section">
          <p class="section-desc">
            Minimum confidence thresholds for storing different memory types.
          </p>

          <div class="conf-group">
            <div class="conf-label">User Notes</div>
            <div class="conf-controls">
              <input
                type="range"
                min="0"
                max="1"
                step="0.05"
                v-model.number="form.conf_user_notes"
              />
              <span class="conf-value">{{ formatPercent(form.conf_user_notes) }}</span>
            </div>
          </div>

          <div class="conf-group">
            <div class="conf-label">Episodes</div>
            <div class="conf-controls">
              <input
                type="range"
                min="0"
                max="1"
                step="0.05"
                v-model.number="form.conf_episodes"
              />
              <span class="conf-value">{{ formatPercent(form.conf_episodes) }}</span>
            </div>
          </div>

          <div class="conf-group">
            <div class="conf-label">Idle Thoughts</div>
            <div class="conf-controls">
              <input
                type="range"
                min="0"
                max="1"
                step="0.05"
                v-model.number="form.conf_idle"
              />
              <span class="conf-value">{{ formatPercent(form.conf_idle) }}</span>
            </div>
          </div>

          <div class="conf-group">
            <div class="conf-label">Governor</div>
            <div class="conf-controls">
              <input
                type="range"
                min="0"
                max="1"
                step="0.05"
                v-model.number="form.conf_governor"
              />
              <span class="conf-value">{{ formatPercent(form.conf_governor) }}</span>
            </div>
          </div>
        </div>

        <div v-show="activeSection === 'prompts'" class="section prompts-section">
          <p class="section-desc">
            Prompt templates for this persona.
          </p>

          <div v-if="promptsLoading" class="prompts-loading">
            Loading prompts...
          </div>

          <div v-else class="prompts-list">
            <div class="prompt-group">
              <label>System Spine</label>
              <textarea
                v-model="promptTemplates.system_spine"
                placeholder="Core system prompt"
                rows="6"
              ></textarea>
            </div>

            <div class="prompt-group">
              <label>Reflector System</label>
              <textarea
                v-model="promptTemplates.reflector_system"
                placeholder="Reflection analysis prompt"
                rows="6"
              ></textarea>
            </div>

            <div class="prompt-group">
              <label>Reflector No-ops</label>
              <textarea
                v-model="promptTemplates.reflector_no_ops"
                placeholder="No-operation triggers"
                rows="4"
              ></textarea>
            </div>

            <div class="prompt-group">
              <label>Idle Thinker</label>
              <textarea
                v-model="promptTemplates.idle_thinker"
                placeholder="Idle thought generation prompt"
                rows="6"
              ></textarea>
            </div>

            <div class="prompt-group">
              <label>Episode Compactor</label>
              <textarea
                v-model="promptTemplates.episode_compactor"
                placeholder="Episode summary generation prompt"
                rows="6"
              ></textarea>
            </div>
          </div>
        </div>

        <div v-show="activeSection === 'reflection'" class="section">
          <p class="section-desc">
            Configure when and how often the AI generates idle thoughts.
          </p>

          <div class="form-group">
            <label>Initial Idle Threshold (minutes)</label>
            <input
              type="number"
              v-model.number="form.idle_threshold_min"
              min="1"
              max="1440"
            />
            <small class="field-help">
              Time before first idle thought after user inactivity
            </small>
          </div>

          <div class="form-group">
            <label>Thought Interval (minutes)</label>
            <input
              type="number"
              v-model.number="form.thought_interval_min"
              min="1"
              max="1440"
            />
            <small class="field-help">
              Time between subsequent idle thoughts
            </small>
          </div>

          <div class="form-group">
            <label>Compaction Threshold (messages)</label>
            <input
              type="number"
              v-model.number="form.compaction_threshold"
              min="2"
              max="50"
            />
            <small class="field-help">
              Messages required before episode compaction runs
            </small>
          </div>
        </div>
      </div>

      <div class="modal-footer">
        <button class="reset-btn" @click="resetToDefaults">
          Reset to Defaults
        </button>
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
  max-width: 900px;
  min-height: 70vh;
  max-height: 95vh;
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

.modal-nav {
  display: flex;
  gap: 2px;
  padding: var(--space-sm) var(--space-lg);
  background: var(--bg-secondary);
  border-bottom: var(--border-subtle);
}

.nav-btn {
  flex: 1;
  padding: var(--space-xs) var(--space-sm);
  background: transparent;
  border-radius: var(--border-radius-sm);
  color: var(--text-secondary);
  font-size: var(--text-sm);
  transition: all var(--transition-fast);
}

.nav-btn:hover {
  background: var(--bg-tertiary);
}

.nav-btn.active {
  background: var(--accent-primary);
  color: white;
}

.modal-body {
  flex: 1;
  overflow-y: auto;
  padding: var(--space-lg);
}

.section {
  display: flex;
  flex-direction: column;
  gap: var(--space-md);
}

.section-desc {
  color: var(--text-dim);
  font-size: var(--text-sm);
  margin: 0 0 var(--space-sm) 0;
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

.ai-name-row {
  display: flex;
  align-items: center;
  gap: var(--space-md);
}

.ai-name-row input[type="text"] {
  flex: 1;
  padding: var(--space-sm);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius);
  color: var(--text-primary);
  font-size: var(--text-sm);
}

.checkbox-label {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  font-size: var(--text-sm);
  color: var(--text-secondary);
  cursor: pointer;
  white-space: nowrap;
}

.checkbox-label input[type="checkbox"] {
  width: 16px;
  height: 16px;
  accent-color: var(--accent-primary);
  cursor: pointer;
}

.form-group input[type="number"] {
  padding: var(--space-sm);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius);
  color: var(--text-primary);
  font-size: var(--text-sm);
  width: 120px;
}

.form-group input[type="number"]:focus {
  outline: none;
  border-color: var(--accent-primary);
}

.field-help {
  font-size: var(--text-xs);
  color: var(--text-muted);
  margin-top: 2px;
}

.llm-group,
.conf-group {
  background: var(--bg-secondary);
  border-radius: var(--border-radius);
  padding: var(--space-sm);
}

.llm-label,
.conf-label {
  font-size: var(--text-sm);
  font-weight: 500;
  color: var(--text-primary);
  margin-bottom: var(--space-xs);
}

.llm-controls {
  display: flex;
  flex-direction: column;
  gap: var(--space-xs);
}

.control-item,
.conf-controls {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
}

.control-label {
  font-size: var(--text-xs);
  color: var(--text-dim);
  min-width: 80px;
}

.control-item input[type="range"],
.conf-controls input[type="range"] {
  flex: 1;
  accent-color: var(--accent-primary);
}

.control-value,
.conf-value {
  font-size: var(--text-xs);
  font-family: var(--font-mono);
  color: var(--text-secondary);
  min-width: 40px;
  text-align: right;
}

.control-item input[type="number"] {
  width: 80px;
  padding: 4px 8px;
  background: var(--bg-tertiary);
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  color: var(--text-primary);
  font-size: var(--text-xs);
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

.reset-btn {
  padding: var(--space-xs) var(--space-sm);
  background: transparent;
  border: var(--border-subtle);
  border-radius: var(--border-radius-sm);
  color: var(--text-dim);
  font-size: var(--text-sm);
  transition: all var(--transition-fast);
}

.reset-btn:hover {
  border-color: var(--warning);
  color: var(--warning);
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

.prompts-section {
  overflow-y: auto;
}

.prompts-loading {
  text-align: center;
  color: var(--text-dim);
  padding: var(--space-lg);
  font-style: italic;
}

.prompts-list {
  display: flex;
  flex-direction: column;
  gap: var(--space-md);
}

.prompt-group {
  display: flex;
  flex-direction: column;
  gap: var(--space-xs);
}

.prompt-group label {
  font-size: var(--text-sm);
  font-weight: 500;
  color: var(--text-secondary);
}

.prompt-group textarea {
  width: 100%;
  padding: var(--space-sm);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius);
  color: var(--text-primary);
  font-size: var(--text-xs);
  font-family: var(--font-mono);
  resize: vertical;
  min-height: 80px;
}

.prompt-group textarea:focus {
  outline: none;
  border-color: var(--accent-primary);
}

.prompt-group textarea::placeholder {
  color: var(--text-dim);
  font-style: italic;
}

.kernel-textarea {
  width: 100%;
  padding: var(--space-sm);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius);
  color: var(--text-primary);
  font-size: var(--text-sm);
  font-family: var(--font-mono);
  resize: vertical;
  min-height: 200px;
}

.kernel-textarea:focus {
  outline: none;
  border-color: var(--accent-primary);
}

.kernel-textarea::placeholder {
  color: var(--text-dim);
  font-style: italic;
}

.preset-row {
  display: flex;
  gap: var(--space-sm);
  margin-bottom: var(--space-md);
}

.preset-select {
  flex: 1;
  padding: var(--space-sm);
  background: var(--bg-secondary);
  border: var(--border-subtle);
  border-radius: var(--border-radius);
  color: var(--text-primary);
  font-size: var(--text-sm);
}

.preset-apply-btn {
  padding: var(--space-sm) var(--space-md);
  background: var(--accent-primary);
  border-radius: var(--border-radius);
  color: white;
  font-size: var(--text-sm);
  transition: all var(--transition-fast);
}

.preset-apply-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.preset-apply-btn:not(:disabled):hover {
  background: var(--accent-secondary);
}
</style>
