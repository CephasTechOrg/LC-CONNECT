'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type ScholarView = {
  user_id: string;
  display_name: string | null;
  summary: string | null;
  skills: string[];
  career_interests: string[];
  headshot_url: string | null;
};

function initials(name: string | null): string {
  const source = (name || 'Scholar').trim();
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0][0].toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

export default function ScholarDirectoryPage() {
  const [scholars, setScholars] = useState<ScholarView[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setError(null);
    setLoading(true);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<ScholarView[]>('/employers/scholars', token);
      setScholars(data);
    } catch (err) {
      setError(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
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
          <h1>Scholar Directory</h1>
          <p>Presidential Scholars who have opted in to employer visibility.</p>
        </div>
        <button className="ops-btn" type="button" disabled={loading} onClick={() => void load()}>
          Refresh
        </button>
      </header>

      <div style={{ paddingTop: 8 }}>
        {error ? <div className="error-banner">{error}</div> : null}

        <div className="ops-toolbar" style={{ marginTop: 0 }}>
          <span className="ops-count" style={{ marginLeft: 0 }}>
            {loading ? '…' : `${scholars.length} scholar${scholars.length === 1 ? '' : 's'}`}
          </span>
        </div>

        {loading ? (
          <div className="ops-table-wrap">
            <OpsLoading label="Loading scholars…" />
          </div>
        ) : scholars.length === 0 ? (
          <div className="ops-table-wrap">
            <OpsEmpty title="No scholars available">
              No Presidential Scholars are currently visible to employers.
            </OpsEmpty>
          </div>
        ) : (
          <div className="card-grid">
            {scholars.map((scholar) => {
              const tags = [...scholar.skills, ...scholar.career_interests].slice(0, 4);
              return (
                <div className="scholar-card" key={scholar.user_id}>
                  {scholar.headshot_url ? (
                    /* Short-lived signed URL — next/image needs remote-host config for expiring URLs. */
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={scholar.headshot_url}
                      alt={scholar.display_name || 'Scholar headshot'}
                      className="scholar-avatar"
                      style={{ objectFit: 'cover' }}
                    />
                  ) : (
                    <div className="scholar-avatar">{initials(scholar.display_name)}</div>
                  )}
                  <div className="scholar-name">{scholar.display_name || 'Presidential Scholar'}</div>
                  {scholar.summary ? <div className="scholar-meta">{scholar.summary}</div> : null}
                  {tags.length > 0 ? (
                    <div className="tag-row">
                      {tags.map((tag) => (
                        <span className="tag" key={tag}>
                          {tag}
                        </span>
                      ))}
                    </div>
                  ) : null}
                  <Link className="btn ghost" href={`/dashboard/scholars/${scholar.user_id}`}>
                    View profile
                  </Link>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </>
  );
}
