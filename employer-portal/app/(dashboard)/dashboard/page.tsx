'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type Scholar = { user_id: string };

type Submission = {
  id: string;
  title: string;
  status: 'pending' | 'approved' | 'rejected';
  created_at: string;
};

function timeAgo(iso: string): string {
  const diffMs = Date.now() - new Date(iso).getTime();
  const minutes = Math.floor(diffMs / 60000);
  if (minutes < 60) return `${Math.max(minutes, 0)}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

export default function DashboardHomePage() {
  const [scholarCount, setScholarCount] = useState<number | null>(null);
  const [submissions, setSubmissions] = useState<Submission[]>([]);
  const [status, setStatus] = useState('Loading…');
  const [error, setError] = useState(false);

  const load = useCallback(async () => {
    setError(false);
    setStatus('Loading…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const [scholars, mySubmissions] = await Promise.all([
        apiFetch<Scholar[]>('/employers/scholars', token),
        apiFetch<Submission[]>('/employers/opportunities/me', token),
      ]);
      setScholarCount(scholars.length);
      setSubmissions(mySubmissions);
      setStatus('');
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load the dashboard. Please refresh and try again.'));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const pending = submissions.filter((s) => s.status === 'pending');
  const approved = submissions.filter((s) => s.status === 'approved');
  const rejected = submissions.filter((s) => s.status === 'rejected');
  const recent = [...submissions]
    .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
    .slice(0, 5);

  return (
    <>
      <div className="page-header">
        <h1>Employer Partner Portal</h1>
        <p>Blueprint Bond • Powered by LC Connect</p>
      </div>

      {error ? <div className="error-banner">{status}</div> : null}

      <div className="kpi-grid">
        <div className="kpi-card">
          <div className="kpi-icon">🎓</div>
          <div className="kpi-value">{scholarCount ?? '—'}</div>
          <div className="kpi-title">Total Scholars Available</div>
          <div className="kpi-subtitle">Consenting Presidential Scholars</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-icon">💼</div>
          <div className="kpi-value">{approved.length}</div>
          <div className="kpi-title">Active Opportunities</div>
          <div className="kpi-subtitle">Published to the Blueprint Bond feed</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-icon">🕐</div>
          <div className="kpi-value">{pending.length}</div>
          <div className="kpi-title">Pending Reviews</div>
          <div className="kpi-subtitle">Awaiting Honors Program approval</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-icon">📋</div>
          <div className="kpi-value">{submissions.length}</div>
          <div className="kpi-title">Total Submissions</div>
          <div className="kpi-subtitle">Across all statuses</div>
        </div>
      </div>

      <div className="dashboard-grid">
        <div className="panel">
          <div className="panel-head">
            <h2>Recent Submissions</h2>
            <Link href="/dashboard/opportunities">View all</Link>
          </div>
          {recent.length === 0 ? (
            <div className="empty">No opportunities submitted yet.</div>
          ) : (
            recent.map((s) => (
              <div className="activity-row" key={s.id}>
                <div className="activity-icon">
                  {s.status === 'approved' ? '✓' : s.status === 'rejected' ? '✕' : '⏳'}
                </div>
                <div>
                  <div className="activity-title">{s.title}</div>
                  <div className="activity-desc">
                    {s.status === 'approved'
                      ? 'Approved and live to scholars'
                      : s.status === 'rejected'
                        ? 'Not approved'
                        : 'Awaiting Honors Program review'}
                  </div>
                </div>
                <div className="activity-time">{timeAgo(s.created_at)}</div>
              </div>
            ))
          )}
        </div>

        <div className="panel">
          <div className="panel-head">
            <h2>Quick Actions</h2>
          </div>
          <Link className="quick-action" href="/dashboard/opportunities">
            <div className="quick-action-icon">+</div>
            <div>
              <div className="quick-action-title">Create Opportunity</div>
              <div className="quick-action-desc">Post a new role for scholars</div>
            </div>
            <div className="quick-action-arrow">›</div>
          </Link>
          <Link className="quick-action" href="/dashboard/scholars">
            <div className="quick-action-icon">◉</div>
            <div>
              <div className="quick-action-title">Browse Scholars</div>
              <div className="quick-action-desc">Find and connect with talent</div>
            </div>
            <div className="quick-action-arrow">›</div>
          </Link>
          <Link className="quick-action" href="/dashboard/organization">
            <div className="quick-action-icon">⌘</div>
            <div>
              <div className="quick-action-title">Organization Profile</div>
              <div className="quick-action-desc">View your organization details</div>
            </div>
            <div className="quick-action-arrow">›</div>
          </Link>
        </div>
      </div>

      <div className="panel">
        <div className="panel-head">
          <h2>Opportunity Status</h2>
          <Link href="/dashboard/opportunities">View all opportunities</Link>
        </div>
        <div className="table-scroll">
          <table className="rows">
            <thead>
              <tr>
                <th>Status</th>
                <th>Count</th>
                <th>Description</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td><span className="badge">Pending</span></td>
                <td>{pending.length}</td>
                <td>Awaiting Honors Program review</td>
              </tr>
              <tr>
                <td><span className="badge success">Approved</span></td>
                <td>{approved.length}</td>
                <td>Live to scholars in the Blueprint Bond feed</td>
              </tr>
              <tr>
                <td><span className="badge danger">Rejected</span></td>
                <td>{rejected.length}</td>
                <td>Not approved by the Honors Program</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
}
