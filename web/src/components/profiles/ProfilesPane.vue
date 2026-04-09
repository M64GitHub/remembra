<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue'
import { profiles as profilesApi, prompts as promptsApi } from '../../api/client.js'
import { appState, reloadAllData, registerReload } from '../../stores/appState.js'
import { emitEvent } from '../../stores/eventBus.js'
import ProviderCard from './ProviderCard.vue'
import PersonaCard from './PersonaCard.vue'
import PersonaEditorModal from './PersonaEditorModal.vue'
import ProviderEditorModal from './ProviderEditorModal.vue'

const activeTab = ref('personas')
const providers = ref([])
const personas = ref([])
const activeProfile = ref({ provider: null, persona: null })
const activeIds = ref({ provider_id: null, persona_id: null })
const isLoading = ref(false)
const error = ref(null)
const hasLoaded = ref(false)

const showPersonaModal = ref(false)
const editingPersona = ref(null)
const modalMode = ref('edit')

const showProviderModal = ref(false)
const editingProvider = ref(null)
const providerModalMode = ref('edit')

const defaultProvider = {
  name: '',
  ollama_url: 'http://127.0.0.1:11434',
  model: 'llama3.2',
}

const defaultPersona = {
  name: '',
  ai_name: 'REMEMBRA',
  tone: 'helpful, concise, grounded, engaging',
  llm_chat_temp: 0.7,
  llm_chat_tokens: 256,
  llm_reflect_temp: 0.2,
  llm_reflect_tokens: 512,
  llm_idle_temp: 0.4,
  llm_idle_tokens: 160,
  llm_episode_temp: 0.2,
  llm_episode_tokens: 512,
  conf_user_notes: 0.70,
  conf_episodes: 0.85,
  conf_idle: 0.55,
  conf_governor: 0.60,
}

async function loadProfiles() {
  if (isLoading.value || appState.isChatBusy) return

  isLoading.value = true
  error.value = null

  try {
    const [provData, persData, actData] = await Promise.all([
      profilesApi.providers.list(),
      profilesApi.personas.list(),
      profilesApi.active.get(),
    ])
    providers.value = provData.providers || []
    personas.value = persData.personas || []
    activeProfile.value = actData || { provider: null, persona: null }
    activeIds.value = {
      provider_id: actData?.provider_id ?? null,
      persona_id: actData?.persona_id ?? null,
    }
    const active = personas.value.find(p => p.id === activeIds.value.persona_id)
    appState.activeAiName = active?.ai_name || '...'
    appState.activePersonaId = activeIds.value.persona_id
    console.log('[Profiles] Loaded', providers.value.length, 'providers,',
                personas.value.length, 'personas,',
                'active IDs:', activeIds.value)
  } catch (e) {
    console.error('[Profiles] Error:', e)
    error.value = e.message
  } finally {
    isLoading.value = false
  }
}

async function setActive(providerId, personaId) {
  try {
    await profilesApi.active.set(providerId, personaId)
    activeIds.value = { provider_id: providerId, persona_id: personaId }
    const active = personas.value.find(p => p.id === personaId)
    appState.activeAiName = active?.ai_name || '...'
    appState.activePersonaId = personaId

    // Sequential reload all registered components
    await reloadAllData()

    await loadProfiles()
  } catch (e) {
    error.value = e.message
  }
}

async function deleteProvider(id) {
  try {
    await profilesApi.providers.remove(id)
    providers.value = providers.value.filter(p => p.id !== id)
  } catch (e) {
    error.value = e.message
  }
}

async function deletePersona(id) {
  try {
    await profilesApi.personas.remove(id)
    personas.value = personas.value.filter(p => p.id !== id)
    emitEvent('personas_changed')
  } catch (e) {
    error.value = e.message
  }
}

function openPersonaEditor(persona) {
  editingPersona.value = { ...persona }
  modalMode.value = 'edit'
  showPersonaModal.value = true
}

function createNewPersona() {
  editingPersona.value = { ...defaultPersona }
  modalMode.value = 'create'
  showPersonaModal.value = true
}

function closePersonaEditor() {
  showPersonaModal.value = false
  editingPersona.value = null
  modalMode.value = 'edit'
}

async function savePersona(personaData) {
  try {
    let personaId
    if (modalMode.value === 'create') {
      const result = await profilesApi.personas.create(personaData)
      personaId = result.id
    } else {
      await profilesApi.personas.update(personaData)
      personaId = personaData.id
    }

    if (personaData.prompts && personaId) {
      for (const [name, content] of Object.entries(personaData.prompts)) {
        if (content.trim()) {
          await promptsApi.set(personaId, name, content)
        }
      }
    }

    await loadProfiles()
    emitEvent('personas_changed')
    closePersonaEditor()
  } catch (e) {
    error.value = e.message
  }
}

function openProviderEditor(provider) {
  editingProvider.value = { ...provider }
  providerModalMode.value = 'edit'
  showProviderModal.value = true
}

function createNewProvider() {
  editingProvider.value = { ...defaultProvider }
  providerModalMode.value = 'create'
  showProviderModal.value = true
}

function closeProviderEditor() {
  showProviderModal.value = false
  editingProvider.value = null
  providerModalMode.value = 'edit'
}

