'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { RefreshIcon } from '@/components/admin-page';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import RowMenu from '@/components/row-menu';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';
import { categoriesForKind, priorityChip, statusChip, type Post } from './post-shared';

export default function PostsPanel({
  flash,
  onEdit,
  onCreate,
}: {
  /** A message from the compose view ("Published.") to show above the list. */
  flash: string | null;
  onEdit: (post: Post) => void;
  onCreate: () => void;
}) {
  const [items, setItems] = useState<Post[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [status, setStatus] = useState('');
  const [message, setMessage] = useState<string | null>(flash);
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

  async function run(id: string, label: string, doIt: (token: string) => Promise<void>) {
    if (busy) return;
    setBusy(id);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      await doIt(token);
      setMessage(label);
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
      <div className="post-toolbar">
        <div className="post-search">
          <SearchIcon />
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search posts" aria-label="Search posts" />
        </div>
        <select className="post-filter" value={filterKind} onChange={(e) => setFilterKind(e.target.value)} aria-label="Type">
          <option value="all">All types</option>
          <option value="announcement">Announcements</option>
          <option value="opportunity">Opportunities</option>
        </select>
        <select className="post-filter" value={filterStatus} onChange={(e) => setFilterStatus(e.target.value)} aria-label="Status">
          <option value="all">All statuses</option>
          <option value="draft">Drafts</option>
          <option value="published">Published</option>
          <option value="archived">Archived</option>
        </select>
        <span className="post-count">{loading ? 'Loading…' : `${filtered.length} of ${items.length} posts`}</span>
        <button className="btn-quiet" type="button" disabled={loading} onClick={() => void load()}>
          <RefreshIcon spinning={loading} />
          Refresh
        </button>
      </div>

      {error ? <div className="error-banner">{status}</div> : null}
      {message ? <p className="post-flash" role="status">{message}</p> : null}

      {loading ? (
        <OpsLoading label="Loading posts…" />
      ) : filtered.length === 0 ? (
        <OpsEmpty title={items.length === 0 ? 'No posts yet' : 'No matches'}>
          {emptyBody}
          {items.length === 0 ? (
            <div style={{ marginTop: 16 }}>
              <button className="btn-primary" type="button" onClick={onCreate}>New post</button>
            </div>
          ) : null}
        </OpsEmpty>
      ) : (
        <ul className="ruled-list card post-list" aria-label="Posts">
          {filtered.map((item) => (
            <li key={item.id} className="post-row">
              <div className="post-row-copy">
                <span className="post-row-title">{item.title}</span>
                <span className="post-row-sub">{item.summary || item.body.slice(0, 120)}</span>
                <span className="post-row-meta">
                  <span className={statusChip(item.status)}>{STATUS_LABEL[item.status] ?? item.status}</span>
                  {item.priority !== 'normal' ? (
                    <span className={priorityChip(item.priority)}>{PRIORITY_LABEL[item.priority] ?? item.priority}</span>
                  ) : null}
                  <span>{metaLine(item)}</span>
                </span>
              </div>
              <div className="post-row-actions">
                {/* One obvious next step per row: publish a draft, otherwise edit. */}
                {item.status === 'draft' ? (
                  <button className="btn-secondary" type="button" disabled={busy === item.id} onClick={() => publish(item)}>
                    Publish
                  </button>
                ) : null}
                {item.status !== 'archived' ? (
                  <button className="btn-quiet" type="button" disabled={busy === item.id} onClick={() => onEdit(item)}>
                    Edit
                  </button>
                ) : null}
                <RowMenu
                  label={`More actions for ${item.title}`}
                  items={[
                    { label: 'Archive', disabled: item.status === 'archived', onSelect: () => archive(item) },
                    { label: 'Delete permanently', danger: true, onSelect: () => remove(item) },
                  ]}
                />
              </div>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}

const STATUS_LABEL: Record<string, string> = { draft: 'Draft', published: 'Published', archived: 'Archived' };
const PRIORITY_LABEL: Record<string, string> = { important: 'Important', urgent: 'Urgent' };
const AUDIENCE_LABEL: Record<string, string> = { all: 'Everyone', students: 'Students', staff: 'Staff' };

/** "Opportunity · Internships · Students" — the facts that tell posts apart, on one line. */
function metaLine(item: Post): string {
  return [
    item.kind === 'opportunity' ? 'Opportunity' : 'Announcement',
    categoriesForKind(item.kind)[item.category ?? ''],
    AUDIENCE_LABEL[item.audience] ?? item.audience,
  ]
    .filter(Boolean)
    .join(' · ');
}

function SearchIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-3.5-3.5" />
    </svg>
  );
}
