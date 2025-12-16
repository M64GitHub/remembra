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
    remove: (name) => del(`/api/profiles/providers?name=${encodeURIComponent(name)}`),
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
