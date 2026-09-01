import { apiFetch } from '@/lib/api/client';

export type HonorsAttendanceFeatureStatus = {
  enabled: boolean;
};

export const ATTENDANCE_DISABLED_MESSAGE = 'Honors attendance is not enabled';

export function isAttendanceDisabledError(err: unknown): boolean {
  return err instanceof Error && err.message === ATTENDANCE_DISABLED_MESSAGE;
}

export async function fetchHonorsAttendanceStatus(): Promise<HonorsAttendanceFeatureStatus> {
  return apiFetch<HonorsAttendanceFeatureStatus>('/attendance/honors/status', null);
}

export type AttendanceSession = {
  id: string;
  program_id: string;
  title: string;
  started_by_id: string;
  opened_at: string;
  present_until: string;
  late_until: string | null;
  closed_at: string | null;
  status: string;
  created_at: string;
};

export type AttendanceDashboard = {
  honors_student_count: number;
  active_session: AttendanceSession | null;
  checked_in_count: number | null;
  remaining_count: number | null;
};

export type AttendanceHistoryItem = {
  session: AttendanceSession;
  honors_student_count: number;
  checked_in_count: number;
  present_count: number;
  late_count: number;
  absent_count: number;
  excused_count: number;
};

export type AttendanceQRPayload = {
  v: number;
  session_id: string;
  challenge_id: string;
  expires_at: string;
  token: string;
};

export type AttendanceRosterEntry = {
  record_id: string | null;
  student_id: string;
  display_name: string | null;
  email: string;
  status: string | null;
  checked_in_at: string | null;
};

export type AttendanceRoster = {
  session: AttendanceSession;
  session_id: string;
  checked_in_count: number;
  present_count: number;
  late_count: number;
  absent_count: number;
  excused_count: number;
  remaining_count: number;
  entries: AttendanceRosterEntry[];
};

export type StartAttendancePayload = {
  title: string;
  present_window_seconds?: number;
  late_window_seconds?: number;
};

export type ManualCorrectionPayload = {
  status: 'present' | 'late' | 'absent' | 'excused';
  reason: string;
};
