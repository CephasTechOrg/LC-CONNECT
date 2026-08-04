'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import { apiFetch, myEmployer, type MyEmployer, toUserMessage } from '@/lib/api/client';
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

function formatCount(n: number | null): string {
  if (n == null) return '—';
  return n.toLocaleString();
}

export default function DashboardHomePage() {
  const [employer, setEmployer] = useState<MyEmployer | null>(null);
  const [scholarCount, setScholarCount] = useState<number | null>(null);
  const [submissions, setSubmissions] = useState<Submission[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setError(null);
    setLoading(true);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const [me, scholars, mySubmissions] = await Promise.all([
        myEmployer(token),
        apiFetch<Scholar[]>('/employers/scholars', token),
        apiFetch<Submission[]>('/employers/opportunities/me', token),
      ]);
      setEmployer(me);
      setScholarCount(scholars.length);
      setSubmissions(mySubmissions);
    } catch (err) {
      setError(toUserMessage(err, 'Could not load the dashboard. Please refresh and try again.'));
    } finally {
      setLoading(false);
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

  const orgName = employer?.organization_name || 'Partner';

  return (
    <div className="dash" aria-busy={loading}>
      {error ? <div className="error-banner">{error}</div> : null}

      <section className="dash-welcome">
        <div className="dash-welcome-copy">
          <h1>Welcome back{employer?.display_name ? `, ${employer.display_name.split(' ')[0]}` : ''}.</h1>
          <p>
            Blueprint Bond partner portal for {orgName}. Browse consenting Presidential Scholars and
            submit opportunities for Honors Program review.
          </p>
          <div className="dash-welcome-chips">
            <div className="dash-chip dash-chip-primary">
              {loading ? '…' : pending.length} pending review{pending.length === 1 ? '' : 's'}
            </div>
            <div className="dash-chip dash-chip-warn">
              <span className="dash-chip-dot" aria-hidden />
              {loading ? '…' : formatCount(scholarCount)} scholar{scholarCount === 1 ? '' : 's'} available
            </div>
          </div>
        </div>
      </section>

      <div className="dash-kpi-grid">
        <div className="dash-kpi dash-kpi-fill">
          <div className="dash-kpi-icon">
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
              <circle cx="12" cy="9" r="5" />
              <path d="M8.5 13.2 7 21l5-2.6L17 21l-1.5-7.8" />
            </svg>
          </div>
          <div>
            <div className="dash-kpi-value">{formatCount(scholarCount)}</div>
            <div className="dash-kpi-title">Scholars available</div>
            <div className="dash-kpi-sub">Opted into employer visibility</div>
          </div>
        </div>
        <div className="dash-kpi">
          <div className="dash-kpi-icon tone-green">
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="#2DAA72" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
              <path d="M20 6 9 17l-5-5" />
            </svg>
          </div>
          <div>
            <div className="dash-kpi-value">{loading ? '—' : approved.length}</div>
            <div className="dash-kpi-title">Active opportunities</div>
            <div className="dash-kpi-sub">Published to scholars</div>
          </div>
        </div>
        <div className="dash-kpi">
          <div className="dash-kpi-icon tone-orange">
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="#D96B36" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
              <circle cx="12" cy="12" r="9" />
              <path d="M12 7v5l3 2" />
            </svg>
          </div>
          <div>
            <div className="dash-kpi-value">{loading ? '—' : pending.length}</div>
            <div className="dash-kpi-title">Pending reviews</div>
            <div className="dash-kpi-sub">Awaiting review</div>
          </div>
        </div>
        <div className="dash-kpi">
          <div className="dash-kpi-icon tone-cyan">
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="#2F8EA3" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
              <rect x="3" y="7.5" width="18" height="12.5" rx="2.5" />
              <path d="M8.5 7.5V6a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v1.5" />
            </svg>
          </div>
          <div>
            <div className="dash-kpi-value">{loading ? '—' : submissions.length}</div>
            <div className="dash-kpi-title">Total submissions</div>
            <div className="dash-kpi-sub">Across all statuses</div>
          </div>
        </div>
      </div>

      <div className="dash-split">
        <section className="dash-panel">
          <div className="dash-panel-head">
            <div className="dash-panel-title">Recent submissions</div>
            <Link className="dash-panel-link" href="/dashboard/opportunities">View all</Link>
          </div>
          {loading ? (
            <OpsLoading label="Loading submissions…" />
          ) : recent.length === 0 ? (
            <OpsEmpty title="No submissions yet">
              Create an opportunity to start the Honors Program review process.
            </OpsEmpty>
          ) : (
            recent.map((s) => (
              <div className="activity-row" key={s.id}>
                <div
                  className={`activity-icon${
                    s.status === 'approved' ? ' ok' : s.status === 'rejected' ? ' bad' : ' wait'
                  }`}
                  aria-hidden
                >
                  {s.status === 'approved' ? (
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M20 6 9 17l-5-5" />
                    </svg>
                  ) : s.status === 'rejected' ? (
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M18 6 6 18M6 6l12 12" />
                    </svg>
                  ) : (
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                      <circle cx="12" cy="12" r="9" />
                      <path d="M12 7v5l3 2" />
                    </svg>
                  )}
                </div>
                <div>
                  <div className="activity-title">{s.title}</div>
                  <div className="activity-desc">
                    {s.status === 'approved'
                      ? 'Approved and live to scholars'
                      : s.status === 'rejected'
                        ? 'Not approved'
                        : 'Awaiting review'}
                  </div>
                </div>
                <div className="activity-time">{timeAgo(s.created_at)}</div>
              </div>
            ))
          )}
        </section>

        <section className="dash-panel">
          <div className="dash-panel-head">
            <div className="dash-panel-title">Quick actions</div>
          </div>
          <div className="dash-actions">
            <Link className="dash-action" href="/dashboard/opportunities">
              <div className="dash-action-icon">
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#6F42E8" strokeWidth="2" strokeLinecap="round" aria-hidden>
                  <path d="M12 5v14M5 12h14" />
                </svg>
              </div>
              <div>
                <div className="dash-action-title">Create opportunity</div>
                <div className="dash-action-desc">Post a new role for scholars</div>
              </div>
              <div className="dash-action-arrow">›</div>
            </Link>
            <Link className="dash-action" href="/dashboard/scholars">
              <div className="dash-action-icon">
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#6F42E8" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                  <circle cx="12" cy="9" r="5" />
                  <path d="M8.5 13.2 7 21l5-2.6L17 21l-1.5-7.8" />
                </svg>
              </div>
              <div>
                <div className="dash-action-title">Browse scholars</div>
                <div className="dash-action-desc">Find and connect with talent</div>
              </div>
              <div className="dash-action-arrow">›</div>
            </Link>
            <Link className="dash-action" href="/dashboard/organization">
              <div className="dash-action-icon">
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#6F42E8" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                  <rect x="4" y="8" width="16" height="12" rx="2" />
                  <path d="M9 8V5.5a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 5.5V8" />
                </svg>
              </div>
              <div>
                <div className="dash-action-title">Organization profile</div>
                <div className="dash-action-desc">View your partner details</div>
              </div>
              <div className="dash-action-arrow">›</div>
            </Link>
          </div>
        </section>
      </div>

      <section className="dash-panel">
        <div className="dash-panel-head">
          <div className="dash-panel-title">Opportunity status</div>
          <Link className="dash-panel-link" href="/dashboard/opportunities">View all</Link>
        </div>
        <div className="ops-table-wrap table-scroll">
          {loading ? (
            <OpsLoading label="Loading status…" />
          ) : (
            <table className="ops-table">
              <thead>
                <tr>
                  <th>Status</th>
                  <th>Count</th>
                  <th>Description</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td><span className="ops-chip warn">Pending</span></td>
                  <td>{pending.length}</td>
                  <td>Awaiting review</td>
                </tr>
                <tr>
                  <td><span className="ops-chip success">Approved</span></td>
                  <td>{approved.length}</td>
                  <td>Live to scholars in the Blueprint Bond feed</td>
                </tr>
                <tr>
                  <td><span className="ops-chip danger">Rejected</span></td>
                  <td>{rejected.length}</td>
                  <td>Not approved by the Honors Program</td>
                </tr>
              </tbody>
            </table>
          )}
        </div>
      </section>
    </div>
  );
}
