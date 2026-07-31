'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { apiFetch } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type Report = {
  id: string;
  reporter_id: string;
  reported_user_id: string | null;
  activity_id: string | null;
  group_id: string | null;
  message_id: string | null;
  message_body: string | null;
  reason: string;
  details: string | null;
  status: string;
  created_at: string;
};

type AdminUser = {
  id: string;
  email: string;
  role: string;
  status: string;
  is_active: boolean;
  is_verified: boolean;
  display_name: string | null;
};

function when(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? iso : d.toLocaleString();
}

export default function ModerationPage() {
  const [reports, setReports] = useState<Report[]>([]);
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [status, setStatus] = useState('Loading…');
  const [error, setError] = useState(false);

  const load = useCallback(async () => {
    setError(false);
    setStatus('Loading…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const [r, u] = await Promise.all([
        apiFetch<Report[]>('/admin/reports', token),
        apiFetch<AdminUser[]>('/admin/users', token),
      ]);
      setReports(r);
      setUsers(u);
      setStatus(`${r.length} report(s).`);
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Failed to load');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const usersById = useMemo(() => {
    const map = new Map<string, AdminUser>();
    for (const u of users) map.set(u.id, u);
    return map;
  }, [users]);

  async function suspend(userId: string, label: string, reason: string | null) {
    const ok = window.confirm(`Suspend ${label}? They will be signed out and blocked from the app.`);
    if (!ok) return;
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/users/${userId}/suspend`, token, {
        method: 'POST',
        body: JSON.stringify({ reason: reason?.trim() || null }),
      });
      setError(false);
      setStatus(`Suspended ${label}.`);
      await load();
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Suspend failed');
    }
  }

  function userLabel(u: AdminUser | undefined, fallbackId: string): string {
    if (!u) return fallbackId;
    return u.display_name || u.email;
  }

  return (
    <>
      <header className="topbar">
        <div>
          <h1>Moderation</h1>
          <p>Review reports and act on abusive accounts</p>
        </div>
      </header>
      <div className="content">
        <div className="actions" style={{ justifyContent: 'space-between', alignItems: 'center', marginTop: 0 }}>
          <p className={`status${error ? ' error' : ''}`} style={{ margin: 0 }}>
            {status}
          </p>
          <button className="btn ghost" type="button" onClick={() => void load()} style={{ width: 'auto' }}>
            Refresh
          </button>
        </div>

        {reports.length === 0 ? (
          <div className="panel empty">No reports.</div>
        ) : (
          <div className="card-list">
            {reports.map((r) => {
              const reported = r.reported_user_id ? usersById.get(r.reported_user_id) : undefined;
              const label = userLabel(reported, r.reported_user_id || '—');
              return (
                <article key={r.id} className="card">
                  <div className="card-head">
                    <div>
                      <h3 style={{ textTransform: 'capitalize' }}>{r.reason.replaceAll('_', ' ')}</h3>
                      <p className="meta">
                        Reported: {label} · {when(r.created_at)}
                      </p>
                    </div>
                    <span className={r.status === 'open' ? 'badge' : 'badge muted'}>{r.status}</span>
                  </div>
                  {r.details ? <p className="meta">{r.details}</p> : null}
                  {r.message_body ? (
                    <p className="meta" style={{ fontStyle: 'italic' }}>
                      “{r.message_body}”
                    </p>
                  ) : null}
                  {r.reported_user_id && reported && reported.status === 'active' ? (
                    <div className="actions">
                      <button
                        className="btn danger"
                        type="button"
                        onClick={() => void suspend(r.reported_user_id!, label, `Report: ${r.reason}`)}
                      >
                        Suspend {label}
                      </button>
                    </div>
                  ) : reported && reported.status !== 'active' ? (
                    <p className="meta">Reported user is already {reported.status}.</p>
                  ) : null}
                </article>
              );
            })}
          </div>
        )}
      </div>
    </>
  );
}
