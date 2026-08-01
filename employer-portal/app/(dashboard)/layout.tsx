'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { ReactNode, useEffect, useState } from 'react';
import { myEmployer, type MyEmployer, toUserMessage } from '@/lib/api/client';
import { createClient } from '@/lib/supabase/client';
import { signOut } from '@/lib/auth/session';

const NAV = [
  { href: '/dashboard', label: 'Dashboard', icon: '▦' },
  { href: '/dashboard/scholars', label: 'Scholar Directory', icon: '◉' },
  { href: '/dashboard/opportunities', label: 'Opportunities', icon: '▤' },
  { href: '/dashboard/organization', label: 'Organization', icon: '⌘' },
];

function initials(name: string | null, fallback: string): string {
  const source = (name || fallback).trim();
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0][0].toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
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
      <aside className="sidebar">
        <div className="sidebar-brand">
          <strong>Livingstone College</strong>
          <span>Employer Partner Portal</span>
        </div>
        {NAV.map((item) => (
          <Link
            key={item.href}
            href={item.href}
            className={`nav-link${pathname === item.href ? ' active' : ''}`}
          >
            <span className="nav-icon">{item.icon}</span>
            {item.label}
          </Link>
        ))}
        <div className="sidebar-footer">
          <strong>Blueprint Bond</strong>
          <span>Presidential Scholars Program</span>
        </div>
      </aside>
      <div className="main">
        <header className="topbar">
          <div className="topbar-org">{employer.organization_name}</div>
          <div className="topbar-user">
            <div className="topbar-avatar">{initials(employer.display_name, employer.email)}</div>
            <div>
              <div className="topbar-user-name">{employer.display_name || employer.email}</div>
              <div className="topbar-user-role">Recruiter</div>
            </div>
            <button className="btn ghost" type="button" onClick={() => void onLogout()} style={{ width: 'auto' }}>
              Sign out
            </button>
          </div>
        </header>
        <div className="content">{children}</div>
      </div>
    </div>
  );
}
