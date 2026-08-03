'use client';

import Image from 'next/image';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { ComponentType, ReactNode, useEffect, useState } from 'react';
import { apiFetch, bootstrapUser, type BootstrapUser, toUserMessage } from '@/lib/api/client';
import { createClient } from '@/lib/supabase/client';
import { signOut } from '@/lib/auth/session';
import {
  IconAdmins,
  IconAudit,
  IconBell,
  IconCampusHub,
  IconChevronDown,
  IconDashboard,
  IconEmployers,
  IconModeration,
  IconPositions,
  IconScholars,
  IconSearch,
  IconSettings,
  IconSignOut,
  IconUsers,
} from '@/components/nav-icons';
import './dashboard/ops.css';
import './dashboard/dashboard.css';

type NavIcon = ComponentType<{ stroke?: string; size?: number }>;
type NavItem = { href: string; label: string; Icon: NavIcon };
type NavSection = { honorsOnly?: boolean; dividerBefore?: boolean; items: NavItem[] };

const NAV_SECTIONS: NavSection[] = [
  {
    items: [
      { href: '/dashboard', label: 'Dashboard', Icon: IconDashboard },
      { href: '/dashboard/content', label: 'Campus Hub', Icon: IconCampusHub },
      { href: '/dashboard/users', label: 'Users', Icon: IconUsers },
      { href: '/dashboard/positions', label: 'Campus Positions', Icon: IconPositions },
      { href: '/dashboard/moderation', label: 'Moderation', Icon: IconModeration },
    ],
  },
  {
    honorsOnly: true,
    dividerBefore: true,
    items: [
      { href: '/dashboard/scholars', label: 'Presidential Scholars', Icon: IconScholars },
      { href: '/dashboard/employers', label: 'Employer Partners', Icon: IconEmployers },
    ],
  },
  {
    dividerBefore: true,
    items: [
      { href: '/dashboard/admins', label: 'Admins & Roles', Icon: IconAdmins },
      { href: '/dashboard/settings', label: 'Settings', Icon: IconSettings },
      { href: '/dashboard/audit-logs', label: 'Audit Logs', Icon: IconAudit },
    ],
  },
];

function initials(email: string): string {
  const name = email.split('@')[0].replace(/[._-]+/g, ' ').trim();
  const parts = name.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

function displayName(email: string): string {
  const raw = email.split('@')[0].replace(/[._-]+/g, ' ').trim();
  if (!raw) return 'Admin';
  return raw
    .split(/\s+/)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

function roleLabel(scopes: string[]): string {
  if (scopes.includes('super_admin')) return 'Super Administrator';
  if (scopes.includes('school_admin')) return 'School Administrator';
  if (scopes.includes('honors_admin')) return 'Honors Administrator';
  if (scopes.includes('content_admin')) return 'Content Administrator';
  if (scopes.includes('auditor')) return 'Auditor';
  return 'Administrator';
}

function isActive(href: string, pathname: string): boolean {
  if (href === '/dashboard') return pathname === '/dashboard';
  return pathname === href || pathname.startsWith(`${href}/`);
}

export default function DashboardLayout({ children }: { children: ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [user, setUser] = useState<BootstrapUser | null>(null);
  const [scopes, setScopes] = useState<string[]>([]);
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

        const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
        if (aal?.currentLevel !== 'aal2') {
          router.replace('/mfa');
          return;
        }

        const bootstrapped = await bootstrapUser(session.access_token);
        if (bootstrapped.role !== 'admin') {
          setError('This account is not an admin. Ask an existing admin to promote you.');
          setReady(true);
          return;
        }
        setUser(bootstrapped);
        try {
          const scopesRes = await apiFetch<{ scopes: string[] }>(
            '/admin/admins/me/scopes',
            session.access_token,
          );
          setScopes(scopesRes.scopes);
        } catch {
          setScopes([]);
        }
        setReady(true);
      } catch (err) {
        setError(toUserMessage(err, 'Could not load admin session'));
        setReady(true);
      }
    })();
  }, [router]);

  const isHonors = scopes.includes('honors_admin') || scopes.includes('super_admin');
  const sections = NAV_SECTIONS.filter((section) => !section.honorsOnly || isHonors);

  async function onLogout() {
    await signOut();
    router.replace('/login');
  }

  if (!ready) {
    return (
      <div className="auth-shell">
        <p className="status">Checking admin session…</p>
      </div>
    );
  }

  if (error || !user) {
    return (
      <div className="auth-shell">
        <div className="auth-card">
          <h1>Access denied</h1>
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
      <aside className="sidebar" aria-label="Admin navigation">
        <div className="sidebar-brand">
          <div className="sidebar-brand-mark">
            <Image src="/lclogo.png" alt="Livingstone College" width={44} height={44} priority />
          </div>
          <div className="sidebar-brand-code">LC</div>
        </div>

        <nav className="sidebar-nav">
          {sections.map((section, sectionIndex) => (
            <div className="nav-section" key={sectionIndex}>
              {section.dividerBefore ? <div className="nav-divider" aria-hidden /> : null}
              {section.items.map((item) => {
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
          ))}
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
            <input type="search" placeholder="Search across LC Connect" aria-label="Search across LC Connect" disabled />
          </div>

          <div className="appbar-actions">
            <div className="org-chip">
              <span className="org-chip-dot" aria-hidden />
              <span>Livingstone College</span>
            </div>

            <Link
              href="/dashboard/settings"
              className="icon-btn"
              title="Settings"
              aria-label="Settings"
            >
              <IconSettings stroke="#5A5464" size={19} />
            </Link>

            {/* Bell is chrome only — no admin notification feed yet. */}
            <button className="icon-btn" type="button" title="Notifications" aria-label="Notifications" disabled>
              <IconBell stroke="#5A5464" />
            </button>

            <div className="appbar-user">
              <div className="appbar-avatar">{initials(user.email)}</div>
              <div className="appbar-user-meta">
                <div className="appbar-user-name">{displayName(user.email)}</div>
                <div className="appbar-user-role">{roleLabel(scopes)}</div>
              </div>
              <IconChevronDown stroke="#8E8899" />
            </div>
          </div>
        </header>

        <div className="main-body">{children}</div>
      </div>
    </div>
  );
}
