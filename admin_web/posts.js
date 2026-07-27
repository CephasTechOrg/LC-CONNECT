const apiBaseInput = document.getElementById('apiBase');
const tokenInput = document.getElementById('token');
const statusEl = document.getElementById('status');
const listEl = document.getElementById('list');
const refreshBtn = document.getElementById('refreshBtn');
const createBtn = document.getElementById('createBtn');
const cardTemplate = document.getElementById('cardTemplate');

const kindInput = document.getElementById('kind');
const priorityInput = document.getElementById('priority');
const audienceInput = document.getElementById('audience');
const titleInput = document.getElementById('title');
const summaryInput = document.getElementById('summary');
const bodyInput = document.getElementById('body');

const STORAGE_KEY = 'lc_connect_admin_web';

function loadConfig() {
  const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
  apiBaseInput.value = saved.apiBase || 'http://localhost:8000/api/v1';
  tokenInput.value = saved.token || '';
}

function saveConfig() {
  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify({ apiBase: apiBaseInput.value.trim(), token: tokenInput.value.trim() }),
  );
}

function setStatus(message, isError = false) {
  statusEl.textContent = message;
  statusEl.style.color = isError ? '#b91c1c' : '#6b7280';
}

async function api(path, options = {}) {
  saveConfig();
  const base = apiBaseInput.value.replace(/\/$/, '');
  const token = tokenInput.value.trim();
  if (!token) throw new Error('Paste an admin bearer token first.');

  const response = await fetch(`${base}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      ...(options.headers || {}),
    },
  });

  const text = await response.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch (_) {
    data = text;
  }

  if (!response.ok) {
    const detail = data?.detail || response.statusText;
    throw new Error(typeof detail === 'string' ? detail : 'Request failed');
  }
  return data;
}

function renderCard(item) {
  const node = cardTemplate.content.firstElementChild.cloneNode(true);
  node.querySelector('.title').textContent = item.title;
  node.querySelector('.meta').textContent = `${item.kind} · ${item.priority} · ${item.audience}`;
  node.querySelector('.badge').textContent = item.status;
  node.querySelector('.summary').textContent = item.summary || item.body.slice(0, 140);

  const publishBtn = node.querySelector('.publish');
  const archiveBtn = node.querySelector('.archive');
  publishBtn.disabled = item.status === 'published';
  archiveBtn.disabled = item.status === 'archived';

  publishBtn.addEventListener('click', async () => {
    const needsConfirm = item.priority === 'urgent' || item.priority === 'important';
    if (needsConfirm) {
      const ok = window.confirm(
        `Publish “${item.title}” as ${item.priority}? This may send a push notification to the campus audience.`,
      );
      if (!ok) return;
    }
    publishBtn.disabled = true;
    try {
      await api(`/admin/campus-posts/${item.id}/publish`, { method: 'POST' });
      setStatus(`Published “${item.title}”.`);
      await loadPosts();
    } catch (error) {
      setStatus(error.message, true);
      publishBtn.disabled = false;
    }
  });

  archiveBtn.addEventListener('click', async () => {
    archiveBtn.disabled = true;
    try {
      await api(`/admin/campus-posts/${item.id}/archive`, { method: 'POST' });
      setStatus(`Archived “${item.title}”.`);
      await loadPosts();
    } catch (error) {
      setStatus(error.message, true);
      archiveBtn.disabled = false;
    }
  });

  return node;
}

async function loadPosts() {
  listEl.innerHTML = '';
  setStatus('Loading posts…');
  try {
    const items = await api('/admin/campus-posts');
    if (!items.length) {
      setStatus('No campus posts yet.');
      return;
    }
    items.forEach((item) => listEl.appendChild(renderCard(item)));
    setStatus(`${items.length} post(s).`);
  } catch (error) {
    setStatus(error.message, true);
  }
}

createBtn.addEventListener('click', async () => {
  createBtn.disabled = true;
  try {
    await api('/admin/campus-posts', {
      method: 'POST',
      body: JSON.stringify({
        kind: kindInput.value,
        priority: priorityInput.value,
        audience: audienceInput.value,
        title: titleInput.value.trim(),
        summary: summaryInput.value.trim() || null,
        body: bodyInput.value.trim(),
      }),
    });
    titleInput.value = '';
    summaryInput.value = '';
    bodyInput.value = '';
    setStatus('Draft saved.');
    await loadPosts();
  } catch (error) {
    setStatus(error.message, true);
  } finally {
    createBtn.disabled = false;
  }
});

refreshBtn.addEventListener('click', loadPosts);
apiBaseInput.addEventListener('change', saveConfig);
tokenInput.addEventListener('change', saveConfig);

loadConfig();
loadPosts();
