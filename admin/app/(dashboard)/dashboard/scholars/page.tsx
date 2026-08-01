'use client';

import { useCallback, useEffect, useState } from 'react';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type ProgramMembership = {
  id: string;
  user_id: string;
  status: string;
  verified_at: string | null;
  revoked_at: string | null;
  user_email: string;
  display_name: string | null;
};

type Tab = 'active' | 'revoked';

const PROGRAM_SLUG = 'presidential_scholars';

export default function ScholarsPage() {
  const [tab, setTab] = useState<Tab>('active');
  const [items, setItems] = useState<ProgramMembership[]>([]);
  const [status, setStatus] = useState('Loading…');
  const [error, setError] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);

  const [verifyEmail, setVerifyEmail] = useState('');
  const [verifying, setVerifying] = useState(false);

  const load = useCallback(async (which: Tab) => {
    setError(false);
    setStatus('Loading…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<ProgramMembership[]>(
        `/admin/programs/${PROGRAM_SLUG}/members?status=${which}`,
        token,
      );
      setItems(data);
      setStatus(data.length ? `${data.length} ${which} scholar(s).` : `No ${which} scholars.`);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    }
  }, []);

  useEffect(() => {
    void load(tab);
  }, [load, tab]);

  async function onVerify(e: React.FormEvent) {
    e.preventDefault();
    if (!verifyEmail.trim()) return;
    setVerifying(true);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      await apiFetch(`/admin/programs/${PROGRAM_SLUG}/members`, token, {
        method: 'POST',
        body: JSON.stringify({ email: verifyEmail.trim().toLowerCase() }),
      });
      setStatus(`Verified ${verifyEmail.trim()} as a Presidential Scholar.`);
      setVerifyEmail('');
      await load(tab);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not verify that code. Please try again.'));
    } finally {
      setVerifying(false);
    }
  }

  async function onRevoke(item: ProgramMembership) {
    const label = item.display_name || item.user_email;
    if (!window.confirm(`Revoke ${label}'s Presidential Scholar status?`)) return;
    setBusy(item.user_id);
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/programs/${PROGRAM_SLUG}/members/${item.user_id}/revoke`, token, {
        method: 'POST',
        body: JSON.stringify({ reason: null }),
      });
      setError(false);
      setStatus(`Revoked ${label}.`);
      await load(tab);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not revoke access. Please try again.'));
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <header className="topbar">
        <div>
          <h1>Presidential Scholars</h1>
          <p>Verify scholars from the official roster — Blueprint Bond</p>
        </div>
        <div className="tabs">
          <button type="button" className={`tab${tab === 'active' ? ' active' : ''}`} onClick={() => setTab('active')}>
            Active
          </button>
          <button
            type="button"
            className={`tab${tab === 'revoked' ? ' active' : ''}`}
            onClick={() => setTab('revoked')}
          >
            Revoked
          </button>
        </div>
      </header>
      <div className="content">
        <div className="panel">
          <h2>Verify a scholar</h2>
          <p className="hint">
            Students never self-declare — enter the email of a student on the official
            Presidential Scholars roster.
          </p>
          <form onSubmit={onVerify}>
            <div className="field">
              <label htmlFor="verify-email">Student email</label>
              <input
                id="verify-email"
                type="email"
                value={verifyEmail}
                onChange={(e) => setVerifyEmail(e.target.value)}
                placeholder="name@students.livingstone.edu"
                required
              />
            </div>
            <button className="btn" type="submit" disabled={verifying}>
              {verifying ? 'Verifying…' : 'Verify scholar'}
            </button>
          </form>
        </div>

        <div className="actions" style={{ justifyContent: 'space-between', alignItems: 'center' }}>
          <p className={`status${error ? ' error' : ''}`} style={{ margin: 0 }}>
            {status}
          </p>
          <button className="btn ghost" type="button" onClick={() => void load(tab)} style={{ width: 'auto' }}>
            Refresh
          </button>
        </div>

        {items.length === 0 ? (
          <div className="panel empty">{tab === 'active' ? 'No active scholars.' : 'No revoked scholars.'}</div>
        ) : (
          <div className="card-list">
            {items.map((item) => {
              const label = item.display_name || item.user_email;
              return (
                <article key={item.id} className="card">
                  <div className="card-head">
                    <div>
                      <h3>{label}</h3>
                      <p className="meta">{item.user_email}</p>
                    </div>
                    <span className={tab === 'active' ? 'badge success' : 'badge muted'}>{item.status}</span>
                  </div>
                  {tab === 'active' && (
                    <div className="actions">
                      <button
                        className="btn danger"
                        type="button"
                        disabled={busy === item.user_id}
                        onClick={() => void onRevoke(item)}
                      >
                        Revoke
                      </button>
                    </div>
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
