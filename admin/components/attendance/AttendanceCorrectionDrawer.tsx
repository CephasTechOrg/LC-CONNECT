'use client';

import { useEffect, useState } from 'react';
import type { AttendanceRosterEntry } from '@/lib/api/attendance';
import type { AttendanceStatus } from '@/components/attendance/attendance-ui';
import { studentLabel } from '@/components/attendance/attendance-ui';

type Props = {
  entry: AttendanceRosterEntry;
  busy: boolean;
  onClose: () => void;
  onSave: (status: AttendanceStatus, reason: string) => void;
};

export function AttendanceCorrectionDrawer({ entry, busy, onClose, onSave }: Props) {
  const [status, setStatus] = useState<AttendanceStatus>('present');
  const [reason, setReason] = useState('');

  useEffect(() => {
    setStatus(
      entry.status === 'late' || entry.status === 'absent' || entry.status === 'excused'
        ? entry.status
        : 'present',
    );
    setReason('');
  }, [entry]);

  const canSave = reason.trim().length >= 3 && !busy;

  return (
    <>
      <div className="ops-drawer-backdrop" onClick={onClose} aria-hidden />
      <aside className="ops-drawer" role="dialog" aria-label="Edit attendance">
        <div className="ops-drawer-head">
          <div>
            <h2>{studentLabel(entry)}</h2>
            <div className="ops-drawer-meta">Manual correction — a reason is required and audit-logged.</div>
          </div>
          <button className="ops-drawer-close" type="button" aria-label="Close" onClick={onClose}>
            ✕
          </button>
        </div>
        <div className="ops-drawer-grid">
          <div className="ops-drawer-field">
            <label htmlFor="attendance-status">Status</label>
            <select
              id="attendance-status"
              className="ops-select"
              value={status}
              onChange={(e) => setStatus(e.target.value as AttendanceStatus)}
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
          <button className="ops-btn" type="button" onClick={onClose} disabled={busy}>
            Cancel
          </button>
          <button
            className="ops-btn primary"
            type="button"
            onClick={() => onSave(status, reason.trim())}
            disabled={!canSave}
          >
            Save
          </button>
        </div>
      </aside>
    </>
  );
}
