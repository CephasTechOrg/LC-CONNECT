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

  const totalApprovals = useMemo(() => {
    let total = pendingPositions;
    if (isHonors) total += pendingEmployers + pendingOpps;
    return total;
  }, [isHonors, pendingPositions, pendingEmployers, pendingOpps]);

  const allSystemsGo =
    status != null &&
    status.auth === 'operational' &&
    status.database === 'operational' &&
    status.storage === 'operational' &&
    status.api_gateway === 'operational';

  return (
    <div className="dash" aria-busy={loading}>
      {error ? <div className="error-banner">{error}</div> : null}

      <div className="dash-layout">
        <div className="dash-main">
          <section className="dash-welcome">
            <div className="dash-welcome-copy">
              <h1>Welcome back, {firstNameFromEmail(user?.email)}.</h1>
              <p>
                Here&rsquo;s what is happening across LC Connect today. Livingstone College platform
                operations are running normally.
              </p>
              <div className="dash-welcome-chips">
                <div className="dash-chip dash-chip-primary">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                    <path d="M20 6 9 17l-5-5" />
                  </svg>
                  {loading ? '…' : totalApprovals} approval{totalApprovals === 1 ? '' : 's'} require review
                </div>
                <div className="dash-chip dash-chip-warn">
                  <span className="dash-chip-dot" aria-hidden />
                  {loading ? '…' : openReports} open moderation report{openReports === 1 ? '' : 's'}
                </div>
              </div>
            </div>
            <div className="dash-welcome-art" aria-hidden>
              <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="rgba(122,90,46,.5)" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
                <path d="M22 10 12 5 2 10l10 5z" />
                <path d="M6 12v5c3 2 9 2 12 0v-5" />
                <path d="M22 10v6" />
              </svg>
              <span>campus illustration</span>
            </div>
          </section>

          <div className="dash-overview-head">
            <h2>LC Connect Overview</h2>
            <div className="dash-overview-actions">
              {/* Label only — summary endpoint is not date-ranged. */}
              <div className="dash-range" title="Current totals (not a filtered date range)">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#6F42E8" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                  <rect x="3" y="4.5" width="18" height="16" rx="2.5" />
                  <path d="M3 9h18M8 2.5v4M16 2.5v4" />
                </svg>
                <span>Current totals</span>
              </div>
              <button className="dash-icon-btn" type="button" title="Refresh" aria-label="Refresh dashboard" onClick={() => void load()}>
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#5A5464" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                  <path d="M20 11a8 8 0 1 0-.9 4.5" />
                  <path d="M20 4.5V11h-6.2" />
                </svg>
              </button>
            </div>
          </div>

          <div className="dash-kpi-grid">
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
                <KpiCard tone="tone-orange" title="Active Opportunities" sub="Published opportunities" value={summary?.active_opportunities} icon="opps" />
              </>
            ) : (
              <KpiCard tone="tone-purple-soft" title="Pending Positions" sub="Awaiting verification" value={summary?.pending_positions} icon="positions" />
            )}

            <KpiCard tone="tone-red" title="Reported Items" sub="Open moderation reports" value={summary?.open_reports} icon="reports" />
          </div>

          <section className="dash-panel dash-approvals">
            <div className="dash-panel-head">
              <div className="dash-panel-title-row">
                <div className="dash-panel-icon">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#6F42E8" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                    <path d="M9 11l2.5 2.5L16 8" />
                    <circle cx="12" cy="12" r="9" />
                  </svg>
                </div>
                <div>
                  <div className="dash-panel-title">Pending Approvals</div>
                  <div className="dash-panel-sub">Across campus and Honors workflows</div>
                </div>
              </div>
              <span className="dash-priority-pill">Priority</span>
            </div>

            <div className="dash-approvals-body">
              <ApprovalDonut
                positions={pendingPositions}
                employers={isHonors ? pendingEmployers : 0}
                opportunities={isHonors ? pendingOpps : 0}
              />
              <div className="dash-approval-list">
                <ApprovalRow
                  href="/dashboard/positions"
                  title="Campus Positions"
                  desc="Verification requests awaiting review"
                  count={pendingPositions}
                  tone="tone-purple-soft"
                  stroke="#6F42E8"
                />
                {isHonors ? (
                  <>
                    <ApprovalRow
                      href="/dashboard/employers"
                      title="Employer Approvals"
                      desc="Organizations awaiting approval"
                      count={pendingEmployers}
                      tone="tone-yellow"
                      stroke="#D3A012"
                    />
                    <ApprovalRow
                      href="/dashboard/employers?tab=opportunities"
                      title="Opportunity Reviews"
                      desc="Submissions awaiting review"
                      count={pendingOpps}
                      tone="tone-orange"
                      stroke="#F08A5D"
                    />
                  </>
                ) : null}
                <Link className="dash-review-btn" href="/dashboard/positions">
                  Review approvals
                  <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                    <path d="M5 12h14M13 6l6 6-6 6" />
                  </svg>
                </Link>
              </div>
            </div>
          </section>

          <div className="dash-split">
            <section className="dash-panel">
              <div className="dash-panel-title" style={{ marginBottom: 16 }}>Quick Actions</div>
              <div className="dash-actions">
                {isHonors ? (
                  <>
                    <ActionRow href="/dashboard/scholars" title="Verify Scholars" desc="Review scholar applications" tone="tone-purple-soft" stroke="#6F42E8" />
                    <ActionRow href="/dashboard/employers" title="Approve Employers" desc="Review employer organizations" tone="tone-green" stroke="#2DAA72" />
                    <ActionRow href="/dashboard/employers?tab=opportunities" title="Review Opportunities" desc="Evaluate submitted opportunities" tone="tone-orange" stroke="#F08A5D" />
                  </>
                ) : null}
                <ActionRow href="/dashboard/content" title="Create Announcement" desc="Post an update to the Campus Hub" tone="tone-cyan" stroke="#52BCD2" />
                <ActionRow href="/dashboard/content?tab=resources" title="Manage Resources" desc="Upload and organize campus resources" tone="tone-yellow" stroke="#D3A012" />
                {canInviteAdmins ? (
                  <ActionRow href="/dashboard/admins" title="Invite Administrator" desc="Add an admin and assign access" tone="tone-red" stroke="#D95763" />
                ) : null}
              </div>
            </section>

            <section className="dash-panel">
              <div className="dash-panel-head" style={{ marginBottom: 16 }}>
                <div className="dash-panel-title">System Status</div>
                {status ? (
                  <span className={`dash-systems-pill${allSystemsGo ? '' : ' warn'}`}>
                    <span className={`status-dot${allSystemsGo ? '' : ' down'}`} />
                    {allSystemsGo ? 'All systems go' : 'Attention needed'}
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
          </div>
        </div>

        <aside className="dash-side">
          <section>
            <div className="dash-side-head">
              <h3>Attention Required</h3>
              <Link href="/dashboard/positions" className="dash-side-link">
                View all <Chevron />
              </Link>
            </div>
            <div className="dash-attention-grid">
              <AttentionCard href="/dashboard/positions" tone="fill-purple" value={pendingPositions} title="Campus Positions" sub={`${pendingPositions} pending review`} />
              {isHonors ? (
                <>
                  <AttentionCard href="/dashboard/employers" tone="fill-yellow" value={pendingEmployers} title="Employer Approvals" sub={`${pendingEmployers} pending approval`} />
                  <AttentionCard href="/dashboard/employers?tab=opportunities" tone="fill-orange" value={pendingOpps} title="Opportunity Reviews" sub={`${pendingOpps} pending review`} />
                </>
              ) : null}
              <AttentionCard href="/dashboard/moderation" tone="fill-cyan" value={openReports} title="Moderation Reports" sub={`${openReports} open reports`} />
            </div>
          </section>

          <section className="dash-panel dash-team">
            <div className="dash-side-head" style={{ marginBottom: 18 }}>
              <h3>Admin Team</h3>
              <Link href="/dashboard/admins" className="dash-icon-btn sm" aria-label="Manage admins">
                <Chevron />
              </Link>
            </div>
            {admins.length === 0 ? (
              <p className="status">No admins to show yet.</p>
            ) : (
              <div className="dash-team-row">
                {admins.map((admin, i) => {
                  const label = admin.display_name || admin.user_email.split('@')[0];
                  const shortName = label.split(/\s+/)[0];
                  return (
                    <div className="dash-team-person" key={admin.id}>
                      <div className={`dash-team-avatar ${AVATAR_TONES[i % AVATAR_TONES.length]}`}>
                        {initialsFrom(admin.display_name || '', admin.user_email)}
                      </div>
                      <div className="dash-team-name">{shortName}</div>
                      <div className="dash-team-role">{ROLE_SHORT[admin.role] ?? 'Admin'}</div>
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

function ApprovalRow({
  href,
  title,
  desc,
  count,
  tone,
  stroke,
}: {
  href: string;
  title: string;
  desc: string;
  count: number;
  tone: string;
  stroke: string;
}) {
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

function ActionRow({
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
    <Link className="dash-action" href={href}>
      <div className={`dash-action-icon ${tone}`}>
        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={stroke} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          <circle cx="12" cy="12" r="7" />
        </svg>
      </div>
      <div>
        <div className="dash-action-title">{title}</div>
        <div className="dash-action-desc">{desc}</div>
      </div>
      <span className="dash-action-chevron"><Chevron /></span>
    </Link>
  );
}

function AttentionCard({
  href,
  tone,
  value,
  title,
  sub,
}: {
  href: string;
  tone: string;
  value: number;
  title: string;
  sub: string;
}) {
  return (
    <Link className={`dash-attention ${tone}`} href={href}>
      <div className="dash-attention-top">
        <div className="dash-attention-icon">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <rect x="3" y="7.5" width="18" height="12.5" rx="2.5" />
            <path d="M8.5 7.5V6a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v1.5M3 12.5h18" />
          </svg>
        </div>
        <Chevron />
      </div>
      <div className="dash-attention-value">{value}</div>
      <div className="dash-attention-title">{title}</div>
      <div className="dash-attention-sub">{sub}</div>
    </Link>
  );
}
