'use client';

import { useCallback, useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type EmployerOrganization = {
  id: string;
  name: string;
  status: string;
  contact_email: string;
  contact_name: string | null;
  review_note: string | null;
};

type Tab = 'pending' | 'approved' | 'rejected';

export default function EmployersPage() {
  const [tab, setTab] = useState<Tab>('pending');
  const [items, setItems] = useState<EmployerOrganization[]>([]);
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
      const data = await apiFetch<EmployerOrganization[]>(`/admin/employers?status=${which}`, token);
      setItems(data);
      setStatus(data.length ? `${data.length} ${which} organization(s).` : `No ${which} organizations.`);
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Failed to load');
    }
  }, []);

  useEffect(() => {
    void load(tab);
  }, [load, tab]);

  async function act(id: string, action: 'approve' | 'reject', label: string) {
    setBusy(id);
    try {
      const token = await getAccessToken();
      if (!token) return;
      const body = action === 'reject' ? JSON.stringify({ reason: notes[id]?.trim() || null }) : undefined;
      await apiFetch(`/admin/employers/${id}/${action}`, token, { method: 'POST', body });
      setError(false);
      setStatus(`${action[0].toUpperCase() + action.slice(1)}d ${label}.`);
      await load(tab);
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : `${action} failed`);
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <header className="topbar">
        <div>
          <h1>Employer Partners</h1>
          <p>Review employer organization applications — Blueprint Bond</p>
        </div>
        <div className="tabs">
          <button type="button" className={`tab${tab === 'pending' ? ' active' : ''}`} onClick={() => setTab('pending')}>
            Pending
          </button>
          <button
            type="button"
            className={`tab${tab === 'approved' ? ' active' : ''}`}
            onClick={() => setTab('approved')}
          >
            Approved
          </button>
          <button
            type="button"
            className={`tab${tab === 'rejected' ? ' active' : ''}`}
            onClick={() => setTab('rejected')}
          >
            Rejected
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
          <div className="panel empty">{`No ${tab} organizations.`}</div>
        ) : (
          <div className="card-list">
            {items.map((item) => {
              const label = item.name;
              return (
                <article key={item.id} className="card">
                  <div className="card-head">
                    <div>
                      <h3>{label}</h3>
                      <p className="meta">
                        {item.contact_name ? `${item.contact_name} · ` : ''}
                        {item.contact_email}
                      </p>
                      {item.review_note && <p className="meta">Note: {item.review_note}</p>}
                    </div>
                    <span
                      className={
                        tab === 'approved' ? 'badge success' : tab === 'rejected' ? 'badge danger' : 'badge'
                      }
                    >
                      {item.status}
                    </span>
                  </div>

                  {tab === 'pending' && (
                    <>
                      <div className="field" style={{ marginTop: 12, marginBottom: 0 }}>
                        <label htmlFor={`note-${item.id}`}>Note (sent on reject)</label>
                        <textarea
                          id={`note-${item.id}`}
                          rows={2}
                          value={notes[item.id] || ''}
                          onChange={(e) => setNotes((prev) => ({ ...prev, [item.id]: e.target.value }))}
                          placeholder="Optional"
                        />
                      </div>
                      <div className="actions">
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
                      </div>
                    </>
                  )}
                </article>
              );
            })}
          </div>
        )}
      </div>
    </>
  );
}
