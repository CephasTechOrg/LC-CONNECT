'use client';

import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { AttendanceCorrectionDrawer } from '@/components/attendance/AttendanceCorrectionDrawer';
import { AttendanceFeatureDisabled } from '@/components/attendance/AttendanceFeatureDisabled';
import { AttendanceQrDisplay } from '@/components/attendance/AttendanceQrDisplay';
import { AttendanceRosterList } from '@/components/attendance/AttendanceRosterList';
import {
  formatAttendanceDateTime,
  formatAttendanceTime,
  sortRosterEntries,
  studentLabel,
  type AttendanceStatus,
  type AttendanceStatusFilter,
} from '@/components/attendance/attendance-ui';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import type { AttendanceQRPayload, AttendanceRoster, AttendanceRosterEntry } from '@/lib/api/attendance';
import { fetchHonorsAttendanceStatus, isAttendanceDisabledError } from '@/lib/api/attendance';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';
import '../attendance.css';

const ROSTER_POLL_MS = 3000;
const QR_POLL_MS = 8000;

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

export default function AttendanceSessionPage() {
  const params = useParams<{ sessionId: string }>();
  const router = useRouter();
  const sessionId = params.sessionId;

  const [loading, setLoading] = useState(true);
  const [featureEnabled, setFeatureEnabled] = useState<boolean | null>(null);
  const [error, setError] = useState('');
  const [roster, setRoster] = useState<AttendanceRoster | null>(null);
  const [qr, setQr] = useState<AttendanceQRPayload | null>(null);
  const [busy, setBusy] = useState(false);
  const [flash, setFlash] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [editing, setEditing] = useState<AttendanceRosterEntry | null>(null);
  const [statusFilter, setStatusFilter] = useState<AttendanceStatusFilter>('all');
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
      setFeatureEnabled(null);
      try {
        const status = await fetchHonorsAttendanceStatus();
        setFeatureEnabled(status.enabled);
        if (!status.enabled) return;

        const data = await loadRoster();
        setRoster(data);
        if (data.session.status === 'open') {
          setQr(await loadQr());
        }
      } catch (err) {
        if (isAttendanceDisabledError(err)) {
          setFeatureEnabled(false);
          return;
        }
        setError(toUserMessage(err, 'Could not load this session.'));
      } finally {
        setLoading(false);
      }
    })();
  }, [loadQr, loadRoster]);

  const isOpen = roster?.session.status === 'open';

  useEffect(() => {
    if (!isOpen) return;
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
    const matches = term
      ? roster.entries.filter((entry) => {
          const name = studentLabel(entry).toLowerCase();
          return name.includes(term) || entry.email.toLowerCase().includes(term);
        })
      : roster.entries;
    return sortRosterEntries(matches);
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
      setStatusFilter('all');
      setFlash('Attendance ended. Absent rows were recorded for students who did not check in.');
    } catch (err) {
      setFlash(toUserMessage(err, 'Could not end attendance.'));
    } finally {
      setBusy(false);
    }
  }

  async function saveCorrection(entry: AttendanceRosterEntry, status: AttendanceStatus, reason: string) {
    if (!entry.record_id) return;
    setBusy(true);
    setFlash(null);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      await apiFetch(`/admin/attendance/records/${entry.record_id}`, token, {
        method: 'PATCH',
        body: JSON.stringify({ status, reason }),
      });
      setEditing(null);
      setRoster(await loadRoster());
      setFlash('Attendance updated.');
    } catch (err) {
      setFlash(toUserMessage(err, 'Could not update attendance.'));
    } finally {
      setBusy(false);
    }
  }

  function toggleFilter(next: AttendanceStatusFilter) {
    setStatusFilter((current) => (current === next ? 'all' : next));
  }

  if (loading) return <OpsLoading label="Loading session…" />;

  if (featureEnabled === false) {
    return (
      <div>
        <div className="ops-top">
          <div>
            <Link href="/dashboard/attendance" style={{ fontSize: 13, color: 'var(--muted)' }}>
              ← Honors Attendance
            </Link>
            <h1 style={{ marginTop: 8 }}>Honors Attendance</h1>
          </div>
        </div>
        <AttendanceFeatureDisabled />
      </div>
    );
  }

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
              : `Session closed · ${formatAttendanceDateTime(roster.session.closed_at)}`}
          </p>
          {isOpen ? (
            <span className={`attendance-live-dot ${liveStale ? 'stale' : 'live'}`}>
              {liveStale ? 'Live updates paused — retrying…' : 'Live'}
            </span>
          ) : (
            <p className="attendance-review-note">
              Corrections need a reason and are audit-logged. Any honors admin can edit this session.
            </p>
          )}
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
            <button
              className={`attendance-stat ${statusFilter === 'present' ? 'is-active' : ''}`}
              type="button"
              aria-pressed={statusFilter === 'present'}
              onClick={() => toggleFilter('present')}
            >
              <strong>{roster.present_count}</strong>
              <span>Present</span>
            </button>
            <button
              className={`attendance-stat ${statusFilter === 'late' ? 'is-active' : ''}`}
              type="button"
              aria-pressed={statusFilter === 'late'}
              onClick={() => toggleFilter('late')}
            >
              <strong>{roster.late_count}</strong>
              <span>Late</span>
            </button>
            <button
              className={`attendance-stat ${statusFilter === 'absent' ? 'is-active' : ''}`}
              type="button"
              aria-pressed={statusFilter === 'absent'}
              onClick={() => toggleFilter('absent')}
            >
              <strong>{roster.absent_count}</strong>
              <span>Absent</span>
            </button>
            <button
              className={`attendance-stat ${statusFilter === 'excused' ? 'is-active' : ''}`}
              type="button"
              aria-pressed={statusFilter === 'excused'}
              onClick={() => toggleFilter('excused')}
            >
              <strong>{roster.excused_count}</strong>
              <span>Excused</span>
            </button>
          </>
        )}
      </div>

      {isOpen ? (
        <div className="attendance-progress" aria-hidden>
          <span style={{ width: `${progress}%` }} />
        </div>
      ) : null}

      {isOpen ? (
        <div className="attendance-live-grid">
          <section className="ops-table-wrap" style={{ padding: 18 }}>
            <strong>Live roster</strong>
            <RosterSearch value={search} onChange={setSearch} />
            <AttendanceRosterList entries={filteredEntries} mode="live" />
          </section>

          <section>
            {qr ? <AttendanceQrDisplay payload={qr as unknown as Record<string, string | number>} /> : null}
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
                      <span>{studentLabel(entry)}</span>
                      <span>{formatAttendanceTime(entry.checked_in_at)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </section>
        </div>
      ) : (
        <section className="ops-table-wrap attendance-review-panel">
          <strong>Session review</strong>
          <p className="ops-cell-sub" style={{ marginTop: 6 }}>
            Names are grouped A–Z. Click a count above to show only that group.
          </p>
          <RosterSearch value={search} onChange={setSearch} />
          <AttendanceRosterList
            entries={filteredEntries}
            mode="review"
            statusFilter={statusFilter}
            onEdit={setEditing}
          />
        </section>
      )}

      {editing ? (
        <AttendanceCorrectionDrawer
          entry={editing}
          busy={busy}
          onClose={() => setEditing(null)}
          onSave={(status, reason) => void saveCorrection(editing, status, reason)}
        />
      ) : null}
    </div>
  );
}

function RosterSearch({ value, onChange }: { value: string; onChange: (value: string) => void }) {
  return (
    <div className="ops-search" style={{ marginTop: 12, maxWidth: '100%' }}>
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder="Search by name or email…"
        aria-label="Search students"
      />
    </div>
  );
}
