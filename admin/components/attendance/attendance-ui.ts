import type { AttendanceRosterEntry } from '@/lib/api/attendance';

export type AttendanceStatus = 'present' | 'late' | 'absent' | 'excused';
export type AttendanceStatusFilter = 'all' | AttendanceStatus;

export const ATTENDANCE_STATUS_GROUPS: AttendanceStatus[] = [
  'present',
  'late',
  'absent',
  'excused',
];

export function attendanceInitials(name: string | null, email: string): string {
  const source = (name || email.split('@')[0]).replace(/[._-]+/g, ' ').trim();
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

export function studentLabel(entry: Pick<AttendanceRosterEntry, 'display_name' | 'email'>): string {
  return entry.display_name?.trim() || entry.email;
}

export function sortRosterEntries(entries: AttendanceRosterEntry[]): AttendanceRosterEntry[] {
  return [...entries].sort((a, b) =>
    studentLabel(a).localeCompare(studentLabel(b), undefined, { sensitivity: 'base' }),
  );
}

export function attendanceStatusChip(status: string | null): string {
  if (status === 'present') return 'ops-chip success';
  if (status === 'late') return 'ops-chip warn';
  if (status === 'absent') return 'ops-chip danger';
  if (status === 'excused') return 'ops-chip';
  return 'ops-chip muted';
}

export function formatAttendanceTime(iso: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

export function formatAttendanceDateTime(iso: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
}

export function reviewStatusOf(entry: AttendanceRosterEntry): AttendanceStatus {
  if (entry.status === 'present' || entry.status === 'late' || entry.status === 'excused') {
    return entry.status;
  }
  return 'absent';
}
