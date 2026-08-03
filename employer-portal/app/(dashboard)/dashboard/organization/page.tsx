'use client';

import { useCallback, useEffect, useState } from 'react';
import { OpsLoading } from '@/components/ops-states';
import { myEmployer, type MyEmployer, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

function statusChip(status: MyEmployer['organization_status']): string {
  if (status === 'approved') return 'ops-chip success';
  if (status === 'rejected') return 'ops-chip danger';
  return 'ops-chip warn';
}

export default function OrganizationPage() {
  const [employer, setEmployer] = useState<MyEmployer | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setError(null);
    setLoading(true);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const me = await myEmployer(token);
      setEmployer(me);
    } catch (err) {
      setError(toUserMessage(err, 'Failed to load organization'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <>
      <header className="ops-top">
        <div>
          <h1>Organization</h1>
          <p>Your Blueprint Bond employer partner profile.</p>
        </div>
        <button className="ops-btn" type="button" disabled={loading} onClick={() => void load()}>
          Refresh
        </button>
      </header>

      <div style={{ paddingTop: 8 }}>
        {error ? <div className="error-banner">{error}</div> : null}

        {loading ? (
          <div className="ops-table-wrap">
            <OpsLoading label="Loading organization…" />
          </div>
        ) : employer ? (
          <section className="ops-form">
            <div className="panel-head" style={{ marginBottom: 18 }}>
              <h2 style={{ margin: 0 }}>{employer.organization_name}</h2>
              <span className={statusChip(employer.organization_status)}>
                {employer.organization_status}
              </span>
            </div>

            <div className="field">
              <label>Contact email</label>
              <div className="ops-cell-title" style={{ fontWeight: 600 }}>{employer.email}</div>
            </div>

            {employer.display_name ? (
              <div className="field">
                <label>Contact name</label>
                <div className="ops-cell-title" style={{ fontWeight: 600 }}>{employer.display_name}</div>
              </div>
            ) : null}

            {employer.organization_status === 'pending' ? (
              <p className="hint" style={{ marginTop: 0 }}>
                Your application is awaiting Honors Program review. You&rsquo;ll receive an email once a
                decision is made.
              </p>
            ) : null}
            {employer.organization_status === 'rejected' ? (
              <p className="hint" style={{ marginTop: 0 }}>
                This organization&rsquo;s application was not approved. Contact the Honors Program office
                with questions.
              </p>
            ) : null}
          </section>
        ) : null}
      </div>
    </>
  );
}
