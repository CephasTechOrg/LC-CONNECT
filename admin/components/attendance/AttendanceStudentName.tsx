import { attendanceInitials, studentLabel } from '@/components/attendance/attendance-ui';

type Props = {
  displayName: string | null;
  email: string;
};

export function AttendanceStudentName({ displayName, email }: Props) {
  const label = studentLabel({ display_name: displayName, email });
  const showEmail = Boolean(displayName?.trim());

  return (
    <div className="ops-user-cell attendance-student-name">
      <div className="ops-avatar" aria-hidden>
        {attendanceInitials(displayName, email)}
      </div>
      <div className="ops-user-cell-text">
        <div className="ops-cell-title" title={label}>
          {label}
        </div>
        {showEmail ? (
          <div className="ops-cell-sub" title={email}>
            {email}
          </div>
        ) : null}
      </div>
    </div>
  );
}
