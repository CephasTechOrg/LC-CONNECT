import type { AttendanceRosterEntry } from '@/lib/api/attendance';
import {
  ATTENDANCE_STATUS_GROUPS,
  attendanceStatusChip,
  formatAttendanceTime,
  reviewStatusOf,
  type AttendanceStatus,
  type AttendanceStatusFilter,
} from '@/components/attendance/attendance-ui';
import { AttendanceStudentName } from '@/components/attendance/AttendanceStudentName';

type Props = {
  entries: AttendanceRosterEntry[];
  mode: 'live' | 'review';
  statusFilter?: AttendanceStatusFilter;
  onEdit?: (entry: AttendanceRosterEntry) => void;
};

const GROUP_LABELS: Record<AttendanceStatus, string> = {
  present: 'Present',
  late: 'Late',
  absent: 'Absent',
  excused: 'Excused',
};

export function AttendanceRosterList({ entries, mode, statusFilter = 'all', onEdit }: Props) {
  if (mode === 'live') {
    return <LiveRosterTable entries={entries} />;
  }
  return <ReviewRosterList entries={entries} statusFilter={statusFilter} onEdit={onEdit} />;
}

function LiveRosterTable({ entries }: { entries: AttendanceRosterEntry[] }) {
  if (entries.length === 0) {
    return <p className="ops-cell-sub" style={{ marginTop: 12 }}>No students match this search.</p>;
  }

  return (
    <table className="ops-table ops-cards-sm attendance-roster-table" style={{ marginTop: 12 }}>
      <thead>
        <tr>
          <th>Student</th>
          <th>Status</th>
          <th>Time</th>
        </tr>
      </thead>
      <tbody>
        {entries.map((entry) => (
          <tr key={entry.student_id}>
            <td>
              <AttendanceStudentName displayName={entry.display_name} email={entry.email} />
            </td>
            <td data-label="Status">
              <span className={attendanceStatusChip(entry.status)}>{entry.status || '—'}</span>
            </td>
            <td data-label="Checked in">{formatAttendanceTime(entry.checked_in_at)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function ReviewRosterList({
  entries,
  statusFilter,
  onEdit,
}: {
  entries: AttendanceRosterEntry[];
  statusFilter: AttendanceStatusFilter;
  onEdit?: (entry: AttendanceRosterEntry) => void;
}) {
  const groups = ATTENDANCE_STATUS_GROUPS.map((status) => ({
    status,
    items: entries.filter((entry) => reviewStatusOf(entry) === status),
  })).filter((group) => group.items.length > 0);
  const visible = statusFilter === 'all' ? groups : groups.filter((group) => group.status === statusFilter);

  if (visible.length === 0) {
    return <p className="ops-cell-sub" style={{ marginTop: 12 }}>No students match this search.</p>;
  }

  return (
    <div className="attendance-review-groups">
      {visible.map((group) => (
        <section key={group.status} className="attendance-roster-group">
          <header className="attendance-roster-group-head">
            <span>{GROUP_LABELS[group.status]}</span>
            <span>{group.items.length}</span>
          </header>
          {group.items.length > 0 ? (
            <ul className="attendance-name-list">
              {group.items.map((entry) => (
                <li key={entry.student_id}>
                  <AttendanceStudentName displayName={entry.display_name} email={entry.email} />
                  <div className="attendance-name-meta">
                    {entry.checked_in_at ? (
                      <span className="ops-cell-sub">{formatAttendanceTime(entry.checked_in_at)}</span>
                    ) : null}
                    {onEdit && entry.record_id ? (
                      <button className="ops-btn" type="button" onClick={() => onEdit(entry)}>
                        Edit
                      </button>
                    ) : null}
                  </div>
                </li>
              ))}
            </ul>
          ) : null}
        </section>
      ))}
    </div>
  );
}
