'use client';

import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type Post = {
  id: string;
  kind: string;
  title: string;
  summary: string | null;
  body: string;
  audience: string;
  category: string | null;
  priority: string;
  status: string;
};

const ANNOUNCEMENT_CATEGORIES: Record<string, string> = {
  general: 'General',
  academic: 'Academic',
  campus: 'Campus',
  events: 'Events',
  safety: 'Safety',
};

const OPPORTUNITY_CATEGORIES: Record<string, string> = {
  internship: 'Internships',
  job: 'Jobs',
  volunteer: 'Volunteering',
  leadership: 'Leadership',
};

function categoriesForKind(kind: string): Record<string, string> {
  return kind === 'opportunity' ? OPPORTUNITY_CATEGORIES : ANNOUNCEMENT_CATEGORIES;
}

function priorityChip(priority: string): string {
  if (priority === 'urgent') return 'ops-chip danger';
  if (priority === 'important') return 'ops-chip warn';
  return 'ops-chip muted';
}

function statusChip(status: string): string {
  if (status === 'published') return 'ops-chip success';
  if (status === 'archived') return 'ops-chip muted';
  return 'ops-chip warn';
}

export default function PostsPanel() {
  const [items, setItems] = useState<Post[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [status, setStatus] = useState('');
  const [flash, setFlash] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [kind, setKind] = useState('announcement');
  const [category, setCategory] = useState(Object.keys(ANNOUNCEMENT_CATEGORIES)[0]);
  const [priority, setPriority] = useState('normal');
  const [audience, setAudience] = useState('all');
  const [title, setTitle] = useState('');
  const [summary, setSummary] = useState('');
  const [body, setBody] = useState('');
  const [saving, setSaving] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [q, setQ] = useState('');
  const [filterKind, setFilterKind] = useState('all');
  const [filterStatus, setFilterStatus] = useState('all');

  function resetForm() {
    setEditingId(null);
    setKind('announcement');
    setCategory(Object.keys(ANNOUNCEMENT_CATEGORIES)[0]);
    setPriority('normal');
    setAudience('all');
    setTitle('');
    setSummary('');
    setBody('');
    setShowForm(false);
  }

  function onKindChange(nextKind: string) {
    setKind(nextKind);
    setCategory(Object.keys(categoriesForKind(nextKind))[0]);
  }

  function startEdit(item: Post) {
    setEditingId(item.id);
    setKind(item.kind);
    setCategory(item.category ?? Object.keys(categoriesForKind(item.kind))[0]);
    setPriority(item.priority);
    setAudience(item.audience);
    setTitle(item.title);
    setSummary(item.summary ?? '');
    setBody(item.body);
    setShowForm(true);
  }

  const load = useCallback(async () => {
    setLoading(true);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<Post[]>('/admin/campus-posts', token);
      setItems(data);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return items.filter((item) => {
      if (filterKind !== 'all' && item.kind !== filterKind) return false;
      if (filterStatus !== 'all' && item.status !== filterStatus) return false;
      if (!needle) return true;
      return (
        item.title.toLowerCase().includes(needle) ||
        (item.summary || '').toLowerCase().includes(needle) ||
        item.body.toLowerCase().includes(needle)
      );
    });
  }, [items, q, filterKind, filterStatus]);

  async function submitForm(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const payload = {
        kind,
        category,
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
        setFlash('Changes saved.');
      } else {
        await apiFetch('/admin/campus-posts', token, { method: 'POST', body: JSON.stringify(payload) });
        setFlash('Draft saved.');
      }
      resetForm();
      await load();
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not save post'));
    } finally {
      setSaving(false);
    }
  }

  async function run(id: string, label: string, doIt: (token: string) => Promise<void>) {
    if (busy) return;
    setBusy(id);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      await doIt(token);
      setFlash(label);
      if (editingId === id) resetForm();
      await load();
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not complete that action. Please try again.'));
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
      <div className="ops-toolbar">
        <div className="ops-search">
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search posts" aria-label="Search posts" />
        </div>
        <select className="ops-select" value={filterKind} onChange={(e) => setFilterKind(e.target.value)} aria-label="Kind">
          <option value="all">All kinds</option>
          <option value="announcement">Announcement</option>
          <option value="opportunity">Opportunity</option>
        </select>
        <select className="ops-select" value={filterStatus} onChange={(e) => setFilterStatus(e.target.value)} aria-label="Status">
          <option value="all">All statuses</option>
          <option value="draft">Draft</option>
          <option value="published">Published</option>
          <option value="archived">Archived</option>
        </select>
        <span className="ops-count">
          {loading ? '…' : `${filtered.length} of ${items.length} posts`}
        </span>
        <button className="ops-btn" type="button" disabled={loading} onClick={() => void load()}>Refresh</button>
        <button
          className="ops-btn primary"
          type="button"
          onClick={() => {
            resetForm();
            setShowForm(true);
          }}
        >
          Create post
        </button>
      </div>

      {error ? <div className="error-banner">{status}</div> : null}

      {flash ? <p className="ops-flash">{flash}</p> : null}

      {showForm ? (
        <form className="ops-form" onSubmit={submitForm}>
          <h2>{editingId ? 'Edit post' : 'Create draft'}</h2>
          <div className="grid-2">
            <div className="field">
              <label htmlFor="kind">Kind</label>
              <select id="kind" value={kind} onChange={(e) => onKindChange(e.target.value)}>
                <option value="announcement">Announcement</option>
                <option value="opportunity">Opportunity</option>
              </select>
            </div>
            <div className="field">
              <label htmlFor="category">Category</label>
              <select id="category" value={category} onChange={(e) => setCategory(e.target.value)}>
                {Object.entries(categoriesForKind(kind)).map(([value, label]) => (
                  <option key={value} value={value}>{label}</option>
                ))}
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
            <button className="btn ghost" type="button" onClick={resetForm} style={{ width: 'auto' }}>
              Cancel
            </button>
          </div>
        </form>
      ) : null}

      <div className="ops-table-wrap table-scroll">
        {loading ? (
          <OpsLoading label="Loading posts…" />
        ) : filtered.length === 0 ? (
          <OpsEmpty title={items.length === 0 ? 'No posts' : 'No matches'}>
            {items.length === 0
              ? 'Create a draft to publish campus announcements and opportunities.'
              : 'No posts match these filters.'}
          </OpsEmpty>
        ) : (
          <table className="ops-table">
            <thead>
              <tr>
                <th>Title</th>
                <th>Kind</th>
                <th>Category</th>
                <th>Audience</th>
                <th>Priority</th>
                <th>Status</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {filtered.map((item) => (
                <tr key={item.id}>
                  <td>
                    <div className="ops-cell-title">{item.title}</div>
                    <div className="ops-cell-sub">{item.summary || item.body.slice(0, 80)}</div>
                  </td>
                  <td style={{ textTransform: 'capitalize' }}>{item.kind}</td>
                  <td>{categoriesForKind(item.kind)[item.category ?? ''] ?? '—'}</td>
                  <td style={{ textTransform: 'capitalize' }}>{item.audience}</td>
                  <td><span className={priorityChip(item.priority)}>{item.priority}</span></td>
                  <td><span className={statusChip(item.status)}>{item.status}</span></td>
                  <td>
                    <div className="ops-row-actions">
                      <button className="ops-btn primary" type="button" disabled={busy === item.id || item.status === 'published'} onClick={() => publish(item)}>Publish</button>
                      <button className="ops-btn" type="button" disabled={busy === item.id || item.status === 'archived'} onClick={() => startEdit(item)}>Edit</button>
                      <button className="ops-btn" type="button" disabled={busy === item.id || item.status === 'archived'} onClick={() => archive(item)}>Archive</button>
                      <button className="ops-btn danger" type="button" disabled={busy === item.id} onClick={() => remove(item)}>Delete</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </>
  );
}
