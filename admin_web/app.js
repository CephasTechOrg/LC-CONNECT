const apiBaseInput = document.getElementById('apiBase');
const tokenInput = document.getElementById('token');
const statusEl = document.getElementById('status');
const listEl = document.getElementById('list');
const refreshBtn = document.getElementById('refreshBtn');
const cardTemplate = document.getElementById('cardTemplate');

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
  node.querySelector('.name').textContent = item.display_name || 'Unnamed';
  node.querySelector('.email').textContent = `${item.user_email} · ${item.user_role}`;
  node.querySelector('.badge').textContent = item.status;
  node.querySelector('.title').textContent = item.official_title;
  node.querySelector('.department').textContent = item.department;
  node.querySelector('.category').textContent = item.category.replaceAll('_', ' ');
  node.querySelector('.contact').textContent = item.contact_email;

  const note = node.querySelector('.review-note');
  const approveBtn = node.querySelector('.approve');
  const rejectBtn = node.querySelector('.reject');

  approveBtn.addEventListener('click', async () => {
    approveBtn.disabled = true;
    rejectBtn.disabled = true;
    try {
      await api(`/admin/campus-positions/${item.id}/approve`, { method: 'POST' });
      setStatus(`Approved ${item.display_name || item.user_email}.`);
      await loadPending();
    } catch (error) {
      setStatus(error.message, true);
      approveBtn.disabled = false;
      rejectBtn.disabled = false;
    }
  });

  rejectBtn.addEventListener('click', async () => {
    approveBtn.disabled = true;
    rejectBtn.disabled = true;
    try {
      await api(`/admin/campus-positions/${item.id}/reject`, {
        method: 'POST',
        body: JSON.stringify({ review_note: note.value.trim() || null }),
      });
      setStatus(`Rejected ${item.display_name || item.user_email}.`);
      await loadPending();
    } catch (error) {
      setStatus(error.message, true);
      approveBtn.disabled = false;
      rejectBtn.disabled = false;
    }
  });

  return node;
}

async function loadPending() {
  listEl.innerHTML = '';
  setStatus('Loading pending positions…');
  try {
    const items = await api('/admin/campus-positions/pending');
    if (!items.length) {
      setStatus('No pending campus positions right now.');
      return;
    }
    items.forEach((item) => listEl.appendChild(renderCard(item)));
    setStatus(`${items.length} pending position(s).`);
  } catch (error) {
    setStatus(error.message, true);
  }
}

refreshBtn.addEventListener('click', loadPending);
apiBaseInput.addEventListener('change', saveConfig);
tokenInput.addEventListener('change', saveConfig);

loadConfig();
