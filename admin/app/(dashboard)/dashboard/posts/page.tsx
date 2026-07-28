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

export default function PostsPage() {
  const [items, setItems] = useState<Post[]>([]);
  const [status, setStatus] = useState('Load posts to begin.');
  const [error, setError] = useState(false);
  const [kind, setKind] = useState('update');
  const [priority, setPriority] = useState('normal');
  const [audience, setAudience] = useState('all');
  const [title, setTitle] = useState('');
  const [summary, setSummary] = useState('');
  const [body, setBody] = useState('');
  const [saving, setSaving] = useState(false);

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

  async function createDraft(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      await apiFetch('/admin/campus-posts', token, {
        method: 'POST',
        body: JSON.stringify({
          kind,
          priority,
          audience,
          title: title.trim(),
          summary: summary.trim() || null,
          body: body.trim(),
        }),
      });
      setTitle('');
      setSummary('');
      setBody('');
      setStatus('Draft saved.');
      await load();
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Could not create draft');
    } finally {
      setSaving(false);
    }
  }

  async function publish(item: Post) {
    if (item.priority === 'urgent' || item.priority === 'important') {
      const ok = window.confirm(
        `Publish “${item.title}” as ${item.priority}? This may send a push notification.`,
      );
      if (!ok) return;
    }
    const token = await getAccessToken();
    if (!token) return;
    await apiFetch(`/admin/campus-posts/${item.id}/publish`, token, { method: 'POST' });
    setStatus(`Published “${item.title}”.`);
    await load();
  }

  async function archive(item: Post) {
    const token = await getAccessToken();
    if (!token) return;
    await apiFetch(`/admin/campus-posts/${item.id}/archive`, token, { method: 'POST' });
    setStatus(`Archived “${item.title}”.`);
    await load();
  }

  return (
    <>
      <header className="topbar">
        <div>
          <h1>Campus Posts</h1>
          <p>Create and publish official updates, deadlines, and opportunities</p>
        </div>
        <button className="btn secondary" type="button" onClick={() => void load()} style={{ width: 'auto' }}>
          Refresh
        </button>
      </header>
      <div className="content">
        <form className="panel" onSubmit={createDraft}>
          <h2>Create draft</h2>
          <div className="grid-2">
            <div className="field">
              <label htmlFor="kind">Kind</label>
              <select id="kind" value={kind} onChange={(e) => setKind(e.target.value)}>
                <option value="update">Update</option>
                <option value="deadline">Deadline</option>
                <option value="opportunity">Opportunity</option>
                <option value="alert">Alert</option>
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
          <button className="btn" type="submit" disabled={saving} style={{ width: 'auto' }}>
            {saving ? 'Saving…' : 'Save draft'}
          </button>
        </form>

        <p className={`status${error ? ' error' : ''}`}>{status}</p>
        <div className="card-list">
          {items.map((item) => (
            <article key={item.id} className="card">
              <div className="card-head">
                <div>
                  <h3>{item.title}</h3>
                  <p className="meta">
                    {item.kind} · {item.priority} · {item.audience}
                  </p>
                </div>
                <span className="badge">{item.status}</span>
              </div>
              <p className="meta">{item.summary || item.body.slice(0, 160)}</p>
              <div className="actions">
                <button
                  className="btn"
                  type="button"
                  disabled={item.status === 'published'}
                  onClick={() => void publish(item)}
                >
                  Publish
                </button>
                <button
                  className="btn danger"
                  type="button"
                  disabled={item.status === 'archived'}
                  onClick={() => void archive(item)}
                >
                  Archive
                </button>
              </div>
            </article>
          ))}
        </div>
      </div>
    </>
  );
}
