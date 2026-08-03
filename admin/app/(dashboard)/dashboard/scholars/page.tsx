'use client';

import { useCallback, useEffect, useState } from 'react';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
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

function initials(name: string | null, email: string): string {
  const source = (name || email.split('@')[0]).replace(/[._-]+/g, ' ').trim();
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

function when(iso: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString();
}

export default function ScholarsPage() {
  const [tab, setTab] = useState<Tab>('active');
  const [activeIds, setActiveIds] = useState<Set<string>>(new Set());
  const [items, setItems] = useState<ProgramMembership[]>([]);
  const [activeCount, setActiveCount] = useState(0);
  const [revokedCount, setRevokedCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [status, setStatus] = useState('');
  const [flash, setFlash] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const [query, setQuery] = useState('');
  const [candidates, setCandidates] = useState<StudentResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [searchNote, setSearchNote] = useState('');
  const [verifying, setVerifying] = useState<string | null>(null);

  const loadCounts = useCallback(async (token: string) => {
    const [active, revoked] = await Promise.all([
      apiFetch<ProgramMembership[]>(`/admin/programs/${PROGRAM_SLUG}/members?status=active`, token),
      apiFetch<ProgramMembership[]>(`/admin/programs/${PROGRAM_SLUG}/members?status=revoked`, token),
    ]);
    setActiveCount(active.length);
    setRevokedCount(revoked.length);
    setActiveIds(new Set(active.map((m) => m.user_id)));
  }, []);

  const load = useCallback(async (which: Tab) => {
    setLoading(true);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<ProgramMembership[]>(
        `/admin/programs/${PROGRAM_SLUG}/members?status=${which}`,
        token,
      );
      setItems(data);
      await loadCounts(token);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    } finally {
      setLoading(false);
    }
  }, [loadCounts]);

  useEffect(() => {
    void load(tab);
  }, [load, tab]);

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
      setFlash(`Verified ${student.display_name || student.email} as a Presidential Scholar.`);
      setQuery('');
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
      setFlash(`Revoked ${label}.`);
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
      <header className="ops-top">
        <div>
          <h1>Presidential Scholars</h1>
          <p>Verify students from the official Presidential Scholars roster — Blueprint Bond.</p>
        </div>
      </header>

      <div className="content" style={{ paddingTop: 8 }}>
        {error ? <div className="error-banner">{status}</div> : null}

        <div className="dash-kpi-grid" style={{ gridTemplateColumns: 'repeat(2, minmax(0, 1fr))', marginBottom: 18 }}>
          <div className="dash-kpi">
            <div className="dash-kpi-icon tone-green">
              <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="#2DAA72" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                <circle cx="12" cy="9" r="5" />
                <path d="M8.5 13.2 7 21l5-2.6L17 21l-1.5-7.8" />
              </svg>
            </div>
            <div>
              <div className="dash-kpi-value">{activeCount}</div>
              <div className="dash-kpi-title">Active Scholars</div>
              <div className="dash-kpi-sub">Verified memberships</div>
            </div>
          </div>
          <div className="dash-kpi">
            <div className="dash-kpi-icon">
              <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="#736E7D" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                <circle cx="12" cy="12" r="9" />
                <path d="M8 12h8" />
              </svg>
            </div>
            <div>
              <div className="dash-kpi-value">{revokedCount}</div>
              <div className="dash-kpi-title">Revoked</div>
              <div className="dash-kpi-sub">Former memberships</div>
            </div>
          </div>
        </div>

        <section className="ops-form">
          <h2>Student directory</h2>
          <p className="hint" style={{ marginTop: 0 }}>
            Students never self-declare. Verify anyone on the official Presidential Scholars roster.
          </p>
          <div className="ops-toolbar" style={{ marginTop: 0, marginBottom: 12 }}>
            <div className="ops-search" style={{ maxWidth: 420 }}>
              <input
                type="search"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Filter by name or email…"
                aria-label="Search students"
                autoComplete="off"
              />
            </div>
            <span className="ops-count">{searching ? 'Searching…' : `${candidates.length} students`}</span>
          </div>
          {searchNote ? <p className="status">{searchNote}</p> : null}
          {searching ? (
            <div className="ops-table-wrap table-scroll">
              <OpsLoading label="Searching students…" />
            </div>
          ) : candidates.length > 0 ? (
            <div className="ops-table-wrap table-scroll">
              <table className="ops-table">
                <thead>
                  <tr>
                    <th>Student</th>
                    <th>Email</th>
                    <th>Account Status</th>
                    <th>Scholar Status</th>
                    <th>Action</th>
                  </tr>
                </thead>
                <tbody>
                  {candidates.map((s) => {
                    const alreadyScholar = activeIds.has(s.id);
                    return (
                      <tr key={s.id}>
                        <td>
                          <div className="ops-user-cell">
                            <div className="ops-avatar">{initials(s.display_name, s.email)}</div>
                            <div className="ops-cell-title">{s.display_name || '—'}</div>
                          </div>
                        </td>
                        <td>{s.email}</td>
                        <td>
                          <span className={s.status === 'active' ? 'ops-chip success' : 'ops-chip muted'}>
                            {s.status}
                          </span>
                        </td>
                        <td>
                          {alreadyScholar ? (
                            <span className="ops-chip success">Already a scholar</span>
                          ) : (
                            <span className="ops-cell-sub">Not verified</span>
                          )}
                        </td>
                        <td>
                          <div className="ops-row-actions">
                            <button
                              className="ops-btn primary"
                              type="button"
                              disabled={alreadyScholar || verifying === s.id}
                              onClick={() => void onVerify(s)}
                            >
                              {verifying === s.id ? 'Verifying…' : 'Verify'}
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          ) : null}
        </section>

        <div className="ops-toolbar">
          <div className="seg-tabs">
            <button type="button" className={`seg-tab${tab === 'active' ? ' active' : ''}`} onClick={() => setTab('active')}>
              Active{activeCount ? ` · ${activeCount}` : ''}
            </button>
            <button type="button" className={`seg-tab${tab === 'revoked' ? ' active' : ''}`} onClick={() => setTab('revoked')}>
              Revoked{revokedCount ? ` · ${revokedCount}` : ''}
            </button>
          </div>
          <button className="ops-btn" type="button" disabled={loading} onClick={() => void load(tab)}>Refresh</button>
        </div>

        {flash ? <p className="ops-flash">{flash}</p> : null}

        <div className="ops-table-wrap table-scroll">
          {loading ? (
            <OpsLoading label="Loading scholars…" />
          ) : items.length === 0 ? (
            <OpsEmpty title={tab === 'active' ? 'No active scholars' : 'No revoked scholars'}>
              {tab === 'active'
                ? 'No students have been verified as Presidential Scholars yet.'
                : 'No revoked scholar memberships.'}
            </OpsEmpty>
          ) : (
            <table className="ops-table">
              <thead>
                <tr>
                  <th>Scholar</th>
                  <th>Email</th>
                  <th>{tab === 'active' ? 'Verified' : 'Revoked'}</th>
                  <th>Status</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {items.map((item) => {
                  const label = item.display_name || item.user_email;
                  return (
                    <tr key={item.id}>
                      <td>
                        <div className="ops-user-cell">
                          <div className="ops-avatar">{initials(item.display_name, item.user_email)}</div>
                          <div className="ops-cell-title">{label}</div>
                        </div>
                      </td>
                      <td>{item.user_email}</td>
                      <td>{when(tab === 'active' ? item.verified_at : item.revoked_at)}</td>
                      <td>
                        <span className={tab === 'active' ? 'ops-chip success' : 'ops-chip muted'}>
                          {item.status}
                        </span>
                      </td>
                      <td>
                        {tab === 'active' ? (
                          <div className="ops-row-actions">
                            <button
                              className="ops-btn danger"
                              type="button"
                              disabled={busy === item.user_id}
                              onClick={() => void onRevoke(item)}
                            >
                              Revoke
                            </button>
                          </div>
                        ) : null}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </>
  );
}
