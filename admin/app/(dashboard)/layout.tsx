'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { ReactNode, useEffect, useState } from 'react';
import { bootstrapUser, type BootstrapUser } from '@/lib/api/client';
import { createClient } from '@/lib/supabase/client';
import { signOut } from '@/lib/auth/session';

const NAV = [
  { href: '/dashboard', label: 'Overview' },
  { href: '/dashboard/positions', label: 'Positions' },
  { href: '/dashboard/content', label: 'Content' },
  { href: '/dashboard/moderation', label: 'Moderation' },
];

export default function DashboardLayout({ children }: { children: ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [user, setUser] = useState<BootstrapUser | null>(null);
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
        setReady(true);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Could not load admin session');
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
        <div className="brand">
          <strong>LC Connect</strong>
          <span>Campus Admin</span>
        </div>
        {NAV.map((item) => (
          <Link
            key={item.href}
            href={item.href}
            className={`nav-link${pathname === item.href ? ' active' : ''}`}
          >
            {item.label}
          </Link>
        ))}
        <div className="sidebar-footer">
          <p className="hint" style={{ marginTop: 0 }}>
            {user.email}
          </p>
          <button className="btn ghost" type="button" onClick={() => void onLogout()}>
            Sign out
          </button>
        </div>
      </aside>
      <div className="main">{children}</div>
    </div>
  );
}
