'use client';

import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { AttendanceQrDisplay } from '@/components/attendance/AttendanceQrDisplay';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import type {
  AttendanceQRPayload,
  AttendanceRoster,
  AttendanceRosterEntry,
} from '@/lib/api/attendance';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';
import '../attendance.css';

const ROSTER_POLL_MS = 3000;
const QR_POLL_MS = 8000;

function formatTime(iso: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

function sessionEndAt(session: AttendanceRoster['session']): Date {
  return new Date(session.late_until ?? session.present_until);
}

function remainingLabel(session: AttendanceRoster['session']): string {
  const end = sessionEndAt(session);
  const diffMs = end.getTime() - Date.now();
  if (diffMs <= 0) return 'Closing…';
  const mins = Math.floor(diffMs / 60000);
  const secs = Math.floor((diffMs % 60000) / 1000);
  return `${mins}:${secs.toString().padStart(2, '0')} remaining`;
}

function statusChip(status: string | null): string {
  if (status === 'present') return 'ops-chip success';
  if (status === 'late') return 'ops-chip warn';
  if (status === 'absent') return 'ops-chip danger';
  if (status === 'excused') return 'ops-chip';
  return 'ops-chip';
}

export default function AttendanceSessionPage() {
  const params = useParams<{ sessionId: string }>();
  const router = useRouter();
  const sessionId = params.sessionId;

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [roster, setRoster] = useState<AttendanceRoster | null>(null);
  const [qr, setQr] = useState<AttendanceQRPayload | null>(null);
  const [busy, setBusy] = useState(false);
  const [flash, setFlash] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [editing, setEditing] = useState<AttendanceRosterEntry | null>(null);
  const [newStatus, setNewStatus] = useState<'present' | 'late' | 'absent' | 'excused'>('present');
  const [reason, setReason] = useState('');
  const [liveStale, setLiveStale] = useState(false);

  const loadRoster = useCallback(async () => {
    const token = await getAccessToken();
    if (!token) throw new Error('Not signed in');
    return apiFetch<AttendanceRoster>(`/admin/attendance/sessions/${sessionId}/roster`, token);
  }, [sessionId]);

  const loadQr = useCallback(async () => {
    const token = await getAccessToken();
    if (!token) throw new Error('Not signed in');
    return apiFetch<AttendanceQRPayload>(`/admin/attendance/sessions/${sessionId}/qr`, token);
  }, [sessionId]);

  useEffect(() => {
    void (async () => {
      setLoading(true);
      setError('');
      try {
        const data = await loadRoster();
        setRoster(data);
        if (data.session.status === 'open') {
          setQr(await loadQr());
        }
      } catch (err) {
        setError(toUserMessage(err, 'Could not load this session.'));
      } finally {
        setLoading(false);
      }
    })();
  }, [loadQr, loadRoster]);

  const isOpen = roster?.session.status === 'open';

  useEffect(() => {
    if (!isOpen) return;
    // Polls keep the last good data on failure (the screen never wipes mid-class); a transient
    // network blip just flags the live feed as stale until the next poll succeeds.
    const rosterTimer = setInterval(() => {
      void loadRoster()
        .then((data) => {
          setRoster(data);
          setLiveStale(false);
        })
        .catch(() => setLiveStale(true));
    }, ROSTER_POLL_MS);
    const qrTimer = setInterval(() => {
      void loadQr()
        .then((data) => {
          setQr(data);
          setLiveStale(false);
        })
        .catch(() => setLiveStale(true));
    }, QR_POLL_MS);
    return () => {
      clearInterval(rosterTimer);
      clearInterval(qrTimer);
    };
  }, [isOpen, loadQr, loadRoster]);

  const filteredEntries = useMemo(() => {
    if (!roster) return [];
    const term = search.trim().toLowerCase();
    if (!term) return roster.entries;
    return roster.entries.filter((entry) => {
      const name = (entry.display_name || entry.email).toLowerCase();
      return name.includes(term);
    });
  }, [roster, search]);

  const recentCheckIns = useMemo(() => {
    if (!roster) return [];
    return roster.entries
      .filter((entry) => entry.checked_in_at)
      .sort((a, b) => new Date(b.checked_in_at || 0).getTime() - new Date(a.checked_in_at || 0).getTime())
      .slice(0, 8);
  }, [roster]);

  const progress = roster
    ? Math.min(100, Math.round((roster.checked_in_count / Math.max(roster.entries.length, 1)) * 100))
    : 0;

  async function endSession() {
    setBusy(true);
    setFlash(null);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      await apiFetch(`/admin/attendance/sessions/${sessionId}/close`, token, { method: 'POST' });
      const data = await loadRoster();
      setRoster(data);
      setQr(null);
      setFlash('Attendance ended. Absent rows were recorded for students who did not check in.');
    } catch (err) {
      setFlash(toUserMessage(err, 'Could not end attendance.'));
    } finally {
      setBusy(false);
    }
  }

  async function saveCorrection() {
    if (!editing?.record_id) return;
    setBusy(true);
    setFlash(null);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      await apiFetch(`/admin/attendance/records/${editing.record_id}`, token, {
        method: 'PATCH',
        body: JSON.stringify({ status: newStatus, reason: reason.trim() }),
      });
      setEditing(null);
      setReason('');
      setRoster(await loadRoster());
      setFlash('Attendance updated.');
    } catch (err) {
      setFlash(toUserMessage(err, 'Could not update attendance.'));
    } finally {
      setBusy(false);
    }
  }

  if (loading) return <OpsLoading label="Loading session…" />;
  if (!roster) return <OpsEmpty title="Session not found">{error || 'This attendance session could not be loaded.'}</OpsEmpty>;

  return (
    <div>
      <div className="ops-top">
        <div>
          <Link href="/dashboard/attendance" style={{ fontSize: 13, color: 'var(--muted)' }}>
            ← Honors Attendance
          </Link>
          <h1 style={{ marginTop: 8 }}>{roster.session.title}</h1>
          <p>
            {isOpen
              ? `Attendance open · ${remainingLabel(roster.session)}`
              : `Session closed · ${formatTime(roster.session.closed_at)}`}
          </p>
          {isOpen ? (
            <span className={`attendance-live-dot ${liveStale ? 'stale' : 'live'}`}>
              {liveStale ? 'Live updates paused — retrying…' : 'Live'}
            </span>
          ) : null}
        </div>
        {isOpen ? (
          <button className="ops-btn danger" type="button" onClick={() => void endSession()} disabled={busy}>
            End Attendance
          </button>
        ) : (
          <button className="ops-btn" type="button" onClick={() => router.push('/dashboard/attendance')}>
            Back to Attendance
          </button>
        )}
      </div>

      {error ? <p className="ops-status error">{error}</p> : null}
      {flash ? <p className="ops-status">{flash}</p> : null}

      <div className="attendance-stat-grid">
        {isOpen ? (
          <>
            <div className="attendance-stat">
              <strong>
                {roster.checked_in_count} / {roster.entries.length}
              </strong>
              <span>Checked in</span>
            </div>
            <div className="attendance-stat">
              <strong>{roster.present_count}</strong>
              <span>Present</span>
            </div>
            <div className="attendance-stat">
              <strong>{roster.late_count}</strong>
              <span>Late</span>
            </div>
            <div className="attendance-stat">
              <strong>{roster.remaining_count}</strong>
              <span>Remaining</span>
            </div>
          </>
        ) : (
          <>
            <div className="attendance-stat">
              <strong>{roster.present_count}</strong>
              <span>Present</span>
            </div>
            <div className="attendance-stat">
              <strong>{roster.late_count}</strong>
              <span>Late</span>
            </div>
            <div className="attendance-stat">
              <strong>{roster.absent_count}</strong>
              <span>Absent</span>
            </div>
            <div className="attendance-stat">
              <strong>{roster.excused_count}</strong>
              <span>Excused</span>
            </div>
          </>
        )}
      </div>

      {isOpen ? (
        <div className="attendance-progress" aria-hidden>
          <span style={{ width: `${progress}%` }} />
        </div>
      ) : null}

      <div className="attendance-live-grid">
        <section className="ops-table-wrap" style={{ padding: 18 }}>
          <strong>{isOpen ? 'Live roster' : 'Session review'}</strong>
          <div className="ops-search" style={{ marginTop: 12, maxWidth: '100%' }}>
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search students…"
              aria-label="Search students"
            />
          </div>
          <table className="ops-table" style={{ marginTop: 12 }}>
            <thead>
              <tr>
                <th>Student</th>
                <th>Status</th>
                <th>Time</th>
                {!isOpen ? <th /> : null}
              </tr>
            </thead>
            <tbody>
              {filteredEntries.map((entry) => (
                <tr key={entry.student_id}>
                  <td>
                    <div className="ops-cell-title">{entry.display_name || entry.email}</div>
                    <div className="ops-cell-sub">{entry.email}</div>
                  </td>
                  <td>
                    <span className={statusChip(entry.status)}>{entry.status || '—'}</span>
                  </td>
                  <td>{formatTime(entry.checked_in_at)}</td>
                  {!isOpen ? (
                    <td>
                      {entry.record_id ? (
                        <button
                          className="ops-btn"
                          type="button"
                          onClick={() => {
                            setEditing(entry);
                            setNewStatus((entry.status as typeof newStatus) || 'present');
                            setReason('');
                          }}
                        >
                          Edit
                        </button>
                      ) : null}
                    </td>
                  ) : null}
                </tr>
              ))}
            </tbody>
          </table>
        </section>

        <section>
          {isOpen && qr ? (
            <AttendanceQrDisplay payload={qr as unknown as Record<string, string | number>} />
          ) : (
            <div className="ops-table-wrap" style={{ padding: 18 }}>
              <strong>Session closed</strong>
              <p className="ops-cell-sub" style={{ marginTop: 8 }}>
                Select a student below to make a manual correction. All changes require a reason and are audit-logged.
              </p>
            </div>
          )}

          {isOpen ? (
            <div className="ops-table-wrap" style={{ padding: 18, marginTop: 16 }}>
              <strong>Recent check-ins</strong>
              {recentCheckIns.length === 0 ? (
                <p className="ops-cell-sub" style={{ marginTop: 10 }}>
                  Waiting for the first scan…
                </p>
              ) : (
                <ul className="attendance-recent-list" style={{ marginTop: 12 }}>
                  {recentCheckIns.map((entry) => (
                    <li key={`${entry.student_id}-${entry.checked_in_at}`}>
                      <span>{entry.display_name || entry.email}</span>
                      <span>{formatTime(entry.checked_in_at)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          ) : null}
        </section>
      </div>

      {editing ? (
        <>
          <div className="ops-drawer-backdrop" onClick={() => setEditing(null)} aria-hidden />
          <aside className="ops-drawer" role="dialog" aria-label="Edit attendance">
            <div className="ops-drawer-head">
              <div>
                <h2>{editing.display_name || editing.email}</h2>
                <div className="ops-drawer-meta">Manual correction</div>
              </div>
              <button className="ops-drawer-close" type="button" aria-label="Close" onClick={() => setEditing(null)}>
                ✕
              </button>
            </div>
            <div className="ops-drawer-grid">
              <div className="ops-drawer-field">
                <label htmlFor="attendance-status">Status</label>
                <select
                  id="attendance-status"
                  className="ops-select"
                  value={newStatus}
                  onChange={(e) => setNewStatus(e.target.value as typeof newStatus)}
                >
                  <option value="present">Present</option>
                  <option value="late">Late</option>
                  <option value="absent">Absent</option>
                  <option value="excused">Excused</option>
                </select>
              </div>
              <div className="ops-drawer-field">
                <label htmlFor="attendance-reason">Reason</label>
                <textarea
                  id="attendance-reason"
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  rows={4}
                  style={{ width: '100%', borderRadius: 12, border: '1px solid var(--border)', padding: 10 }}
                  placeholder="Required — e.g. Approved absence"
                />
              </div>
            </div>
            <div className="ops-drawer-footer">
              <button className="ops-btn" type="button" onClick={() => setEditing(null)} disabled={busy}>
                Cancel
              </button>
              <button className="ops-btn primary" type="button" onClick={() => void saveCorrection()} disabled={busy}>
                Save
              </button>
            </div>
          </aside>
        </>
      ) : null}
    </div>
  );
}
