/**
 * REMEMBRA API Client
 * Fetch wrapper for REST endpoints
 */

const API_BASE = '';

class ApiError extends Error {
  constructor(status, message, details = null) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.details = details;
  }
}

async function handleResponse(res) {
  if (!res.ok) {
    let details = null;
    try {
      details = await res.json();
    } catch {
      // Response may not be JSON
    }
    throw new ApiError(res.status, res.statusText, details);
  }
  return res.json();
}

export async function get(path) {
  const res = await fetch(API_BASE + path);
  return handleResponse(res);
}

export async function post(path, body) {
  const res = await fetch(API_BASE + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return handleResponse(res);
}

export async function del(path) {
  const res = await fetch(API_BASE + path, { method: 'DELETE' });
  return handleResponse(res);
}

// Specific API methods

export const chat = {
  send: (message) => post('/api/chat', {
    messages: [{ role: 'user', content: message }]
  }),
  getMessages: (limit = 50, before = null) => {
    const params = new URLSearchParams({ limit: String(limit) });
    if (before !== null) params.set('before', String(before));
    return get(`/api/messages?${params}`);
  },
  stream: async (message, signal, onChunk, onComplete, onError) => {
    try {
      const response = await fetch(API_BASE + '/api/chat/stream', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          messages: [{ role: 'user', content: message }]
        }),
        signal,
      });

      if (!response.ok) {
        throw new ApiError(response.status, response.statusText);
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });

        const lines = buffer.split('\n');
        buffer = lines.pop();

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            try {
              const chunk = JSON.parse(line.slice(6));
              if (chunk.done) {
                onComplete(chunk);
              } else {
                onChunk(chunk);
              }
            } catch (e) {
              // Skip malformed JSON lines
            }
          }
        }
      }

      if (buffer.startsWith('data: ')) {
        try {
          const chunk = JSON.parse(buffer.slice(6));
          if (chunk.done) {
            onComplete(chunk);
          } else {
            onChunk(chunk);
          }
        } catch (e) {
          // Skip
        }
      }
    } catch (err) {
      if (err.name === 'AbortError') {
        onComplete({ done: true, aborted: true });
      } else {
        onError(err);
      }
    }
  },
};

export const memories = {
  list: () => get('/api/memories'),
  create: (memory) => post('/api/memories', memory),
  remove: (id) => del(`/api/memories?id=${id}`),
};

export const events = {
  list: (since = null, limit = 100) => {
    const params = new URLSearchParams({ limit: String(limit) });
    if (since !== null) params.set('since', String(since));
    return get(`/api/events?${params}`);
  },
};

export const thoughts = {
  list: () => get('/api/thoughts'),
};

export const episodes = {
  list: () => get('/api/episodes'),
};

export const context = {
  get: () => get('/api/context'),
};

export const profiles = {
  providers: {
    list: () => get('/api/profiles/providers'),
    create: (profile) => post('/api/profiles/providers', profile),
    update: (profile) => post('/api/profiles/providers/update', profile),
    remove: (id) => del(`/api/profiles/providers/${id}`),
  },
  personas: {
    list: () => get('/api/profiles/personas'),
    create: (profile) => post('/api/profiles/personas', profile),
    update: (profile) => post('/api/profiles/personas/update', profile),
    remove: (id) => del(`/api/profiles/personas/${id}`),
  },
  active: {
    get: () => get('/api/profiles/active'),
    set: (providerId, personaId) => post('/api/profiles/active', {
      provider_id: providerId,
      persona_id: personaId,
    }),
  },
};

export const ollama = {
  listModels: (url = 'http://127.0.0.1:11434') =>
    get(`/api/ollama/models?url=${encodeURIComponent(url)}`),
};

export const prompts = {
  get: (personaId) => get(`/api/prompts?persona_id=${personaId}`),
  getDefaults: () => get('/api/prompts/defaults'),
  set: (personaId, name, content) =>
    post('/api/prompts', { persona_id: personaId, name, content }),
};

export const identityPresets = {
  list: () => get('/api/identity-presets'),
};

export const health = {
  check: () => get('/health'),
};

export const command = {
  execute: (cmd) => post('/api/command', { command: cmd }),
};

export const systemConfig = {
  getContextWindow: () => get('/api/system/context-window'),
  setContextWindow: (value) => post('/api/system/context-window', { value }),
};

export const reflection = {
  get: () => get('/api/system/reflection'),
  set: (enabled) => post('/api/system/reflection', { enabled }),
};

export const store = {
  list: () => get('/api/store'),
  create: (content, sourceMsgId = null) =>
    post('/api/store', { content, source_msg_id: sourceMsgId }),
  update: (id, content) => post(`/api/store/${id}`, { content }),
  remove: (id) => del(`/api/store/${id}`),
};

export const bookmarks = {
  list: () => get('/api/bookmarks'),
  create: (messageIds) => post('/api/bookmarks', { message_ids: messageIds }),
  createSingle: (messageId) => post('/api/bookmarks', { message_id: messageId }),
  remove: (id) => del(`/api/bookmarks/${id}`),
  removeByMessage: (msgId) => del(`/api/bookmarks/msg/${msgId}`),
};
