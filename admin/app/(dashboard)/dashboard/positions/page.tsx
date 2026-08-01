'use client';

import { useCallback, useEffect, useState } from 'react';
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

export default function PositionsPage() {
  const [tab, setTab] = useState<Tab>('pending');
  const [items, setItems] = useState<Position[]>([]);
  const [status, setStatus] = useState('Loading…');
  const [error, setError] = useState(false);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async (which: Tab) => {
    setError(false);
    setStatus('Loading…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const path =
        which === 'pending'
          ? '/admin/campus-positions/pending'
          : '/admin/campus-positions?status=verified';
      const data = await apiFetch<Position[]>(path, token);
      setItems(data);
      setStatus(
        data.length
          ? `${data.length} ${which} position(s).`
          : which === 'pending'
            ? 'No positions waiting for review.'
            : 'No verified positions.',
      );
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    }
  }, []);

  useEffect(() => {
    void load(tab);
  }, [load, tab]);

  async function act(id: string, action: 'approve' | 'reject' | 'revoke', label: string) {
    setBusy(id);
    try {
      const token = await getAccessToken();
      if (!token) return;
      const body =
        action === 'approve'
          ? undefined
          : action === 'reject'
            ? JSON.stringify({ review_note: notes[id]?.trim() || null })
            : JSON.stringify({ review_note: notes[id]?.trim() || null, archive_posts: false });
      await apiFetch(`/admin/campus-positions/${id}/${action}`, token, { method: 'POST', body });
      setError(false);
      setStatus(`${action[0].toUpperCase() + action.slice(1)}d ${label}.`);
      await load(tab);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, `Could not ${action} this item. Please try again.`));
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <header className="topbar">
        <div>
          <h1>Positions</h1>
          <p>Approve verified campus roles for staff</p>
        </div>
        <div className="tabs">
          <button type="button" className={`tab${tab === 'pending' ? ' active' : ''}`} onClick={() => setTab('pending')}>
            Pending
          </button>
          <button type="button" className={`tab${tab === 'verified' ? ' active' : ''}`} onClick={() => setTab('verified')}>
            Verified
          </button>
        </div>
      </header>
      <div className="content">
        <div className="actions" style={{ justifyContent: 'space-between', alignItems: 'center' }}>
          <p className={`status${error ? ' error' : ''}`} style={{ margin: 0 }}>
            {status}
          </p>
          <button className="btn ghost" type="button" onClick={() => void load(tab)} style={{ width: 'auto' }}>
            Refresh
          </button>
        </div>

        {items.length === 0 ? (
          <div className="panel empty">{tab === 'pending' ? 'Nothing to review.' : 'No verified positions.'}</div>
        ) : (
          <div className="card-list">
            {items.map((item) => {
              const label = item.display_name || item.user_email;
              return (
                <article key={item.id} className="card">
                  <div className="card-head">
                    <div>
                      <h3>{label}</h3>
                      <p className="meta">
                        {item.official_title} · {item.department} · {item.category.replaceAll('_', ' ')}
                      </p>
                      <p className="meta">
                        {item.user_email} · {item.user_role}
                      </p>
                    </div>
                    <span className={tab === 'verified' ? 'badge success' : 'badge'}>{item.status}</span>
                  </div>

                  <div className="field" style={{ marginTop: 12, marginBottom: 0 }}>
                    <label htmlFor={`note-${item.id}`}>
                      {tab === 'pending' ? 'Note (sent on reject)' : 'Note (sent on revoke)'}
                    </label>
                    <textarea
                      id={`note-${item.id}`}
                      rows={2}
                      value={notes[item.id] || ''}
                      onChange={(e) => setNotes((prev) => ({ ...prev, [item.id]: e.target.value }))}
                      placeholder="Optional"
                    />
                  </div>

                  <div className="actions">
                    {tab === 'pending' ? (
                      <>
                        <button
                          className="btn"
                          type="button"
                          disabled={busy === item.id}
                          onClick={() => void act(item.id, 'approve', label)}
                        >
                          Approve
                        </button>
                        <button
                          className="btn danger"
                          type="button"
                          disabled={busy === item.id}
                          onClick={() => void act(item.id, 'reject', label)}
                        >
                          Reject
                        </button>
                      </>
                    ) : (
                      <button
                        className="btn danger"
                        type="button"
                        disabled={busy === item.id}
                        onClick={() => {
                          if (window.confirm(`Revoke ${label}'s verified position?`)) {
                            void act(item.id, 'revoke', label);
                          }
                        }}
                      >
                        Revoke
                      </button>
                    )}
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </div>
    </>
  );
}
