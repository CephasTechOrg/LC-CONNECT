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

type KpiItem = {
  id: string;
  tone: string;
  title: string;
  sub: string;
  value: number | null | undefined;
  icon: 'users' | 'scholars' | 'employers' | 'opps' | 'positions';
  fill?: boolean;
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

  const pendingPositions = summary?.pending_positions ?? 0;
  const pendingEmployers = summary?.pending_employer_approvals ?? 0;
  const pendingOpps = summary?.pending_opportunity_reviews ?? 0;
  const openReports = summary?.open_reports ?? 0;

  const inventory = useMemo((): KpiItem[] => {
    const cards: KpiItem[] = [
      {
        id: 'users',
        tone: '',
        title: 'Total Users',
        sub: 'Registered on LC Connect',
        value: summary?.total_users,
        icon: 'users',
        fill: true,
      },
    ];
    if (isHonors) {
      cards.push(
        {
          id: 'scholars',
          tone: 'tone-green',
          title: 'Presidential Scholars',
          sub: 'Active memberships',
          value: summary?.active_scholars,
          icon: 'scholars',
        },
        {
          id: 'employers',
          tone: 'tone-cyan',
          title: 'Employer Partners',
          sub: 'Approved organizations',
          value: summary?.employer_partners,
          icon: 'employers',
        },
        {
          id: 'opps',
          tone: 'tone-orange',
          title: 'Active Opportunities',
          sub: 'Published on Campus Hub',
          value: summary?.active_opportunities,
          icon: 'opps',
        },
      );
    } else if (pendingPositions > 0) {
      cards.push({
        id: 'positions',
        tone: 'tone-purple-soft',
        title: 'Pending Positions',
        sub: 'Awaiting verification',
        value: pendingPositions,
        icon: 'positions',
      });
    }
    return cards.filter((card) => card.fill || (card.value != null && card.value > 0));
  }, [isHonors, pendingPositions, summary]);

  const openQueues = useMemo((): QueueItem[] => {
    const rows: QueueItem[] = [];
    if (pendingPositions > 0) {
      rows.push({
        href: '/dashboard/positions',
        title: 'Campus Positions',
        desc: 'Verification requests awaiting review',
        count: pendingPositions,
        tone: 'tone-purple-soft',
        stroke: '#6F42E8',
      });
    }
    if (isHonors && pendingEmployers > 0) {
      rows.push({
        href: '/dashboard/employers',
        title: 'Employer Approvals',
        desc: 'Organizations awaiting approval',
        count: pendingEmployers,
        tone: 'tone-yellow',
        stroke: '#D3A012',
      });
    }
    if (isHonors && pendingOpps > 0) {
      rows.push({
        href: '/dashboard/employers?tab=opportunities',
        title: 'Opportunity Reviews',
        desc: 'Submissions awaiting review',
        count: pendingOpps,
        tone: 'tone-orange',
        stroke: '#F08A5D',
      });
    }
    if (openReports > 0) {
      rows.push({
        href: '/dashboard/moderation',
        title: 'Moderation Reports',
        desc: 'Open safety reports awaiting review',
        count: openReports,
        tone: 'tone-red',
        stroke: '#D95763',
      });
    }
    return rows;
  }, [isHonors, openReports, pendingEmployers, pendingOpps, pendingPositions]);

  const attentionTotal = openQueues.reduce((sum, row) => sum + row.count, 0);
  const primaryQueueHref = openQueues[0]?.href ?? '/dashboard/positions';

  const allSystemsGo =
    status != null &&
    status.auth === 'operational' &&
    status.database === 'operational' &&
    status.storage === 'operational' &&
    status.api_gateway === 'operational';

  const downServices = status
    ? (
        [
          ['Authentication', status.auth],
          ['Database', status.database],
          ['Storage', status.storage],
          ['API Gateway', status.api_gateway],
        ] as const
      ).filter(([, value]) => value !== 'operational')
    : [];

  const welcomeSub = loading
    ? 'Loading today’s platform snapshot…'
    : attentionTotal > 0
      ? `${attentionTotal} item${attentionTotal === 1 ? '' : 's'} need a decision.`
      : allSystemsGo || !status
        ? 'Nothing waiting on you right now.'
        : 'A platform service needs attention.';

  const showHealth = Boolean(status && downServices.length > 0);
  const showTeam = !loading && admins.length > 0;
  const showSide = showHealth || showTeam;

  return (
    <div className="dash" aria-busy={loading}>
      {error ? <div className="error-banner">{error}</div> : null}

      <div className={`dash-layout${showSide ? '' : ' solo'}`}>
        <div className="dash-main">
          <section className="dash-welcome">
            <div className="dash-welcome-copy">
              <p className="dash-welcome-eyebrow">LC Connect operations</p>
              <h1>Welcome back, {firstNameFromEmail(user?.email)}.</h1>
              <p>{welcomeSub}</p>
            </div>
            <button
              className="dash-icon-btn dash-welcome-refresh"
              type="button"
              title="Refresh"
              aria-label="Refresh dashboard"
              onClick={() => void load()}
            >
              <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#8a7348" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                <path d="M20 11a8 8 0 1 0-.9 4.5" />
                <path d="M20 4.5V11h-6.2" />
              </svg>
            </button>
          </section>

          {inventory.length > 0 ? (
            <>
              <div className="dash-section-head">
                <div>
                  <h2>At a glance</h2>
                  <p>Live platform counts — empty metrics stay off this page.</p>
                </div>
              </div>
              <div className="dash-kpi-grid">
                {inventory.map((card) => (
                  <KpiCard key={card.id} {...card} />
                ))}
              </div>
            </>
          ) : null}

          {openQueues.length > 0 ? (
            <section className="dash-panel dash-queues">
              <div className="dash-panel-head">
                <div>
                  <div className="dash-panel-title">Needs attention</div>
                  <div className="dash-panel-sub">Only queues with work to do</div>
                </div>
                <span className="dash-priority-pill">{attentionTotal} open</span>
              </div>
              <div className="dash-queues-body">
                <div className="dash-approval-list">
                  {openQueues.map((row) => (
                    <QueueRow key={row.href} {...row} />
                  ))}
                  <Link className="dash-review-btn" href={primaryQueueHref}>
                    Start reviewing
                    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                      <path d="M5 12h14M13 6l6 6-6 6" />
                    </svg>
                  </Link>
                </div>
              </div>
            </section>
          ) : null}
        </div>

        {showSide ? (
          <aside className="dash-side">
            {showHealth && status ? (
              <section className="dash-panel">
                <div className="dash-panel-head" style={{ marginBottom: 16 }}>
                  <div className="dash-panel-title">System health</div>
                  <span className="dash-systems-pill warn">
                    <span className="status-dot down" />
                    Attention
                  </span>
                </div>
                <div className="dash-status-list">
                  {downServices.map(([name, value]) => (
                    <StatusRow key={name} name={name} value={value} />
                  ))}
                </div>
              </section>
            ) : null}

            {showTeam ? (
              <section className="dash-panel dash-team">
                <div className="dash-side-head" style={{ marginBottom: 18 }}>
                  <h3>Admin team</h3>
                  <Link href="/dashboard/admins" className="dash-side-link">
                    Manage <Chevron />
                  </Link>
                </div>
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
              </section>
            ) : null}
          </aside>
        ) : null}
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
  fill,
}: KpiItem) {
  return (
    <div className={`dash-kpi${fill ? ' dash-kpi-fill' : ''}`}>
      <div className={`dash-kpi-icon ${tone}`}>
        {icon === 'users' ? (
          <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <circle cx="9" cy="8" r="3.2" />
            <path d="M3.5 19.5c.6-3.2 2.9-5 5.5-5s4.9 1.8 5.5 5" />
          </svg>
        ) : null}
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
      </div>
      <div>
        <div className="dash-kpi-value">{formatCount(value)}</div>
        <div className="dash-kpi-title">{title}</div>
        <div className="dash-kpi-sub">{sub}</div>
      </div>
    </div>
  );
}

function QueueRow({ href, title, desc, count, tone, stroke }: QueueItem) {
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
