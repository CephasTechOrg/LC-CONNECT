'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { ReactNode, useEffect, useState } from 'react';
import { apiFetch, bootstrapUser, type BootstrapUser, toUserMessage } from '@/lib/api/client';
import { createClient } from '@/lib/supabase/client';
import { signOut } from '@/lib/auth/session';

type NavItem = { href: string; label: string; icon: string };
type NavSection = { title?: string; honorsOnly?: boolean; items: NavItem[] };

const NAV_SECTIONS: NavSection[] = [
  {
    items: [
      { href: '/dashboard', label: 'Dashboard', icon: '▦' },
      { href: '/dashboard/content', label: 'Campus Hub', icon: '▥' },
      { href: '/dashboard/users', label: 'Users', icon: '◉' },
      { href: '/dashboard/positions', label: 'Campus Positions', icon: '▧' },
      { href: '/dashboard/moderation', label: 'Moderation', icon: '⚑' },
    ],
  },
  {
    title: 'Honors Program',
    honorsOnly: true,
    items: [
      { href: '/dashboard/scholars', label: 'Presidential Scholars', icon: '◈' },
      { href: '/dashboard/employers', label: 'Employer Partners', icon: '▣' },
    ],
  },
  {
    title: 'Administration',
    items: [
      { href: '/dashboard/admins', label: 'Admins & Roles', icon: '❖' },
      { href: '/dashboard/settings', label: 'Settings', icon: '⚙' },
      { href: '/dashboard/audit-logs', label: 'Audit Logs', icon: '▨' },
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

function roleLabel(scopes: string[]): string {
  if (scopes.includes('super_admin')) return 'Super Administrator';
  if (scopes.includes('school_admin')) return 'School Administrator';
  if (scopes.includes('honors_admin')) return 'Honors Administrator';
  if (scopes.includes('content_admin')) return 'Content Administrator';
  if (scopes.includes('auditor')) return 'Auditor';
  return 'Administrator';
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
        // Best-effort: an admin with no scope yet (e.g. legacy account) still sees the base nav.
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
      <aside className="sidebar">
        <div className="sidebar-brand">
          <div className="sidebar-brand-mark">LC</div>
          <div>
            <strong>LC Connect</strong>
            <span>Campus Admin</span>
          </div>
        </div>
        {sections.map((section) => (
          <div className="nav-section" key={section.title || 'base'}>
            {section.title ? <div className="nav-section-title">{section.title}</div> : null}
            {section.items.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className={`nav-link${pathname === item.href ? ' active' : ''}`}
              >
                <span className="nav-icon">{item.icon}</span>
                {item.label}
              </Link>
            ))}
          </div>
        ))}
      </aside>
      <div className="main">
        <header className="appbar">
          <div className="appbar-org">Livingstone College</div>
          <div className="appbar-user">
            <div className="appbar-avatar">{initials(user.email)}</div>
            <div>
              <div className="appbar-user-name">{user.email}</div>
              <div className="appbar-user-role">{roleLabel(scopes)}</div>
            </div>
            <button className="btn ghost" type="button" onClick={() => void onLogout()} style={{ width: 'auto' }}>
              Sign out
            </button>
          </div>
        </header>
        {children}
      </div>
    </div>
  );
}
