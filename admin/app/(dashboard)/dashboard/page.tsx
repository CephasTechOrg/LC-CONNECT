'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import {
  apiFetch,
  dashboardSummary,
  systemStatus,
  type AdminDashboardSummary,
  type ServiceStatus,
  type SystemStatus,
  toUserMessage, } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

function StatusChip({ icon, name, value }: { icon: string; name: string; value: ServiceStatus }) {
  return (
    <div className="status-chip">
      <span className="status-chip-icon">{icon}</span>
      <div>
        <div className="status-chip-name">{name}</div>
        <div className={`status-chip-value ${value}`}>
          <span className={`status-dot${value === 'down' ? ' down' : ''}`} />
          {value === 'operational' ? 'Operational' : 'Down'}
        </div>
      </div>
    </div>
  );
}

export default function OverviewPage() {
  const [summary, setSummary] = useState<AdminDashboardSummary | null>(null);
  const [status, setStatusData] = useState<SystemStatus | null>(null);
  const [scopes, setScopes] = useState<string[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void (async () => {
      try {
        const token = await getAccessToken();
        if (!token) return;
        const [summaryRes, statusRes, scopesRes] = await Promise.all([
          dashboardSummary(token),
          systemStatus(token),
          apiFetch<{ scopes: string[] }>('/admin/admins/me/scopes', token),
        ]);
        setSummary(summaryRes);
        setStatusData(statusRes);
        setScopes(scopesRes.scopes);
      } catch (err) {
        setError(toUserMessage(err, 'Could not load the dashboard. Please refresh and try again.'));
      }
    })();
  }, []);

  const isHonors = scopes.includes('honors_admin') || scopes.includes('super_admin');
  const canInviteAdmins = scopes.includes('super_admin') || scopes.includes('school_admin');

  return (
    <>
      <header className="topbar">
        <div>
          <h1>Dashboard</h1>
          <p>Here&rsquo;s an overview of today&rsquo;s platform activity.</p>
        </div>
      </header>
      <div className="content">
        {error ? <div className="error-banner">{error}</div> : null}

        <div className="kpi-grid">
          <div className="kpi-card">
            <div className="kpi-icon">◉</div>
            <div className="kpi-value">{summary?.total_users ?? '—'}</div>
            <div className="kpi-title">Total Users</div>
            <div className="kpi-subtitle">Registered on LC Connect</div>
          </div>

          {isHonors ? (
            <>
              <div className="kpi-card">
                <div className="kpi-icon">◈</div>
                <div className="kpi-value">{summary?.active_scholars ?? '—'}</div>
                <div className="kpi-title">Presidential Scholars</div>
                <div className="kpi-subtitle">Active memberships</div>
              </div>
              <div className="kpi-card">
                <div className="kpi-icon">▣</div>
                <div className="kpi-value">{summary?.employer_partners ?? '—'}</div>
                <div className="kpi-title">Employer Partners</div>
                <div className="kpi-subtitle">Approved organizations</div>
              </div>
              <div className="kpi-card">
                <div className="kpi-icon">▤</div>
                <div className="kpi-value">{summary?.active_opportunities ?? '—'}</div>
                <div className="kpi-title">Active Opportunities</div>
                <div className="kpi-subtitle">Published to the feed</div>
              </div>
            </>
          ) : (
            <div className="kpi-card">
              <div className="kpi-icon">▧</div>
              <div className="kpi-value">{summary?.pending_positions ?? '—'}</div>
              <div className="kpi-title">Pending Positions</div>
              <div className="kpi-subtitle">Awaiting verification</div>
            </div>
          )}

          <div className="kpi-card">
            <div className="kpi-icon">⚑</div>
            <div className="kpi-value">{summary?.open_reports ?? '—'}</div>
            <div className="kpi-title">Reported Items</div>
            <div className="kpi-subtitle">Open moderation reports</div>
          </div>
        </div>

        <div className="dashboard-grid">
          <div className="panel">
            <div className="panel-head">
              <h2>Pending Approvals</h2>
            </div>

            <Link className="approval-row is-link" href="/dashboard/positions">
              <span className="approval-icon">▧</span>
              <div>
                <div className="approval-title">Campus Positions</div>
                <div className="approval-desc">Verification requests awaiting review</div>
              </div>
              <span className="approval-count">{summary?.pending_positions ?? '—'}</span>
              <span className="approval-chevron">›</span>
            </Link>

            {isHonors ? (
              <>
                <Link className="approval-row is-link" href="/dashboard/employers">
                  <span className="approval-icon">▣</span>
                  <div>
                    <div className="approval-title">Employer Approvals</div>
                    <div className="approval-desc">Organizations awaiting approval</div>
                  </div>
                  <span className="approval-count">{summary?.pending_employer_approvals ?? '—'}</span>
                  <span className="approval-chevron">›</span>
                </Link>

                <Link className="approval-row is-link" href="/dashboard/employers?tab=opportunities">
                  <span className="approval-icon">▤</span>
                  <div>
                    <div className="approval-title">Opportunity Reviews</div>
                    <div className="approval-desc">Submissions awaiting review</div>
                  </div>
                  <span className="approval-count">{summary?.pending_opportunity_reviews ?? '—'}</span>
                  <span className="approval-chevron">›</span>
                </Link>
              </>
            ) : null}
          </div>

          <div className="panel">
            <div className="panel-head">
              <h2>Quick Actions</h2>
            </div>
            <div className="quick-action-grid">
              {isHonors ? (
                <>
                  <Link className="quick-action" href="/dashboard/scholars">
                    <span className="quick-action-icon">◈</span>
                    <div>
                      <div className="quick-action-title">Verify Scholars</div>
                      <div className="quick-action-desc">Review scholar applications</div>
                    </div>
                    <span className="quick-action-arrow">›</span>
                  </Link>
                  <Link className="quick-action" href="/dashboard/employers">
                    <span className="quick-action-icon">▣</span>
                    <div>
                      <div className="quick-action-title">Approve Employers</div>
                      <div className="quick-action-desc">Review employer partners</div>
                    </div>
                    <span className="quick-action-arrow">›</span>
                  </Link>
                  <Link className="quick-action" href="/dashboard/employers?tab=opportunities">
                    <span className="quick-action-icon">▤</span>
                    <div>
                      <div className="quick-action-title">Review Opportunities</div>
                      <div className="quick-action-desc">Evaluate and approve postings</div>
                    </div>
                    <span className="quick-action-arrow">›</span>
                  </Link>
                </>
              ) : null}
              <Link className="quick-action" href="/dashboard/content">
                <span className="quick-action-icon">▥</span>
                <div>
                  <div className="quick-action-title">Create Announcement</div>
                  <div className="quick-action-desc">Post updates to the Campus Hub</div>
                </div>
                <span className="quick-action-arrow">›</span>
              </Link>
              <Link className="quick-action" href="/dashboard/content?tab=resources">
                <span className="quick-action-icon">▥</span>
                <div>
                  <div className="quick-action-title">Manage Resources</div>
                  <div className="quick-action-desc">Upload and manage campus resources</div>
                </div>
                <span className="quick-action-arrow">›</span>
              </Link>
              {canInviteAdmins ? (
                <Link className="quick-action" href="/dashboard/admins">
                  <span className="quick-action-icon">❖</span>
                  <div>
                    <div className="quick-action-title">Invite Administrator</div>
                    <div className="quick-action-desc">Add admins and assign roles</div>
                  </div>
                  <span className="quick-action-arrow">›</span>
                </Link>
              ) : null}
            </div>
          </div>
        </div>

        <div className="panel">
          <div className="panel-head">
            <h2>System Status</h2>
          </div>
          {status ? (
            <div className="system-status-grid">
              <StatusChip icon="⛨" name="Authentication" value={status.auth} />
              <StatusChip icon="▤" name="Database" value={status.database} />
              <StatusChip icon="☁" name="Storage" value={status.storage} />
              <StatusChip icon="◇" name="API Gateway" value={status.api_gateway} />
            </div>
          ) : (
            <p className="status">Checking service health…</p>
          )}
        </div>
      </div>
    </>
  );
}
