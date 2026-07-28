'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api/client';
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

export default function PositionsPage() {
  const [items, setItems] = useState<Position[]>([]);
  const [status, setStatus] = useState('Load pending positions to begin.');
  const [error, setError] = useState(false);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [revokeId, setRevokeId] = useState('');
  const [revokeNote, setRevokeNote] = useState('');
  const [archivePosts, setArchivePosts] = useState(false);
  const [lookup, setLookup] = useState<Position | null>(null);

  const load = useCallback(async () => {
    setError(false);
    setStatus('Loading pending positions…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<Position[]>('/admin/campus-positions/pending', token);
      setItems(data);
      setStatus(data.length ? `${data.length} pending position(s).` : 'No pending campus positions.');
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Failed to load');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function approve(id: string, label: string) {
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/campus-positions/${id}/approve`, token, { method: 'POST' });
      setError(false);
      setStatus(`Approved ${label}.`);
      await load();
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Approve failed');
    }
  }

  async function reject(id: string, label: string) {
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/campus-positions/${id}/reject`, token, {
        method: 'POST',
        body: JSON.stringify({ review_note: notes[id]?.trim() || null }),
      });
      setError(false);
      setStatus(`Rejected ${label}.`);
      await load();
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Reject failed');
    }
  }

  async function lookupPosition(event: FormEvent) {
    event.preventDefault();
    setLookup(null);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<Position>(
        `/admin/campus-positions/${revokeId.trim()}`,
        token,
      );
      setLookup(data);
      setError(false);
      setStatus(`Loaded position ${data.id} (${data.status}).`);
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Lookup failed');
    }
  }

  async function revoke() {
    if (!lookup) return;
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/campus-positions/${lookup.id}/revoke`, token, {
        method: 'POST',
        body: JSON.stringify({
          review_note: revokeNote.trim() || null,
          archive_posts: archivePosts,
        }),
      });
      setError(false);
      setStatus(
        `Revoked ${lookup.display_name || lookup.user_email}.` +
          (archivePosts ? ' Their published posts were archived.' : ''),
      );
      setLookup(null);
      setRevokeId('');
      setRevokeNote('');
      setArchivePosts(false);
      await load();
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Revoke failed');
    }
  }

  return (
    <>
      <header className="topbar">
        <div>
          <h1>People &amp; Positions</h1>
          <p>Approve verified campus directory listings</p>
        </div>
        <button className="btn secondary" type="button" onClick={() => void load()} style={{ width: 'auto' }}>
          Refresh
        </button>
      </header>
      <div className="content">
        <p className={`status${error ? ' error' : ''}`}>{status}</p>
        <div className="card-list">
          {items.map((item) => {
            const label = item.display_name || item.user_email;
            return (
              <article key={item.id} className="card">
                <div className="card-head">
                  <div>
                    <h3>{label}</h3>
                    <p className="meta">
                      {item.user_email} · {item.user_role}
                    </p>
                  </div>
                  <span className="badge">{item.status}</span>
                </div>
                <p className="meta">
                  <strong>{item.official_title}</strong> · {item.department} ·{' '}
                  {item.category.replaceAll('_', ' ')}
                </p>
                <p className="meta">Contact: {item.contact_email}</p>
                <div className="field" style={{ marginTop: 12 }}>
                  <label htmlFor={`note-${item.id}`}>Review note (reject)</label>
                  <textarea
                    id={`note-${item.id}`}
                    rows={2}
                    value={notes[item.id] || ''}
                    onChange={(e) => setNotes((prev) => ({ ...prev, [item.id]: e.target.value }))}
                    placeholder="Optional note"
                  />
                </div>
                <div className="actions">
                  <button className="btn" type="button" onClick={() => void approve(item.id, label)}>
                    Approve
                  </button>
                  <button className="btn danger" type="button" onClick={() => void reject(item.id, label)}>
                    Reject
                  </button>
                </div>
              </article>
            );
          })}
        </div>

        <form className="panel" style={{ marginTop: 16 }} onSubmit={lookupPosition}>
          <h2>Revoke verified position</h2>
          <p className="meta" style={{ marginTop: 0 }}>
            Look up by position ID, then revoke if status is verified.
          </p>
          <div className="field">
            <label htmlFor="revoke-id">Position ID</label>
            <input
              id="revoke-id"
              value={revokeId}
              onChange={(e) => setRevokeId(e.target.value)}
              required
              placeholder="UUID"
            />
          </div>
          <button className="btn secondary" type="submit" style={{ width: 'auto' }}>
            Look up
          </button>
          {lookup ? (
            <div className="card" style={{ marginTop: 12 }}>
              <div className="card-head">
                <div>
                  <h3>{lookup.display_name || lookup.user_email}</h3>
                  <p className="meta">
                    {lookup.official_title} · {lookup.department}
                  </p>
                </div>
                <span className="badge">{lookup.status}</span>
              </div>
              <div className="field" style={{ marginTop: 12 }}>
                <label htmlFor="revoke-note">Review note</label>
                <textarea
                  id="revoke-note"
                  rows={2}
                  value={revokeNote}
                  onChange={(e) => setRevokeNote(e.target.value)}
                  placeholder="Optional note"
                />
              </div>
              <label
                className="meta"
                style={{ display: 'flex', gap: 8, alignItems: 'flex-start', marginTop: 12 }}
              >
                <input
                  type="checkbox"
                  checked={archivePosts}
                  onChange={(e) => setArchivePosts(e.target.checked)}
                  style={{ width: 'auto', marginTop: 3 }}
                />
                <span>
                  Also archive their published posts. Leave this off when the term simply
                  ended — past notices stay valid. Turn it on if the position was fraudulent
                  or misused.
                </span>
              </label>
              <div className="actions">
                <button
                  className="btn danger"
                  type="button"
                  disabled={lookup.status !== 'verified'}
                  onClick={() => void revoke()}
                >
                  Revoke
                </button>
              </div>
            </div>
          ) : null}
        </form>
      </div>
    </>
  );
}
