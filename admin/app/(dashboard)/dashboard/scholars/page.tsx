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

type StudentResult = {
  id: string;
  email: string;
  display_name: string | null;
  status: string;
};

type Tab = 'active' | 'revoked';

const PROGRAM_SLUG = 'presidential_scholars';

export default function ScholarsPage() {
  const [tab, setTab] = useState<Tab>('active');
  const [items, setItems] = useState<ProgramMembership[]>([]);
  const [status, setStatus] = useState('Loading…');
  const [error, setError] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);

  const [query, setQuery] = useState('');
  const [candidates, setCandidates] = useState<StudentResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [searchNote, setSearchNote] = useState('');
  const [verifying, setVerifying] = useState<string | null>(null);

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

  // Search server-side (the endpoint is capped, so filtering in the browser would silently hide
  // anyone past the cap), debounced so typing a name doesn't fire a request per keystroke.
  // An empty query intentionally still queries — the directory should be browsable on arrival,
  // not a blank box that only reveals students once you already know who you're looking for.
  useEffect(() => {
    const term = query.trim();
    let cancelled = false;
    setSearching(true);
    const timer = setTimeout(() => {
      void (async () => {
        try {
          const token = await getAccessToken();
          if (!token) return;
          const data = await apiFetch<StudentResult[]>(
            `/admin/users?role=student&q=${encodeURIComponent(term)}`,
            token,
          );
          if (cancelled) return;
          setCandidates(data);
          setSearchNote(
            data.length
              ? ''
              : term
                ? 'No students match that name or email.'
                : 'No students have signed in yet.',
          );
        } catch (err) {
          if (!cancelled) setSearchNote(toUserMessage(err, 'Could not search students.'));
        } finally {
          if (!cancelled) setSearching(false);
        }
      })();
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [query]);

  const activeScholarIds = new Set(items.filter((i) => i.status === 'active').map((i) => i.user_id));

  async function onVerify(student: StudentResult) {
    setVerifying(student.id);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      await apiFetch(`/admin/programs/${PROGRAM_SLUG}/members`, token, {
        method: 'POST',
        body: JSON.stringify({ email: student.email }),
      });
      setStatus(`Verified ${student.display_name || student.email} as a Presidential Scholar.`);
      setQuery('');
      setCandidates([]);
      await load(tab);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not verify that student. Please try again.'));
    } finally {
      setVerifying(null);
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
          <h2>Student directory</h2>
          <p className="hint" style={{ marginTop: 0 }}>
            Students never self-declare. Verify anyone on the official Presidential Scholars
            roster — search by name or email to narrow the list.
          </p>
          <div className="field" style={{ marginBottom: 0 }}>
            <label htmlFor="student-search">Search students</label>
            <input
              id="student-search"
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Filter by name or email…"
              autoComplete="off"
            />
          </div>

          {searching ? <p className="status">Searching…</p> : null}
          {!searching && searchNote ? <p className="status">{searchNote}</p> : null}

          {candidates.length > 0 ? (
            <div className="table-scroll" style={{ marginTop: 12 }}>
              <table className="rows">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Email</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {candidates.map((s) => {
                    const alreadyScholar = activeScholarIds.has(s.id);
                    return (
                      <tr key={s.id}>
                        <td>{s.display_name || '—'}</td>
                        <td>{s.email}</td>
                        <td style={{ textAlign: 'right' }}>
                          {alreadyScholar ? (
                            <span className="badge success">Already a scholar</span>
                          ) : (
                            <button
                              className="btn"
                              type="button"
                              style={{ width: 'auto', minHeight: 34, padding: '6px 12px', fontSize: 13 }}
                              disabled={verifying === s.id}
                              onClick={() => void onVerify(s)}
                            >
                              {verifying === s.id ? 'Verifying…' : 'Verify'}
                            </button>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          ) : null}
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
