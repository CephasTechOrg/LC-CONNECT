'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type Post = {
  id: string;
  kind: string;
  title: string;
  summary: string | null;
  body: string;
  audience: string;
  priority: string;
  status: string;
};

function statusClass(status: string): string {
  if (status === 'published') return 'badge success';
  if (status === 'archived') return 'badge muted';
  return 'badge';
}

export default function PostsPanel() {
  const [items, setItems] = useState<Post[]>([]);
  const [status, setStatus] = useState('Loading posts…');
  const [error, setError] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [kind, setKind] = useState('announcement');
  const [priority, setPriority] = useState('normal');
  const [audience, setAudience] = useState('all');
  const [title, setTitle] = useState('');
  const [summary, setSummary] = useState('');
  const [body, setBody] = useState('');
  const [saving, setSaving] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);

  function resetForm() {
    setEditingId(null);
    setKind('announcement');
    setPriority('normal');
    setAudience('all');
    setTitle('');
    setSummary('');
    setBody('');
  }

  function startEdit(item: Post) {
    setEditingId(item.id);
    setKind(item.kind);
    setPriority(item.priority);
    setAudience(item.audience);
    setTitle(item.title);
    setSummary(item.summary ?? '');
    setBody(item.body);
    if (typeof window !== 'undefined') window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  const load = useCallback(async () => {
    setError(false);
    setStatus('Loading posts…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<Post[]>('/admin/campus-posts', token);
      setItems(data);
      setStatus(`${data.length} post(s).`);
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Failed to load');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function submitForm(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const payload = {
        kind,
        priority,
        audience,
        title: title.trim(),
        summary: summary.trim() || null,
        body: body.trim(),
      };
      if (editingId) {
        await apiFetch(`/admin/campus-posts/${editingId}`, token, {
          method: 'PATCH',
          body: JSON.stringify(payload),
        });
        setStatus('Changes saved.');
      } else {
        await apiFetch('/admin/campus-posts', token, { method: 'POST', body: JSON.stringify(payload) });
        setStatus('Draft saved.');
      }
      resetForm();
      await load();
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Could not save post');
    } finally {
      setSaving(false);
    }
  }

  // One hardened runner for every per-item action: guards double-clicks (busy), always catches
  // errors and surfaces them, and reloads on success.
  async function run(id: string, label: string, doIt: (token: string) => Promise<void>) {
    if (busy) return;
    setBusy(id);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      await doIt(token);
      setStatus(label);
      if (editingId === id) resetForm();
      await load();
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Action failed');
    } finally {
      setBusy(null);
    }
  }

  function publish(item: Post) {
    if (item.priority === 'urgent' || item.priority === 'important') {
      if (!window.confirm(`Publish “${item.title}” as ${item.priority}? This may send a push notification.`)) return;
    }
    void run(item.id, `Published “${item.title}”.`, (token) =>
      apiFetch(`/admin/campus-posts/${item.id}/publish`, token, { method: 'POST' }),
    );
  }

  function archive(item: Post) {
    if (!window.confirm(`Remove “${item.title}” from Campus Hub? It stays here as archived.`)) return;
    void run(item.id, `Archived “${item.title}”.`, (token) =>
      apiFetch(`/admin/campus-posts/${item.id}/archive`, token, { method: 'POST' }),
    );
  }

  function remove(item: Post) {
    if (!window.confirm(`Permanently delete “${item.title}”? This cannot be undone.`)) return;
    void run(item.id, `Deleted “${item.title}”.`, (token) =>
      apiFetch(`/admin/campus-posts/${item.id}`, token, { method: 'DELETE' }),
    );
  }

  return (
    <>
      <form className="panel" onSubmit={submitForm}>
        <h2>{editingId ? 'Edit post' : 'Create draft'}</h2>
        <div className="grid-2">
          <div className="field">
            <label htmlFor="kind">Kind</label>
            <select id="kind" value={kind} onChange={(e) => setKind(e.target.value)}>
              <option value="announcement">Announcement</option>
              <option value="opportunity">Opportunity</option>
            </select>
          </div>
          <div className="field">
            <label htmlFor="priority">Priority</label>
            <select id="priority" value={priority} onChange={(e) => setPriority(e.target.value)}>
              <option value="normal">Normal</option>
              <option value="important">Important</option>
              <option value="urgent">Urgent</option>
            </select>
          </div>
          <div className="field">
            <label htmlFor="audience">Audience</label>
            <select id="audience" value={audience} onChange={(e) => setAudience(e.target.value)}>
              <option value="all">All</option>
              <option value="students">Students</option>
              <option value="staff">Staff</option>
            </select>
          </div>
          <div className="field">
            <label htmlFor="title">Title</label>
            <input id="title" value={title} onChange={(e) => setTitle(e.target.value)} required maxLength={200} />
          </div>
        </div>
        <div className="field">
          <label htmlFor="summary">Summary</label>
          <input id="summary" value={summary} onChange={(e) => setSummary(e.target.value)} maxLength={400} />
        </div>
        <div className="field">
          <label htmlFor="body">Body</label>
          <textarea id="body" rows={4} value={body} onChange={(e) => setBody(e.target.value)} required />
        </div>
        <div className="actions">
          <button className="btn" type="submit" disabled={saving} style={{ width: 'auto' }}>
            {saving ? 'Saving…' : editingId ? 'Save changes' : 'Save draft'}
          </button>
          {editingId ? (
            <button className="btn ghost" type="button" onClick={resetForm} style={{ width: 'auto' }}>
              Cancel
            </button>
          ) : null}
        </div>
      </form>

      <div className="actions" style={{ justifyContent: 'space-between', alignItems: 'center' }}>
        <p className={`status${error ? ' error' : ''}`} style={{ margin: 0 }}>
          {status}
        </p>
        <button className="btn ghost" type="button" onClick={() => void load()} style={{ width: 'auto' }}>
          Refresh
        </button>
      </div>
      <div className="card-list">
        {items.map((item) => (
          <article key={item.id} className="card">
            <div className="card-head">
              <div>
                <h3>{item.title}</h3>
                <p className="meta" style={{ textTransform: 'capitalize' }}>
                  {item.kind} · {item.audience}
                </p>
              </div>
              <div style={{ display: 'flex', gap: 6, flexShrink: 0 }}>
                {item.priority !== 'normal' ? (
                  <span className={item.priority === 'urgent' ? 'badge danger' : 'badge'}>{item.priority}</span>
                ) : null}
                <span className={statusClass(item.status)}>{item.status}</span>
              </div>
            </div>
            <p className="meta">{item.summary || item.body.slice(0, 160)}</p>
            <div className="actions">
              <button
                className="btn"
                type="button"
                disabled={busy === item.id || item.status === 'published'}
                onClick={() => publish(item)}
              >
                Publish
              </button>
              <button
                className="btn ghost"
                type="button"
                disabled={busy === item.id || item.status === 'archived'}
                onClick={() => startEdit(item)}
              >
                Edit
              </button>
              <button
                className="btn ghost"
                type="button"
                disabled={busy === item.id || item.status === 'archived'}
                onClick={() => archive(item)}
              >
                Archive
              </button>
              <button
                className="btn danger"
                type="button"
                disabled={busy === item.id}
                onClick={() => remove(item)}
              >
                Delete
              </button>
            </div>
          </article>
        ))}
      </div>
    </>
  );
}
