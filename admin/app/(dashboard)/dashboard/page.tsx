'use client';

import Link from 'next/link';
import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  apiFetch,
  bootstrapUser,
  dashboardSummary,
  systemStatus,
  type AdminDashboardSummary,
  type BootstrapUser,
  type SystemStatus,
  toUserMessage,
} from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';
import {
  ApprovalDonut,
  AVATAR_TONES,
  Chevron,
  firstNameFromEmail,
  formatCount,
  initialsFrom,
  ROLE_SHORT,
  StatusRow,
  type AdminMembership,
} from './dashboard-widgets';

type QueueItem = {
  href: string;
  title: string;
  desc: string;
  count: number;
  tone: string;
  stroke: string;
};

export default function OverviewPage() {
  const [summary, setSummary] = useState<AdminDashboardSummary | null>(null);
  const [status, setStatusData] = useState<SystemStatus | null>(null);
  const [scopes, setScopes] = useState<string[]>([]);
  const [admins, setAdmins] = useState<AdminMembership[]>([]);
  const [user, setUser] = useState<BootstrapUser | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      setError(null);
      const token = await getAccessToken();
      if (!token) return;
      const [summaryRes, statusRes, scopesRes, boot, adminRes] = await Promise.all([
        dashboardSummary(token),
        systemStatus(token),
        apiFetch<{ scopes: string[] }>('/admin/admins/me/scopes', token),
        bootstrapUser(token),
        apiFetch<AdminMembership[]>('/admin/admins', token).catch(() => [] as AdminMembership[]),
      ]);
      setSummary(summaryRes);
      setStatusData(statusRes);
      setScopes(scopesRes.scopes);
      setUser(boot);
      setAdmins(adminRes.slice(0, 5));
    } catch (err) {
      setError(toUserMessage(err, 'Could not load the dashboard. Please refresh and try again.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const isHonors = scopes.includes('honors_admin') || scopes.includes('super_admin');
  const canInviteAdmins = scopes.includes('super_admin') || scopes.includes('school_admin');

  const pendingPositions = summary?.pending_positions ?? 0;
  const pendingEmployers = summary?.pending_employer_approvals ?? 0;
  const pendingOpps = summary?.pending_opportunity_reviews ?? 0;
  const openReports = summary?.open_reports ?? 0;

  const approvalQueues = useMemo((): QueueItem[] => {
    const rows: QueueItem[] = [
      {
        href: '/dashboard/positions',
        title: 'Campus Positions',
        desc: 'Verification requests awaiting review',
        count: pendingPositions,
        tone: 'tone-purple-soft',
        stroke: '#6F42E8',
      },
    ];
    if (isHonors) {
      rows.push(
        {
          href: '/dashboard/employers',
          title: 'Employer Approvals',
          desc: 'Organizations awaiting approval',
          count: pendingEmployers,
          tone: 'tone-yellow',
          stroke: '#D3A012',
        },
        {
          href: '/dashboard/employers?tab=opportunities',
          title: 'Opportunity Reviews',
          desc: 'Submissions awaiting review',
          count: pendingOpps,
          tone: 'tone-orange',
          stroke: '#F08A5D',
        },
      );
    }
    return rows;
  }, [isHonors, pendingEmployers, pendingOpps, pendingPositions]);

  const approvalTotal = useMemo(
    () => approvalQueues.reduce((sum, row) => sum + row.count, 0),
    [approvalQueues],
  );

  const attentionTotal = approvalTotal + openReports;

  const primaryQueueHref = useMemo(() => {
    const firstWithWork = approvalQueues.find((row) => row.count > 0);
    if (firstWithWork) return firstWithWork.href;
    if (openReports > 0) return '/dashboard/moderation';
    return '/dashboard/positions';
  }, [approvalQueues, openReports]);

  const allSystemsGo =
    status != null &&
    status.auth === 'operational' &&
    status.database === 'operational' &&
    status.storage === 'operational' &&
    status.api_gateway === 'operational';

  const welcomeSub = loading
    ? 'Loading today’s platform snapshot…'
    : attentionTotal > 0
      ? `${attentionTotal} item${attentionTotal === 1 ? '' : 's'} need your attention across approvals and moderation.`
      : allSystemsGo
        ? 'Queues are clear and platform services are running normally.'
        : 'Queues are clear, but one or more services need attention.';

  return (
    <div className="dash" aria-busy={loading}>
      {error ? <div className="error-banner">{error}</div> : null}

      <div className="dash-layout">
        <div className="dash-main">
          <section className="dash-welcome">
            <div className="dash-welcome-copy">
              <p className="dash-welcome-eyebrow">LC Connect operations</p>
              <h1>Welcome back, {firstNameFromEmail(user?.email)}.</h1>
              <p>{welcomeSub}</p>
              <div className="dash-welcome-chips">
                <Link
                  className={`dash-chip dash-chip-primary${attentionTotal === 0 ? ' quiet' : ''}`}
                  href={primaryQueueHref}
                >
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                    <path d="M20 6 9 17l-5-5" />
                  </svg>
                  {loading ? '…' : approvalTotal} approval{approvalTotal === 1 ? '' : 's'}
                </Link>
                <Link className="dash-chip dash-chip-warn" href="/dashboard/moderation">
                  <span className="dash-chip-dot" aria-hidden />
                  {loading ? '…' : openReports} open report{openReports === 1 ? '' : 's'}
                </Link>
                {status ? (
                  <span className={`dash-chip dash-chip-status${allSystemsGo ? '' : ' warn'}`}>
                    <span className={`status-dot${allSystemsGo ? '' : ' down'}`} />
                    {allSystemsGo ? 'Systems healthy' : 'Service issue'}
                  </span>
                ) : null}
              </div>
            </div>
            <div className="dash-welcome-aside" aria-hidden>
              <div className="dash-welcome-stat">
                <strong>{loading ? '—' : formatCount(summary?.total_users)}</strong>
                <span>Total users</span>
              </div>
              {isHonors ? (
                <div className="dash-welcome-stat">
                  <strong>{loading ? '—' : formatCount(summary?.active_scholars)}</strong>
                  <span>Active scholars</span>
                </div>
              ) : (
                <div className="dash-welcome-stat">
                  <strong>{loading ? '—' : formatCount(pendingPositions)}</strong>
                  <span>Pending positions</span>
                </div>
              )}
            </div>
          </section>

          <div className="dash-section-head">
            <div>
              <h2>At a glance</h2>
              <p>Platform inventory — not filtered by date.</p>
            </div>
            <div className="dash-overview-actions">
              <button
                className="dash-icon-btn"
                type="button"
                title="Refresh"
                aria-label="Refresh dashboard"
                onClick={() => void load()}
              >
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#5A5464" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                  <path d="M20 11a8 8 0 1 0-.9 4.5" />
                  <path d="M20 4.5V11h-6.2" />
                </svg>
              </button>
            </div>
          </div>

          <div className={`dash-kpi-grid${isHonors ? ' honors' : ''}`}>
            <div className="dash-kpi dash-kpi-fill">
              <div className="dash-kpi-icon">
                <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                  <circle cx="9" cy="8" r="3.2" />
                  <path d="M3.5 19.5c.6-3.2 2.9-5 5.5-5s4.9 1.8 5.5 5" />
                </svg>
              </div>
              <div>
                <div className="dash-kpi-value">{formatCount(summary?.total_users)}</div>
                <div className="dash-kpi-title">Total Users</div>
                <div className="dash-kpi-sub">Registered on LC Connect</div>
              </div>
            </div>

            {isHonors ? (
              <>
                <KpiCard tone="tone-green" title="Presidential Scholars" sub="Active memberships" value={summary?.active_scholars} icon="scholars" />
                <KpiCard tone="tone-cyan" title="Employer Partners" sub="Approved organizations" value={summary?.employer_partners} icon="employers" />
                <KpiCard tone="tone-orange" title="Active Opportunities" sub="Published on Campus Hub" value={summary?.active_opportunities} icon="opps" />
              </>
            ) : (
              <KpiCard tone="tone-purple-soft" title="Pending Positions" sub="Awaiting verification" value={summary?.pending_positions} icon="positions" />
            )}

            <KpiCard tone="tone-red" title="Open Reports" sub="Moderation queue" value={summary?.open_reports} icon="reports" />
          </div>

          <section className="dash-panel dash-queues">
            <div className="dash-panel-head">
              <div className="dash-panel-title-row">
                <div className="dash-panel-icon">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#6F42E8" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                    <path d="M9 11l2.5 2.5L16 8" />
                    <circle cx="12" cy="12" r="9" />
                  </svg>
                </div>
                <div>
                  <div className="dash-panel-title">Work queues</div>
                  <div className="dash-panel-sub">Approvals and moderation that need a decision</div>
                </div>
              </div>
              {attentionTotal > 0 ? (
                <span className="dash-priority-pill">{attentionTotal} open</span>
              ) : (
                <span className="dash-priority-pill calm">Clear</span>
              )}
            </div>

            <div className="dash-queues-body">
              <ApprovalDonut
                positions={pendingPositions}
                employers={isHonors ? pendingEmployers : 0}
                opportunities={isHonors ? pendingOpps : 0}
              />
              <div className="dash-approval-list">
                {approvalQueues.map((row) => (
                  <QueueRow key={row.href} {...row} />
                ))}
                <QueueRow
                  href="/dashboard/moderation"
                  title="Moderation Reports"
                  desc="Open safety reports awaiting review"
                  count={openReports}
                  tone="tone-red"
                  stroke="#D95763"
                />
                <Link className="dash-review-btn" href={primaryQueueHref}>
                  {attentionTotal > 0 ? 'Start reviewing' : 'Open positions'}
                  <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                    <path d="M5 12h14M13 6l6 6-6 6" />
                  </svg>
                </Link>
              </div>
            </div>
          </section>

          <section className="dash-panel">
            <div className="dash-panel-head" style={{ marginBottom: 12 }}>
              <div>
                <div className="dash-panel-title">Quick actions</div>
                <div className="dash-panel-sub">Common admin tasks — separate from review queues</div>
              </div>
            </div>
            <div className="dash-actions-grid">
              {isHonors ? (
                <>
                  <ActionCard href="/dashboard/scholars" title="Manage Scholars" desc="Memberships and verification" tone="tone-purple-soft" stroke="#6F42E8" />
                  <ActionCard href="/dashboard/attendance" title="Honors Attendance" desc="Start or review a session" tone="tone-green" stroke="#2DAA72" />
                  <ActionCard href="/dashboard/scholar-profiles" title="Scholar Profiles" desc="Headshot and résumé review" tone="tone-orange" stroke="#F08A5D" />
                </>
              ) : null}
              <ActionCard href="/dashboard/content" title="Campus Hub Posts" desc="Announcements and updates" tone="tone-cyan" stroke="#52BCD2" />
              <ActionCard href="/dashboard/content?tab=resources" title="Resources" desc="Upload campus resources" tone="tone-yellow" stroke="#D3A012" />
              <ActionCard href="/dashboard/users" title="Users" desc="Search and manage accounts" tone="tone-purple-soft" stroke="#6F42E8" />
              {canInviteAdmins ? (
                <ActionCard href="/dashboard/admins" title="Invite Admin" desc="Add access for operators" tone="tone-red" stroke="#D95763" />
              ) : null}
            </div>
          </section>
        </div>

        <aside className="dash-side">
          <section className="dash-panel">
            <div className="dash-panel-head" style={{ marginBottom: 16 }}>
              <div className="dash-panel-title">System health</div>
              {status ? (
                <span className={`dash-systems-pill${allSystemsGo ? '' : ' warn'}`}>
                  <span className={`status-dot${allSystemsGo ? '' : ' down'}`} />
                  {allSystemsGo ? 'All clear' : 'Attention'}
                </span>
              ) : null}
            </div>
            {status ? (
              <div className="dash-status-list">
                <StatusRow name="Authentication" value={status.auth} />
                <StatusRow name="Database" value={status.database} />
                <StatusRow name="Storage" value={status.storage} />
                <StatusRow name="API Gateway" value={status.api_gateway} />
              </div>
            ) : (
              <p className="status">Checking service health…</p>
            )}
          </section>

          <section className="dash-panel dash-team">
            <div className="dash-side-head" style={{ marginBottom: 18 }}>
              <h3>Admin team</h3>
              <Link href="/dashboard/admins" className="dash-side-link">
                Manage <Chevron />
              </Link>
            </div>
            {loading ? (
              <p className="status">Loading team…</p>
            ) : admins.length === 0 ? (
              <p className="status">No admins to show yet.</p>
            ) : (
              <div className="dash-team-list">
                {admins.map((admin, i) => {
                  const label = admin.display_name || admin.user_email.split('@')[0];
                  return (
                    <div className="dash-team-row-item" key={admin.id}>
                      <div className={`dash-team-avatar ${AVATAR_TONES[i % AVATAR_TONES.length]}`}>
                        {initialsFrom(admin.display_name || '', admin.user_email)}
                      </div>
                      <div className="dash-team-copy">
                        <div className="dash-team-name">{label}</div>
                        <div className="dash-team-role">{ROLE_SHORT[admin.role] ?? 'Admin'}</div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </section>
        </aside>
      </div>
    </div>
  );
}

function KpiCard({
  tone,
  title,
  sub,
  value,
  icon,
}: {
  tone: string;
  title: string;
  sub: string;
  value: number | null | undefined;
  icon: 'scholars' | 'employers' | 'opps' | 'positions' | 'reports';
}) {
  return (
    <div className="dash-kpi">
      <div className={`dash-kpi-icon ${tone}`}>
        {icon === 'scholars' ? (
          <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="#2DAA72" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <circle cx="12" cy="9" r="5" /><path d="M8.5 13.2 7 21l5-2.6L17 21l-1.5-7.8" />
          </svg>
        ) : null}
        {icon === 'employers' ? (
          <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="#52BCD2" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <rect x="4" y="8" width="16" height="12" rx="2" /><path d="M9 8V5.5a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 5.5V8" />
          </svg>
        ) : null}
        {icon === 'opps' || icon === 'positions' ? (
          <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke={icon === 'opps' ? '#F08A5D' : '#6F42E8'} strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <rect x="3" y="7.5" width="18" height="12.5" rx="2.5" /><path d="M8.5 7.5V6a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v1.5M3 12.5h18" />
          </svg>
        ) : null}
        {icon === 'reports' ? (
          <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="#D95763" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <path d="M5 21V4M5 4h11l-2 4 2 4H5" />
          </svg>
        ) : null}
      </div>
      <div>
        <div className="dash-kpi-value">{formatCount(value)}</div>
        <div className="dash-kpi-title">{title}</div>
        <div className="dash-kpi-sub">{sub}</div>
      </div>
    </div>
  );
}

function QueueRow({
  href,
  title,
  desc,
  count,
  tone,
  stroke,
}: QueueItem) {
  return (
    <Link className="dash-approval-row" href={href}>
      <div className={`dash-approval-icon ${tone}`}>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={stroke} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          <rect x="3" y="7.5" width="18" height="12.5" rx="2.5" />
          <path d="M8.5 7.5V6a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v1.5M3 12.5h18" />
        </svg>
      </div>
      <div className="dash-approval-copy">
        <div className="dash-approval-title">{title}</div>
        <div className="dash-approval-desc">{desc}</div>
      </div>
      <span className={`dash-approval-count ${tone}`}>{count}</span>
      <span className="dash-approval-chevron"><Chevron /></span>
    </Link>
  );
}

function ActionCard({
  href,
  title,
  desc,
  tone,
  stroke,
}: {
  href: string;
  title: string;
  desc: string;
  tone: string;
  stroke: string;
}) {
  return (
    <Link className="dash-action-card" href={href}>
      <div className={`dash-action-icon ${tone}`}>
        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={stroke} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          <path d="M5 12h14M13 6l6 6-6 6" />
        </svg>
      </div>
      <div>
        <div className="dash-action-title">{title}</div>
        <div className="dash-action-desc">{desc}</div>
      </div>
    </Link>
  );
}
