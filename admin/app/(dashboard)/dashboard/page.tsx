'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

export default function OverviewPage() {
  const [pendingCount, setPendingCount] = useState<number | null>(null);
  const [reportCount, setReportCount] = useState<number | null>(null);
  const [postCount, setPostCount] = useState<number | null>(null);
  const [resourceCount, setResourceCount] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void (async () => {
      try {
        const token = await getAccessToken();
        if (!token) return;
        const [positions, reports, posts, resources] = await Promise.all([
          apiFetch<unknown[]>('/admin/campus-positions/pending', token),
          apiFetch<unknown[]>('/admin/reports', token),
          apiFetch<unknown[]>('/admin/campus-posts', token),
          apiFetch<unknown[]>('/admin/campus-resources', token),
        ]);
        setPendingCount(positions.length);
        setReportCount(reports.length);
        setPostCount(posts.length);
        setResourceCount(resources.length);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load overview');
      }
    })();
  }, []);

  const needsAttention = (pendingCount ?? 0) + (reportCount ?? 0);

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
          <Link className={`stat${(pendingCount ?? 0) > 0 ? ' attention' : ''}`} href="/dashboard/positions">
            <strong>{pendingCount ?? '—'}</strong>
            <span>Pending positions</span>
          </Link>
          <Link className={`stat${(reportCount ?? 0) > 0 ? ' attention' : ''}`} href="/dashboard/moderation">
            <strong>{reportCount ?? '—'}</strong>
            <span>Open reports</span>
          </Link>
          <Link className="stat" href="/dashboard/content">
            <strong>{postCount ?? '—'}</strong>
            <span>Campus posts</span>
          </Link>
          <Link className="stat" href="/dashboard/content">
            <strong>{resourceCount ?? '—'}</strong>
            <span>Resources</span>
          </Link>
        </div>

        <div className="panel" style={{ marginTop: 16 }}>
          <h2>Needs attention</h2>
          {pendingCount === null ? (
            <p className="status">Loading…</p>
          ) : needsAttention === 0 ? (
            <p className="status">All clear — no positions or reports waiting.</p>
          ) : (
            <div className="card-list">
              {(pendingCount ?? 0) > 0 ? (
                <Link className="card" href="/dashboard/positions" style={{ display: 'block' }}>
                  <div className="card-head">
                    <div>
                      <h3>
                        {pendingCount} position{pendingCount === 1 ? '' : 's'} to review
                      </h3>
                      <p className="meta">Approve or reject verified campus roles →</p>
                    </div>
                    <span className="badge">Review</span>
                  </div>
                </Link>
              ) : null}
              {(reportCount ?? 0) > 0 ? (
                <Link className="card" href="/dashboard/moderation" style={{ display: 'block' }}>
                  <div className="card-head">
                    <div>
                      <h3>
                        {reportCount} report{reportCount === 1 ? '' : 's'} to review
                      </h3>
                      <p className="meta">Check reports and act on accounts →</p>
                    </div>
                    <span className="badge danger">Moderate</span>
                  </div>
                </Link>
              ) : null}
            </div>
          )}
        </div>
      </div>
    </>
  );
}
