'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type Position = {
  id: string;
  display_name: string | null;
  user_email: string;
  user_role: string;
  official_title: string;
  department: string;
  category: string;
  contact_email: string;
  status: string;
};

type Tab = 'pending' | 'verified';

function initials(name: string | null, email: string): string {
  const source = (name || email.split('@')[0]).replace(/[._-]+/g, ' ').trim();
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

export default function PositionsPage() {
  const [tab, setTab] = useState<Tab>('pending');
  const [items, setItems] = useState<Position[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [status, setStatus] = useState('');
  const [flash, setFlash] = useState<string | null>(null);
  const [q, setQ] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('all');
  const [drawer, setDrawer] = useState<Position | null>(null);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async (which: Tab) => {
    setLoading(true);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const path =
        which === 'pending'
          ? '/admin/campus-positions/pending'
          : '/admin/campus-positions?status=verified';
      const data = await apiFetch<Position[]>(path, token);
      setItems(data);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load(tab);
    setDrawer(null);
    setNote('');
    setQ('');
    setCategoryFilter('all');
  }, [load, tab]);

  const categories = useMemo(
    () => Array.from(new Set(items.map((i) => i.category))).sort(),
    [items],
  );

  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return items.filter((item) => {
      if (categoryFilter !== 'all' && item.category !== categoryFilter) return false;
      if (!needle) return true;
      return (
        (item.display_name || '').toLowerCase().includes(needle) ||
        item.user_email.toLowerCase().includes(needle) ||
        item.official_title.toLowerCase().includes(needle) ||
        item.department.toLowerCase().includes(needle)
      );
    });
  }, [items, q, categoryFilter]);

  async function act(action: 'approve' | 'reject' | 'revoke', item: Position) {
    const label = item.display_name || item.user_email;
    setBusy(true);
    try {
      const token = await getAccessToken();
      if (!token) return;
      const body =
        action === 'approve'
          ? undefined
          : action === 'reject'
            ? JSON.stringify({ review_note: note.trim() || null })
            : JSON.stringify({ review_note: note.trim() || null, archive_posts: false });
      await apiFetch(`/admin/campus-positions/${item.id}/${action}`, token, { method: 'POST', body });
      setError(false);
      setFlash(`${action[0].toUpperCase() + action.slice(1)}d ${label}.`);
      setDrawer(null);
      setNote('');
      await load(tab);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, `Could not ${action} this item. Please try again.`));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <header className="ops-top">
        <div>
          <h1>Campus Positions</h1>
          <p>Review and manage verified campus roles for staff.</p>
        </div>
        <div className="seg-tabs">
          <button type="button" className={`seg-tab${tab === 'pending' ? ' active' : ''}`} onClick={() => setTab('pending')}>
            Pending{tab === 'pending' && items.length ? ` (${items.length})` : ''}
          </button>
          <button type="button" className={`seg-tab${tab === 'verified' ? ' active' : ''}`} onClick={() => setTab('verified')}>
            Verified
          </button>
        </div>
      </header>

      <div className="content" style={{ paddingTop: 8 }}>
        {error ? <div className="error-banner">{status}</div> : null}

        <div className="ops-toolbar">
          <div className="ops-search">
            <input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Search by person, title, department, or email"
              aria-label="Search positions"
            />
          </div>
          <select
            className="ops-select"
            value={categoryFilter}
            onChange={(e) => setCategoryFilter(e.target.value)}
            aria-label="Category"
          >
            <option value="all">All categories</option>
            {categories.map((c) => (
              <option key={c} value={c}>{c.replaceAll('_', ' ')}</option>
            ))}
          </select>
          <span className="ops-count">
            {tab === 'pending' ? `${filtered.length} pending` : `${filtered.length} verified`}
          </span>
          <button className="ops-btn" type="button" disabled={loading} onClick={() => void load(tab)}>Refresh</button>
        </div>

        {flash ? <p className="ops-flash">{flash}</p> : null}

        <div className="ops-table-wrap table-scroll">
          {loading ? (
            <OpsLoading label="Loading positions…" />
          ) : filtered.length === 0 ? (
            <OpsEmpty
              title={
                items.length === 0
                  ? tab === 'pending'
                    ? 'Nothing to review'
                    : 'No verified positions'
                  : 'No matches'
              }
            >
              {items.length === 0
                ? tab === 'pending'
                  ? 'No positions are waiting for review.'
                  : 'No verified positions yet.'
                : 'Try adjusting your search or category filter.'}
            </OpsEmpty>
          ) : (
            <table className="ops-table">
              <thead>
                <tr>
                  <th>Person</th>
                  <th>Official Position</th>
                  <th>Department</th>
                  <th>Category</th>
                  {tab === 'pending' ? <th>Contact</th> : <th>Status</th>}
                  <th>{tab === 'pending' ? 'Review' : 'Action'}</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((item) => {
                  const label = item.display_name || item.user_email;
                  return (
                    <tr key={item.id}>
                      <td>
                        <div className="ops-user-cell">
                          <div className="ops-avatar">{initials(item.display_name, item.user_email)}</div>
                          <div>
                            <div className="ops-cell-title">{label}</div>
                            <div className="ops-cell-sub">{item.user_email}</div>
                          </div>
                        </div>
                      </td>
                      <td>{item.official_title}</td>
                      <td>{item.department}</td>
                      <td style={{ textTransform: 'capitalize' }}>{item.category.replaceAll('_', ' ')}</td>
                      <td>
                        {tab === 'pending' ? (
                          item.contact_email
                        ) : (
                          <span className="ops-chip success">{item.status}</span>
                        )}
                      </td>
                      <td>
                        <div className="ops-row-actions">
                          {tab === 'pending' ? (
                            <button
                              className="ops-btn primary"
                              type="button"
                              onClick={() => {
                                setDrawer(item);
                                setNote('');
                              }}
                            >
                              Review
                            </button>
                          ) : (
                            <button
                              className="ops-btn danger"
                              type="button"
                              onClick={() => {
                                if (window.confirm(`Revoke ${label}'s verified position?`)) {
                                  void act('revoke', item);
                                }
                              }}
                            >
                              Revoke
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {drawer ? (
        <>
          <div className="ops-drawer-backdrop" onClick={() => setDrawer(null)} aria-hidden />
          <aside className="ops-drawer" role="dialog" aria-label="Review campus position">
            <div className="ops-drawer-head">
              <div className="ops-avatar" style={{ width: 48, height: 48, fontSize: 15 }}>
                {initials(drawer.display_name, drawer.user_email)}
              </div>
              <div>
                <h2>{drawer.display_name || drawer.user_email}</h2>
                <div className="ops-drawer-meta">
                  <span className="ops-chip warn">Pending review</span>
                </div>
              </div>
              <button className="ops-drawer-close" type="button" aria-label="Close" onClick={() => setDrawer(null)}>
                ✕
              </button>
            </div>

            <div className="ops-drawer-grid">
              <div className="ops-drawer-field">
                <label>User role</label>
                <div style={{ textTransform: 'capitalize' }}>{drawer.user_role}</div>
              </div>
              <div className="ops-drawer-field">
                <label>Category</label>
                <div style={{ textTransform: 'capitalize' }}>{drawer.category.replaceAll('_', ' ')}</div>
              </div>
              <div className="ops-drawer-field">
                <label>Official title</label>
                <div>{drawer.official_title}</div>
              </div>
              <div className="ops-drawer-field">
                <label>Department</label>
                <div>{drawer.department}</div>
              </div>
            </div>

            <div className="field">
              <label>User email</label>
              <div style={{ fontWeight: 600 }}>{drawer.user_email}</div>
            </div>
            <div className="field">
              <label>Contact email</label>
              <div style={{ fontWeight: 600 }}>{drawer.contact_email}</div>
            </div>
            <div className="field">
              <label htmlFor="review-note">Review note</label>
              <textarea
                id="review-note"
                rows={3}
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="Note sent if rejected"
              />
            </div>

            <div className="ops-drawer-footer">
              <button
                className="btn danger"
                type="button"
                disabled={busy}
                onClick={() => void act('reject', drawer)}
              >
                Reject
              </button>
              <button
                className="btn"
                type="button"
                disabled={busy}
                onClick={() => void act('approve', drawer)}
              >
                Approve position
              </button>
            </div>
          </aside>
        </>
      ) : null}
    </>
  );
}
