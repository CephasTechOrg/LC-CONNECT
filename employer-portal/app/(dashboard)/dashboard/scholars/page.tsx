'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { apiFetch } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type ScholarView = {
  user_id: string;
  display_name: string | null;
  summary: string | null;
  skills: string[];
  career_interests: string[];
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
  const [status, setStatus] = useState('Loading…');
  const [error, setError] = useState(false);

  const load = useCallback(async () => {
    setError(false);
    setStatus('Loading…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<ScholarView[]>('/employers/scholars', token);
      setScholars(data);
      setStatus(data.length ? `${data.length} scholar(s) available.` : 'No scholars available yet.');
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Failed to load');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <>
      <div className="page-header">
        <h1>Scholar Directory</h1>
        <p>Presidential Scholars who have opted in to employer visibility</p>
      </div>

      <div className="actions" style={{ justifyContent: 'space-between', alignItems: 'center', marginTop: 0, marginBottom: 16 }}>
        <p className={`status${error ? ' error' : ''}`} style={{ margin: 0 }}>
          {status}
        </p>
        <button className="btn ghost" type="button" onClick={() => void load()} style={{ width: 'auto' }}>
          Refresh
        </button>
      </div>

      {scholars.length === 0 ? (
        <div className="panel">
          <div className="empty">No scholars are currently visible to employers.</div>
        </div>
      ) : (
        <div className="card-grid">
          {scholars.map((scholar) => {
            const tags = [...scholar.skills, ...scholar.career_interests].slice(0, 4);
            return (
              <div className="scholar-card" key={scholar.user_id}>
                <div className="scholar-avatar">{initials(scholar.display_name)}</div>
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
                  View Profile
                </Link>
              </div>
            );
          })}
        </div>
      )}
    </>
  );
}
