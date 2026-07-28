'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

export default function OverviewPage() {
  const [pendingCount, setPendingCount] = useState<number | null>(null);
  const [postCount, setPostCount] = useState<number | null>(null);
  const [resourceCount, setResourceCount] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void (async () => {
      try {
        const token = await getAccessToken();
        if (!token) return;
        const [positions, posts, resources] = await Promise.all([
          apiFetch<unknown[]>('/admin/campus-positions/pending', token),
          apiFetch<unknown[]>('/admin/campus-posts', token),
          apiFetch<unknown[]>('/admin/campus-resources', token),
        ]);
        setPendingCount(positions.length);
        setPostCount(posts.length);
        setResourceCount(resources.length);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load overview');
      }
    })();
  }, []);

  return (
    <>
      <header className="topbar">
        <div>
          <h1>Overview</h1>
          <p>Campus Hub operations at Livingstone College</p>
        </div>
      </header>
      <div className="content">
        {error ? <p className="status error">{error}</p> : null}
        <div className="stat-grid">
          <div className="stat">
            <strong>{pendingCount ?? '—'}</strong>
            <span>Pending positions</span>
          </div>
          <div className="stat">
            <strong>{postCount ?? '—'}</strong>
            <span>Campus posts</span>
          </div>
          <div className="stat">
            <strong>{resourceCount ?? '—'}</strong>
            <span>Resources</span>
          </div>
        </div>
        <div className="panel" style={{ marginTop: 16 }}>
          <h2>Quick links</h2>
          <div className="actions">
            <Link className="btn" href="/dashboard/positions">
              Review positions
            </Link>
            <Link className="btn secondary" href="/dashboard/posts">
              Manage posts
            </Link>
            <Link className="btn ghost" href="/dashboard/resources">
              Manage resources
            </Link>
          </div>
        </div>
      </div>
    </>
  );
}
