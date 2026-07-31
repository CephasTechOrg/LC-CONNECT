'use client';

import { useCallback, useEffect, useState } from 'react';
import { myEmployer, type MyEmployer } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

function statusBadgeClass(status: MyEmployer['organization_status']): string {
  if (status === 'approved') return 'badge success';
  if (status === 'rejected') return 'badge danger';
  return 'badge';
}

export default function OrganizationPage() {
  const [employer, setEmployer] = useState<MyEmployer | null>(null);
  const [status, setStatus] = useState('Loading…');
  const [error, setError] = useState(false);

  const load = useCallback(async () => {
    setError(false);
    setStatus('Loading…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const me = await myEmployer(token);
      setEmployer(me);
      setStatus('');
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Failed to load organization');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <>
      <div className="page-header">
        <h1>Organization</h1>
        <p>Your Blueprint Bond employer partner profile</p>
      </div>

      {error ? <div className="error-banner">{status}</div> : null}

      {!employer ? (
        <p className="status">{status}</p>
      ) : (
        <div className="panel">
          <div className="panel-head">
            <h2>{employer.organization_name}</h2>
            <span className={statusBadgeClass(employer.organization_status)}>
              {employer.organization_status}
            </span>
          </div>

          <div className="field">
            <label>Contact email</label>
            <p style={{ margin: 0, fontSize: 14 }}>{employer.email}</p>
          </div>

          {employer.display_name ? (
            <div className="field">
              <label>Contact name</label>
              <p style={{ margin: 0, fontSize: 14 }}>{employer.display_name}</p>
            </div>
          ) : null}

          {employer.organization_status === 'pending' ? (
            <p className="hint">
              Your application is awaiting Honors Program review. You&rsquo;ll receive an email once a
              decision is made.
            </p>
          ) : null}
          {employer.organization_status === 'rejected' ? (
            <p className="hint">
              This organization&rsquo;s application was not approved. Contact the Honors Program office
              with questions.
            </p>
          ) : null}
        </div>
      )}
    </>
  );
}