async function saveProvider(providerData) {
  try {
    if (providerModalMode.value === 'create') {
      await profilesApi.providers.create(providerData)
    } else {
      await profilesApi.providers.update(providerData)
    }
    await loadProfiles()
    closeProviderEditor()
  } catch (e) {
    error.value = e.message
  }
}

// Load when pane becomes active
watch(
  () => appState.leftSidebarMode,
  (mode) => {
    if (mode === 'settings' && !hasLoaded.value) {
      loadProfiles()
      hasLoaded.value = true
    }
  },
  { immediate: true }
)

let unregisterReload = null

onMounted(() => {
  // Register for reload after /db clear
  unregisterReload = registerReload('profiles', async () => {
    providers.value = []
    personas.value = []
    hasLoaded.value = false
    await loadProfiles()
    hasLoaded.value = true
  })
})

onUnmounted(() => {
  if (unregisterReload) unregisterReload()
})
</script>

<template>
  <div class="profiles-pane">
    <div class="profiles-tabs">
      <button
        class="tab-btn"
        :class="{ active: activeTab === 'providers' }"
        @click="activeTab = 'providers'"
      >
        Providers
      </button>
      <button
        class="tab-btn"
        :class="{ active: activeTab === 'personas' }"
        @click="activeTab = 'personas'"
      >
        Personas
      </button>
      <button
        @click="loadProfiles"
        class="refresh-btn"
        :disabled="isLoading || appState.isChatBusy"
        title="Refresh"
      >
        &#x21BB;
      </button>
    </div>

    <div class="profiles-error" v-if="error">
      {{ error }}
    </div>

    <div class="profiles-content">
      <div v-if="activeTab === 'providers'" class="profile-list">
        <button class="new-btn" @click="createNewProvider">+ New Provider</button>
        <ProviderCard
          v-for="provider in providers"
          :key="provider.id"
          :provider="provider"
          :is-active="activeIds.provider_id === provider.id"
          :can-delete="providers.length > 1"
          @activate="setActive(provider.id, activeIds.persona_id)"
          @delete="deleteProvider"
          @edit="openProviderEditor"
        />
        <div v-if="providers.length === 0 && !isLoading" class="empty-state">
          No providers configured
        </div>
      </div>

      <div v-if="activeTab === 'personas'" class="profile-list">
        <button class="new-btn" @click="createNewPersona">+ New Persona</button>
        <PersonaCard
          v-for="persona in personas"
          :key="persona.id"
          :persona="persona"
          :is-active="activeIds.persona_id === persona.id"
          :can-delete="personas.length > 1"
          @activate="setActive(activeIds.provider_id, persona.id)"
          @delete="deletePersona"
          @edit="openPersonaEditor"
        />
        <div v-if="personas.length === 0 && !isLoading" class="empty-state">
          No personas configured
        </div>
      </div>

      <div v-if="isLoading" class="loading-state">
        Loading...
      </div>
    </div>

    <PersonaEditorModal
      v-if="showPersonaModal"
      :persona="editingPersona"
      :mode="modalMode"
      :reflection-enabled="appState.reflectionEnabled"
      @save="savePersona"
      @cancel="closePersonaEditor"
    />

    <ProviderEditorModal
      v-if="showProviderModal"
      :provider="editingProvider"
      :mode="providerModalMode"
      @save="saveProvider"
      @cancel="closeProviderEditor"
    />
  </div>
</template>

<style scoped>
.profiles-pane {
  display: flex;
  flex-direction: column;
  height: 100%;
  font-size: var(--text-xs);
}

.profiles-tabs {
  display: flex;
  gap: 2px;
  padding: var(--space-xs);
  background: var(--bg-secondary);
  border-bottom: var(--border-subtle);
}

.tab-btn {
  flex: 1;
  padding: 4px 8px;
  background: var(--bg-tertiary);
  border-radius: var(--border-radius-sm);
  color: var(--text-secondary);
  font-size: var(--text-xs);
  transition: all var(--transition-fast);
}

.tab-btn:hover {
  color: var(--text-primary);
}

.tab-btn.active {
  background: var(--accent-primary);
  color: white;
}

.refresh-btn {
  width: 24px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--border-radius-sm);
  color: var(--text-muted);
  font-size: 14px;
  transition: all var(--transition-fast);
}

.refresh-btn:hover:not(:disabled) {
  background: var(--bg-tertiary);
  color: var(--text-primary);
}

.refresh-btn:disabled {
  opacity: 0.5;
}

.profiles-error {
  padding: var(--space-xs) var(--space-sm);
  background: var(--error-dim);
  color: var(--error);
}

.profiles-content {
  flex: 1;
  overflow-y: auto;
  padding: var(--space-xs);
}

.profile-list {
  display: flex;
  flex-direction: column;
  gap: var(--space-xs);
}

.empty-state,
.loading-state {
  text-align: center;
  color: var(--text-dim);
  padding: var(--space-lg);
  font-style: italic;
}

.new-btn {
  width: 100%;
  padding: var(--space-sm);
  background: var(--bg-tertiary);
  border: 1px dashed var(--text-dim);
  border-radius: var(--border-radius);
  color: var(--text-secondary);
  font-size: var(--text-xs);
  transition: all var(--transition-fast);
  margin-bottom: var(--space-xs);
}

.new-btn:hover {
  border-color: var(--accent-primary);
  color: var(--accent-primary);
  background: var(--bg-secondary);
}
</style>
