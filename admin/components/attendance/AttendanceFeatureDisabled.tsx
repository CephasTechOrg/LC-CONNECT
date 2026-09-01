import { OpsEmpty } from '@/components/ops-states';

export function AttendanceFeatureDisabled() {
  return (
    <OpsEmpty title="Honors attendance is not enabled in this environment">
      Classroom QR check-in is turned off on the API server. To enable it for a pilot, set{' '}
      <strong>HONORS_ATTENDANCE_ENABLED=true</strong> and <strong>ATTENDANCE_QR_SIGNING_SECRET</strong> on the
      backend, then redeploy. Once the service restarts, refresh this page to start a session.
    </OpsEmpty>
  );
}
