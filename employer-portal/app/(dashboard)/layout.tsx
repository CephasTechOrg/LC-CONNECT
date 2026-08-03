'use client';

import Image from 'next/image';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { ComponentType, ReactNode, useEffect, useState } from 'react';
import { myEmployer, type MyEmployer, toUserMessage } from '@/lib/api/client';
import { createClient } from '@/lib/supabase/client';
import { signOut } from '@/lib/auth/session';
import {
  IconDashboard,
  IconOpportunities,
  IconOrganization,
  IconScholars,
  IconSearch,
  IconSignOut,
} from '@/components/nav-icons';

type NavIcon = ComponentType<{ stroke?: string; size?: number }>;
type NavItem = { href: string; label: string; Icon: NavIcon };

const NAV: NavItem[] = [
  { href: '/dashboard', label: 'Dashboard', Icon: IconDashboard },
  { href: '/dashboard/scholars', label: 'Scholar Directory', Icon: IconScholars },
  { href: '/dashboard/opportunities', label: 'Opportunities', Icon: IconOpportunities },
  { href: '/dashboard/organization', label: 'Organization', Icon: IconOrganization },
];

function initials(name: string | null, fallback: string): string {
  const source = (name || fallback).replace(/[._-]+/g, ' ').trim();
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function isActive(href: string, pathname: string): boolean {
  if (href === '/dashboard') return pathname === '/dashboard';
  return pathname === href || pathname.startsWith(`${href}/`);
}

export default function DashboardLayout({ children }: { children: ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [employer, setEmployer] = useState<MyEmployer | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    void (async () => {
      try {
        const supabase = createClient();
        const { data: sessionData } = await supabase.auth.getSession();
        const session = sessionData.session;
        if (!session) {
          router.replace('/login');
          return;
        }

        const me = await myEmployer(session.access_token);
        setEmployer(me);
        setReady(true);
      } catch (err) {
        setError(toUserMessage(err, 'Could not load your session'));
        setReady(true);
      }
    })();
  }, [router]);

  async function onLogout() {
    await signOut();
    router.replace('/login');
  }

  if (!ready) {
    return (
      <div className="auth-shell">
        <p className="status">Checking your session…</p>
      </div>
    );
  }

  if (error || !employer) {
    return (
      <div className="auth-shell">
        <div className="auth-card">
          <p className="eyebrow">Blueprint Bond</p>
          <h1>Access unavailable</h1>
          <p className="subtitle">{error || 'Not authorized'}</p>
          <button className="btn" type="button" onClick={() => void onLogout()}>
            Sign out
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="app-shell">
      <aside className="sidebar" aria-label="Employer navigation">
        <div className="sidebar-brand">
          <div className="sidebar-brand-mark">
            <Image src="/lclogo.png" alt="Livingstone College" width={44} height={44} priority />
          </div>
          <div className="sidebar-brand-code">LC</div>
        </div>

        <nav className="sidebar-nav">
          <div className="nav-section">
            {NAV.map((item) => {
              const active = isActive(item.href, pathname);
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  title={item.label}
                  aria-label={item.label}
                  aria-current={active ? 'page' : undefined}
                  className={`nav-link${active ? ' active' : ''}`}
                >
                  <item.Icon stroke={active ? '#6F42E8' : 'rgba(255,255,255,0.9)'} />
                </Link>
              );
            })}
          </div>
        </nav>

        <button
          className="nav-link nav-signout"
          type="button"
          title="Sign Out"
          aria-label="Sign out"
          onClick={() => void onLogout()}
        >
          <IconSignOut stroke="rgba(255,255,255,0.9)" />
        </button>
      </aside>

      <div className="main">
        <header className="appbar">
          <div className="appbar-search">
            <span className="appbar-search-icon" aria-hidden>
              <IconSearch stroke="#9B95A8" />
            </span>
            {/* Visual chrome only — no global search API yet. */}
            <input
              type="search"
              placeholder="Search scholars or opportunities"
              aria-label="Search scholars or opportunities"
              disabled
            />
          </div>

          <div className="appbar-actions">
            <div className="org-chip">
              <span className="org-chip-dot" aria-hidden />
              <span>{employer.organization_name}</span>
            </div>

            <div className="appbar-user">
              <div className="appbar-avatar">{initials(employer.display_name, employer.email)}</div>
              <div className="appbar-user-meta">
                <div className="appbar-user-name">{employer.display_name || employer.email}</div>
                <div className="appbar-user-role">Employer Partner</div>
              </div>
            </div>
          </div>
        </header>

        <div className="main-body">{children}</div>
      </div>
    </div>
  );
}
