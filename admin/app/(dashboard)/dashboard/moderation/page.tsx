'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import { apiFetch, toUserMessage } from '@/lib/api/client';
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

function reportType(r: Report): string {
  if (r.message_id) return 'Message';
  if (r.activity_id) return 'Activity';
  if (r.group_id) return 'Group';
  if (r.reported_user_id) return 'User';
  return 'Other';
}

function typeChip(type: string): string {
  if (type === 'Message') return 'ops-chip cyan';
  if (type === 'Activity') return 'ops-chip orange';
  if (type === 'Group') return 'ops-chip warn';
  return 'ops-chip';
}

function relativeWhen(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const diff = Date.now() - d.getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'Just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  return d.toLocaleDateString();
}

export default function ModerationPage() {
  const [reports, setReports] = useState<Report[]>([]);
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [status, setStatus] = useState('');
  const [flash, setFlash] = useState<string | null>(null);
  const [q, setQ] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [typeFilter, setTypeFilter] = useState('all');
  const [selected, setSelected] = useState<Report | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const [r, u] = await Promise.all([
        apiFetch<Report[]>('/admin/reports', token),
        apiFetch<AdminUser[]>('/admin/users', token),
      ]);
      setReports(r);
      setUsers(u);
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

  const usersById = useMemo(() => {
    const map = new Map<string, AdminUser>();
    for (const u of users) map.set(u.id, u);
    return map;
  }, [users]);

  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return reports.filter((r) => {
      if (statusFilter !== 'all' && r.status !== statusFilter) return false;
      const type = reportType(r);
      if (typeFilter !== 'all' && type !== typeFilter) return false;
      if (!needle) return true;
      const reported = r.reported_user_id ? usersById.get(r.reported_user_id) : undefined;
      const hay = [
        r.reason,
        r.details || '',
        r.message_body || '',
        reported?.email || '',
        reported?.display_name || '',
        r.id,
      ]
        .join(' ')
        .toLowerCase();
      return hay.includes(needle);
    });
  }, [reports, q, statusFilter, typeFilter, usersById]);

  async function suspend(userId: string, label: string, reason: string | null) {
    if (!window.confirm(`Suspend ${label}? They will be signed out and blocked from the app.`)) return;
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/users/${userId}/suspend`, token, {
        method: 'POST',
        body: JSON.stringify({ reason: reason?.trim() || null }),
      });
      setError(false);
      setFlash(`Suspended ${label}.`);
      setSelected(null);
      await load();
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not suspend this account. Please try again.'));
    }
  }

  async function removeActivity(activityId: string) {
    if (!window.confirm('Take down this activity? It will be cancelled and removed from student feeds.')) return;
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/activities/${activityId}/remove`, token, { method: 'POST' });
      setError(false);
      setFlash('Activity taken down.');
      setSelected(null);
      await load();
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not take down the activity'));
    }
  }

  function userLabel(u: AdminUser | undefined, fallbackId: string): string {
    if (!u) return fallbackId;
    return u.display_name || u.email;
  }

  return (
    <>
      <header className="ops-top">
        <div>
          <h1>Moderation</h1>
          <p>Review reports and take proportionate action on abusive content or accounts.</p>
        </div>
      </header>
      <div className="content" style={{ paddingTop: 8 }}>
        {error ? <div className="error-banner">{status}</div> : null}

        <div className="ops-toolbar">
          <div className="ops-search">
            <input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Search by reported user, reason, or report text"
              aria-label="Search reports"
            />
          </div>
          <select className="ops-select" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} aria-label="Status">
            <option value="all">All statuses</option>
            <option value="open">Open</option>
            <option value="resolved">Resolved</option>
            <option value="dismissed">Dismissed</option>
          </select>
          <select className="ops-select" value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)} aria-label="Type">
            <option value="all">All types</option>
            <option value="Message">Message</option>
            <option value="Activity">Activity</option>
            <option value="User">User</option>
            <option value="Group">Group</option>
          </select>
          <span className="ops-count">{loading ? '…' : `${filtered.length} shown`}</span>
          <button className="ops-btn" type="button" disabled={loading} onClick={() => void load()}>Refresh</button>
        </div>

        {flash ? <p className="ops-flash">{flash}</p> : null}

        <div className="ops-table-wrap table-scroll">
          {loading ? (
            <OpsLoading label="Loading reports…" />
          ) : filtered.length === 0 ? (
            <OpsEmpty title={reports.length === 0 ? 'No reports' : 'No matches'}>
              {reports.length === 0
                ? 'No moderation reports have been submitted yet.'
                : 'Try adjusting your search or filters.'}
            </OpsEmpty>
          ) : (
            <table className="ops-table">
              <thead>
                <tr>
                  <th>Report</th>
                  <th>Reported Subject</th>
                  <th>Type</th>
                  <th>Reason</th>
                  <th>Submitted</th>
                  <th>Status</th>
                  <th>Review</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((r) => {
                  const reported = r.reported_user_id ? usersById.get(r.reported_user_id) : undefined;
                  const label = userLabel(reported, r.reported_user_id || '—');
                  const type = reportType(r);
                  return (
                    <tr key={r.id}>
                      <td>
                        <div className="ops-cell-title">#{r.id.slice(0, 8)}</div>
                        <div className="ops-cell-sub">{(r.details || r.message_body || 'No details').slice(0, 80)}</div>
                      </td>
                      <td>{label}</td>
                      <td><span className={typeChip(type)}>{type}</span></td>
                      <td style={{ textTransform: 'capitalize' }}>{r.reason.replaceAll('_', ' ')}</td>
                      <td>{relativeWhen(r.created_at)}</td>
                      <td>
                        <span className={r.status === 'open' ? 'ops-chip warn' : 'ops-chip muted'}>
                          {r.status}
                        </span>
                      </td>
                      <td>
                        <button className="ops-btn primary" type="button" onClick={() => setSelected(r)}>
                          Review
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {selected ? (
        <>
          <div className="ops-drawer-backdrop" onClick={() => setSelected(null)} aria-hidden />
          <aside className="ops-drawer" role="dialog" aria-label="Review report">
            {(() => {
              const reported = selected.reported_user_id
                ? usersById.get(selected.reported_user_id)
                : undefined;
              const label = userLabel(reported, selected.reported_user_id || '—');
              const type = reportType(selected);
              return (
                <>
                  <div className="ops-drawer-head">
                    <div>
                      <h2>Report #{selected.id.slice(0, 8)}</h2>
                      <div className="ops-drawer-meta">
                        <span className={typeChip(type)}>{type}</span>{' '}
                        <span className={selected.status === 'open' ? 'ops-chip warn' : 'ops-chip muted'}>
                          {selected.status}
                        </span>
                      </div>
                    </div>
                    <button className="ops-drawer-close" type="button" aria-label="Close" onClick={() => setSelected(null)}>
                      ✕
                    </button>
                  </div>

                  <div className="ops-drawer-grid">
                    <div className="ops-drawer-field">
                      <label>Reported subject</label>
                      <div>{label}</div>
                    </div>
                    <div className="ops-drawer-field">
                      <label>Reason</label>
                      <div style={{ textTransform: 'capitalize' }}>{selected.reason.replaceAll('_', ' ')}</div>
                    </div>
                    <div className="ops-drawer-field">
                      <label>Submitted</label>
                      <div>{relativeWhen(selected.created_at)}</div>
                    </div>
                    <div className="ops-drawer-field">
                      <label>Account status</label>
                      <div>{reported?.status ?? '—'}</div>
                    </div>
                  </div>

                  {selected.details ? (
                    <div className="field">
                      <label>Details</label>
                      <p className="meta" style={{ margin: 0 }}>{selected.details}</p>
                    </div>
                  ) : null}
                  {selected.message_body ? (
                    <div className="field">
                      <label>Quoted message</label>
                      <p className="meta" style={{ margin: 0, fontStyle: 'italic' }}>“{selected.message_body}”</p>
                    </div>
                  ) : null}

                  <div className="ops-drawer-footer" style={{ flexDirection: 'column' }}>
                    {selected.reported_user_id && reported && reported.status === 'active' ? (
                      <button
                        className="btn danger"
                        type="button"
                        onClick={() => void suspend(selected.reported_user_id!, label, `Report: ${selected.reason}`)}
                      >
                        Suspend {label}
                      </button>
                    ) : null}
                    {selected.activity_id ? (
                      <button
                        className="btn danger"
                        type="button"
                        onClick={() => void removeActivity(selected.activity_id!)}
                      >
                        Take down activity
                      </button>
                    ) : null}
                    {!selected.activity_id &&
                    !(selected.reported_user_id && reported && reported.status === 'active') ? (
                      <p className="status" style={{ margin: 0 }}>
                        No further actions available for this report with current APIs.
                      </p>
                    ) : null}
                  </div>
                </>
              );
            })()}
          </aside>
        </>
      ) : null}
    </>
  );
}
