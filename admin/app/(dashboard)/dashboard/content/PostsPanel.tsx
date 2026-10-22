'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';
import PostComposeForm from './PostComposeForm';
import { categoriesForKind, priorityChip, statusChip, type Post } from './post-shared';

export default function PostsPanel() {
  const [items, setItems] = useState<Post[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [status, setStatus] = useState('');
  const [flash, setFlash] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [editingPost, setEditingPost] = useState<Post | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [q, setQ] = useState('');
  const [filterKind, setFilterKind] = useState('all');
  const [filterStatus, setFilterStatus] = useState('all');

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

  function openCreate() {
    setEditingPost(null);
    setShowForm(true);
  }

  function openEdit(item: Post) {
    setEditingPost(item);
    setShowForm(true);
  }

  function closeForm() {
    setShowForm(false);
    setEditingPost(null);
  }

  async function onSaved(message: string) {
    closeForm();
    setFlash(message);
    await load();
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
      if (editingPost?.id === id) closeForm();
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

  const emptyBody =
    items.length === 0
      ? 'Create a post to share campus announcements and opportunities.'
      : 'No posts match these filters.';

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
        <span className="ops-count">{loading ? '…' : `${filtered.length} of ${items.length} posts`}</span>
        <button className="ops-btn" type="button" disabled={loading} onClick={() => void load()}>Refresh</button>
        <button className="ops-btn primary" type="button" onClick={openCreate}>Create post</button>
      </div>

      {error ? <div className="error-banner">{status}</div> : null}
      {flash ? <p className="ops-flash">{flash}</p> : null}

      {showForm ? (
        <PostComposeForm
          key={editingPost?.id ?? 'new'}
          existing={editingPost}
          onCancel={closeForm}
          onSaved={onSaved}
        />
      ) : null}

      <div className="ops-table-wrap table-scroll ops-responsive-desktop">
        {loading ? (
          <OpsLoading label="Loading posts…" />
        ) : filtered.length === 0 ? (
          <OpsEmpty title={items.length === 0 ? 'No posts' : 'No matches'}>{emptyBody}</OpsEmpty>
        ) : (
          <table className="ops-table">
            <thead>
              <tr>
                <th>Title</th>
                <th>Kind</th>
                <th className="ops-col-hide-md">Category</th>
                <th className="ops-col-hide-md">Audience</th>
                <th>Priority</th>
                <th>Status</th>
                <th className="ops-col-actions">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((item) => (
                <tr key={item.id}>
                  <td>
                    <div className="ops-cell-title">{item.title}</div>
                    <div className="ops-cell-sub">{item.summary || item.body.slice(0, 80)}</div>
                    {item.external_url ? (
                      <div className="ops-cell-sub">
                        <a className="ops-cell-link" href={item.external_url} target="_blank" rel="noopener noreferrer">
                          {item.external_url}
                        </a>
                      </div>
                    ) : null}
                  </td>
                  <td style={{ textTransform: 'capitalize' }}>{item.kind}</td>
                  <td className="ops-col-hide-md">{categoriesForKind(item.kind)[item.category ?? ''] ?? '—'}</td>
                  <td className="ops-col-hide-md" style={{ textTransform: 'capitalize' }}>{item.audience}</td>
                  <td><span className={priorityChip(item.priority)}>{item.priority}</span></td>
                  <td><span className={statusChip(item.status)}>{item.status}</span></td>
                  <td className="ops-col-actions">
                    <PostActions
                      item={item}
                      busy={busy === item.id}
                      onPublish={() => publish(item)}
                      onEdit={() => openEdit(item)}
                      onArchive={() => archive(item)}
                      onDelete={() => remove(item)}
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="ops-card-list" aria-label="Posts">
        {loading ? (
          <OpsLoading label="Loading posts…" />
        ) : filtered.length === 0 ? (
          <OpsEmpty title={items.length === 0 ? 'No posts' : 'No matches'}>{emptyBody}</OpsEmpty>
        ) : (
          filtered.map((item) => (
            <article key={item.id} className="ops-card">
              <div className="ops-card-top">
                <div style={{ minWidth: 0, flex: 1 }}>
                  <h3 className="ops-card-title">{item.title}</h3>
                  <p className="ops-card-sub">{item.summary || item.body.slice(0, 120)}</p>
                  {item.external_url ? (
                    <p className="ops-card-sub">
                      <a href={item.external_url} target="_blank" rel="noopener noreferrer">
                        Open link
                      </a>
                    </p>
                  ) : null}
                  <div className="ops-chip-row">
                    <span className="ops-chip muted">{item.kind}</span>
                    <span className={priorityChip(item.priority)}>{item.priority}</span>
                    <span className={statusChip(item.status)}>{item.status}</span>
                    {item.category ? (
                      <span className="ops-chip cyan">
                        {categoriesForKind(item.kind)[item.category] ?? item.category}
                      </span>
                    ) : null}
                  </div>
                </div>
              </div>
              <div className="ops-card-actions">
                <PostActions
                  item={item}
                  busy={busy === item.id}
                  onPublish={() => publish(item)}
                  onEdit={() => openEdit(item)}
                  onArchive={() => archive(item)}
                  onDelete={() => remove(item)}
                />
              </div>
            </article>
          ))
        )}
      </div>
    </>
  );
}

function PostActions({
  item,
  busy,
  onPublish,
  onEdit,
  onArchive,
  onDelete,
}: {
  item: Post;
  busy: boolean;
  onPublish: () => void;
  onEdit: () => void;
  onArchive: () => void;
  onDelete: () => void;
}) {
  return (
    <div className="ops-row-actions">
      <button className="ops-btn primary" type="button" disabled={busy || item.status === 'published'} onClick={onPublish}>
        Publish
      </button>
      <button className="ops-btn" type="button" disabled={busy || item.status === 'archived'} onClick={onEdit}>
        Edit
      </button>
      <button className="ops-btn" type="button" disabled={busy || item.status === 'archived'} onClick={onArchive}>
        Archive
      </button>
      <button className="ops-btn danger" type="button" disabled={busy} onClick={onDelete}>
        Delete
      </button>
    </div>
  );
}
