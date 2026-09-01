'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { FormEvent, useCallback, useEffect, useState } from 'react';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import type { AttendanceDashboard, AttendanceHistoryItem } from '@/lib/api/attendance';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';
import './attendance.css';

function formatDate(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString();
}

export default function AttendanceLandingPage() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [dashboard, setDashboard] = useState<AttendanceDashboard | null>(null);
  const [history, setHistory] = useState<AttendanceHistoryItem[]>([]);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [title, setTitle] = useState('Honors Class');
  const [presentMinutes, setPresentMinutes] = useState(3);
  const [lateMinutes, setLateMinutes] = useState(2);
  const [busy, setBusy] = useState(false);
  const [flash, setFlash] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const [dash, items] = await Promise.all([
        apiFetch<AttendanceDashboard>('/admin/attendance/honors', token),
        apiFetch<AttendanceHistoryItem[]>('/admin/attendance/honors/history', token),
      ]);
      setDashboard(dash);
      setHistory(items);
    } catch (err) {
      setError(toUserMessage(err, 'Could not load attendance.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function startSession(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setFlash(null);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const session = await apiFetch<{ id: string }>('/admin/attendance/honors/sessions', token, {
        method: 'POST',
        body: JSON.stringify({
          title: title.trim() || 'Honors Class',
          present_window_seconds: presentMinutes * 60,
          late_window_seconds: lateMinutes * 60,
        }),
      });
      setDialogOpen(false);
      router.push(`/dashboard/attendance/${session.id}`);
    } catch (err) {
      setFlash(toUserMessage(err, 'Could not start attendance.'));
    } finally {
      setBusy(false);
    }
  }

  if (loading) return <OpsLoading label="Loading attendance…" />;

  return (
    <div>
      <div className="ops-top">
        <div>
          <h1>Honors Attendance</h1>
          <p>Start a session, display the classroom QR, and review Honors student check-ins.</p>
        </div>
        <button className="ops-btn primary" type="button" onClick={() => setDialogOpen(true)}>
          Start Attendance
        </button>
      </div>

      {error ? <p className="ops-status error">{error}</p> : null}
      {flash ? <p className="ops-status">{flash}</p> : null}

      <section className="ops-table-wrap" style={{ marginTop: 18 }}>
        <div style={{ padding: '16px 18px', borderBottom: '1px solid #efecf5' }}>
          <strong>Today</strong>
          <div className="ops-cell-sub" style={{ marginTop: 4 }}>
            {dashboard?.honors_student_count ?? 0} active Honors students on the roster
          </div>
        </div>
        {dashboard?.active_session ? (
          <div style={{ padding: '18px' }}>
            <div className="ops-cell-title">{dashboard.active_session.title}</div>
            <div className="ops-cell-sub" style={{ marginTop: 4 }}>
              Attendance is open · {dashboard.checked_in_count ?? 0} / {dashboard.honors_student_count} checked in
            </div>
            <div style={{ marginTop: 14 }}>
              <Link className="ops-btn primary" href={`/dashboard/attendance/${dashboard.active_session.id}`}>
                Open live session
              </Link>
            </div>
          </div>
        ) : (
          <div style={{ padding: '18px' }}>
            <div className="ops-cell-title">No active attendance session</div>
            <div className="ops-cell-sub" style={{ marginTop: 4 }}>
              Start attendance when class begins.
            </div>
          </div>
        )}
      </section>

      <div className="ops-toolbar" style={{ marginTop: 22 }}>
        <strong>Recent sessions</strong>
      </div>

      {history.length === 0 ? (
        <OpsEmpty title="No sessions yet">Start your first Honors attendance session above.</OpsEmpty>
      ) : (
        <div className="ops-table-wrap">
          <table className="ops-table">
            <thead>
              <tr>
                <th>Session</th>
                <th>When</th>
                <th>Present</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {history.map((item) => (
                <tr key={item.session.id}>
                  <td>
                    <Link href={`/dashboard/attendance/${item.session.id}`} className="ops-cell-title">
                      {item.session.title}
                    </Link>
                  </td>
                  <td>{formatDate(item.session.opened_at)}</td>
                  <td>
                    {item.present_count + item.late_count} / {item.honors_student_count}
                  </td>
                  <td style={{ textTransform: 'capitalize' }}>{item.session.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {dialogOpen ? (
        <div className="attendance-start-dialog" role="dialog" aria-modal="true" aria-label="Start Honors attendance">
          <div className="attendance-start-dialog-backdrop" onClick={() => setDialogOpen(false)} aria-hidden />
          <form className="attendance-start-dialog-card" onSubmit={(e) => void startSession(e)}>
            <h2>Start Honors Attendance</h2>
            <label>
              Class title
              <input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={160} required />
            </label>
            <label>
              Present window (minutes)
              <input
                type="number"
                min={1}
                max={60}
                value={presentMinutes}
                onChange={(e) => setPresentMinutes(Number(e.target.value))}
                required
              />
            </label>
            <label>
              Late check-in (minutes)
              <input
                type="number"
                min={0}
                max={60}
                value={lateMinutes}
                onChange={(e) => setLateMinutes(Number(e.target.value))}
                required
              />
            </label>
            <div className="attendance-start-actions">
              <button className="ops-btn" type="button" onClick={() => setDialogOpen(false)} disabled={busy}>
                Cancel
              </button>
              <button className="ops-btn primary" type="submit" disabled={busy}>
                {busy ? 'Starting…' : 'Start Attendance'}
              </button>
            </div>
          </form>
        </div>
      ) : null}
    </div>
  );
}
