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
import { ChevronRight, PageHeader, RefreshIcon, SectionTitle, StatRow, type StatItem } from '@/components/admin-page';
import { greetingName, initialsFrom, ROLE_SHORT, type AdminMembership } from './dashboard-widgets';

type QueueItem = { href: string; title: string; desc: string; count: number };

const SERVICES = [
  ['auth', 'Sign-in'],
  ['database', 'Database'],
  ['storage', 'File storage'],
  ['api_gateway', 'API'],
] as const;

function timeOfDay(): string {
  const hour = new Date().getHours();
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

export default function OverviewPage() {
  const [summary, setSummary] = useState<AdminDashboardSummary | null>(null);
  const [status, setStatusData] = useState<SystemStatus | null>(null);
  const [scopes, setScopes] = useState<string[]>([]);
  const [admins, setAdmins] = useState<AdminMembership[]>([]);
  const [user, setUser] = useState<BootstrapUser | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
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

  // Headline numbers. Honors admins see the program's numbers; everyone else sees users and the
  // queue they can act on, so the row is never padded with counts that do not apply to them.
  const stats = useMemo((): StatItem[] => {
    const users: StatItem = {
      key: 'users',
      value: formatCount(summary?.total_users),
      label: 'Users',
      hint: 'Registered on LC Connect',
    };
    if (isHonors) {
      return [
        users,
        { key: 'scholars', value: formatCount(summary?.active_scholars), label: 'Presidential Scholars', hint: 'Active memberships' },
        { key: 'employers', value: formatCount(summary?.employer_partners), label: 'Employer partners', hint: 'Approved organizations' },
        { key: 'opps', value: formatCount(summary?.active_opportunities), label: 'Open opportunities', hint: 'Published on Campus Hub' },
      ];
    }
    return [
      users,
      { key: 'positions', value: formatCount(pendingPositions), label: 'Pending positions', hint: 'Awaiting verification' },
      { key: 'reports', value: formatCount(openReports), label: 'Open reports', hint: 'Awaiting review' },
    ];
  }, [isHonors, openReports, pendingPositions, summary]);

  const openQueues = useMemo((): QueueItem[] => {
    const rows: QueueItem[] = [];
    if (pendingPositions > 0) {
      rows.push({ href: '/dashboard/positions', title: 'Campus positions', desc: 'Staff waiting to be verified', count: pendingPositions });
    }
    if (isHonors && pendingEmployers > 0) {
      rows.push({ href: '/dashboard/employers', title: 'Employer approvals', desc: 'Organizations waiting for approval', count: pendingEmployers });
    }
    if (isHonors && pendingOpps > 0) {
      rows.push({ href: '/dashboard/employers?tab=opportunities', title: 'Opportunity reviews', desc: 'Submissions waiting for review', count: pendingOpps });
    }
    if (openReports > 0) {
      rows.push({ href: '/dashboard/moderation', title: 'Moderation reports', desc: 'Open safety reports', count: openReports });
    }
    return rows;
  }, [isHonors, openReports, pendingEmployers, pendingOpps, pendingPositions]);

  const attentionTotal = openQueues.reduce((sum, row) => sum + row.count, 0);
  const downServices = status ? SERVICES.filter(([key]) => status[key] !== 'operational') : [];

  const subtitle = loading
    ? 'Loading today’s snapshot…'
    : attentionTotal > 0
      ? `${attentionTotal} ${attentionTotal === 1 ? 'item needs' : 'items need'} a decision.`
      : downServices.length > 0
        ? 'Nothing is waiting on you, but a service needs attention.'
        : 'Nothing is waiting on you right now.';

  return (
    <div className="page" aria-busy={loading}>
      <PageHeader
        title={`${timeOfDay()}, ${greetingName(user)}`}
        subtitle={subtitle}
        action={
          <button className="btn-quiet" type="button" onClick={() => void load()} disabled={loading}>
            <RefreshIcon spinning={loading} />
            Refresh
          </button>
        }
      />

      {error ? <div className="error-banner">{error}</div> : null}

      <StatRow label="Headline numbers" items={stats} loading={loading && !summary} />

      <section className="card" aria-labelledby="attention-title">
        <SectionTitle
          id="attention-title"
          title="Needs attention"
          detail={openQueues.length > 0 ? 'Queues with work waiting, most urgent first.' : undefined}
          aside={
            openQueues.length > 0 ? (
              // The page's one primary action.
              <Link className="btn-primary" href={openQueues[0].href}>
                Start reviewing
              </Link>
            ) : undefined
          }
        />
        {loading && !summary ? (
          <ul className="ruled-list" aria-hidden>
            {[0, 1].map((i) => (
              <li className="ruled-row" key={i}>
                <div className="ruled-row-copy">
                  <div className="skeleton-line" style={{ width: '40%' }} />
                  <div className="skeleton-line" style={{ width: '60%', marginTop: 6 }} />
                </div>
              </li>
            ))}
          </ul>
        ) : openQueues.length > 0 ? (
          <ul className="ruled-list">
            {openQueues.map((row) => (
              <li key={row.href}>
                <Link className="ruled-row" href={row.href}>
                  <div className="ruled-row-copy">
                    <span className="ruled-row-title">{row.title}</span>
                    <span className="ruled-row-sub">{row.desc}</span>
                  </div>
                  <span className="ruled-row-value" aria-label={`${row.count} waiting`}>{row.count}</span>
                  <span className="ruled-row-chevron"><ChevronRight /></span>
                </Link>
              </li>
            ))}
          </ul>
        ) : (
          <p className="quiet-state">
            <span className="status-dot" aria-hidden />
            Every queue is clear.
          </p>
        )}
      </section>

      <div className="dash-pair">
        <section className="card" aria-labelledby="health-title">
          <SectionTitle
            id="health-title"
            title="System health"
            detail={
              status ? (
                <span className="status-line">
                  <span className={`status-dot${downServices.length ? ' down' : ''}`} aria-hidden />
                  {downServices.length
                    ? `${downServices.length} ${downServices.length === 1 ? 'service needs' : 'services need'} attention`
                    : 'All systems operational'}
                </span>
              ) : undefined
            }
          />
          <ul className="ruled-list">
            {SERVICES.map(([key, label]) => {
              const ok = status ? status[key] === 'operational' : true;
              return (
                <li className="ruled-row" key={key} style={{ minHeight: 52 }}>
                  <span className="ruled-row-copy ruled-row-title">{label}</span>
                  {status ? (
                    <span className={`status-text${ok ? '' : ' down'}`}>{ok ? 'Operational' : 'Down'}</span>
                  ) : (
                    <span className="skeleton-line" style={{ width: 80 }} />
                  )}
                </li>
              );
            })}
          </ul>
        </section>

        {admins.length > 0 ? (
          <section className="card" aria-labelledby="team-title">
            <SectionTitle
              id="team-title"
              title="Admin team"
              aside={<Link className="text-link" href="/dashboard/admins">Manage</Link>}
            />
            <ul className="ruled-list">
              {admins.map((admin) => (
                <li className="ruled-row" key={admin.id}>
                  <span className="mark" aria-hidden>{initialsFrom(admin.display_name || '', admin.user_email)}</span>
                  <div className="ruled-row-copy">
                    <span className="ruled-row-title">{admin.display_name || admin.user_email.split('@')[0]}</span>
                    <span className="ruled-row-sub">{ROLE_SHORT[admin.role] ?? 'Admin'}</span>
                  </div>
                </li>
              ))}
            </ul>
          </section>
        ) : null}
      </div>
    </div>
  );
}

function formatCount(n: number | null | undefined): string {
  if (n == null) return '–';
  return n.toLocaleString('en-US');
}
