'use client';

import { FormEvent, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

export default function AcceptInvitePage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [validSession, setValidSession] = useState(false);
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    void (async () => {
      const supabase = createClient();
      // The invite email's link establishes a session automatically on load (Supabase's client
      // detects the token in the URL) — this just waits for that and confirms it landed.
      const { data } = await supabase.auth.getSession();
      setValidSession(Boolean(data.session));
      setReady(true);
    })();
  }, []);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    if (password.length < 8) {
      setError('Password must be at least 8 characters.');
      return;
    }
    if (password !== confirmPassword) {
      setError('Passwords do not match.');
      return;
    }
    setLoading(true);
    try {
      const supabase = createClient();
      const { error: updateError } = await supabase.auth.updateUser({ password });
      if (updateError) throw updateError;
      router.replace('/mfa');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not set your password');
    } finally {
      setLoading(false);
    }
  }

  if (!ready) {
    return (
      <div className="auth-shell">
        <p className="status">Preparing your invite…</p>
      </div>
    );
  }

  if (!validSession) {
    return (
      <div className="auth-shell">
        <div className="auth-card">
          <p className="eyebrow">LC Connect</p>
          <h1>Invite link expired</h1>
          <p className="subtitle">
            This invite link is invalid or has expired. Ask whoever invited you to send a new one,
            or sign in below if you already set a password.
          </p>
          <a className="btn" href="/login">
            Go to sign in
          </a>
        </div>
      </div>
    );
  }

  return (
    <div className="auth-shell">
      <form className="auth-card" onSubmit={onSubmit}>
        <p className="eyebrow">LC Connect</p>
        <h1>Welcome — set your password</h1>
        <p className="subtitle">
          You&rsquo;ve been invited as an admin. Choose a password, then you&rsquo;ll set up your
          authenticator app (MFA is required for all admin accounts).
        </p>
        {error ? <div className="error-banner">{error}</div> : null}
        <div className="field">
          <label htmlFor="password">Password</label>
          <input
            id="password"
            type="password"
            autoComplete="new-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            minLength={8}
          />
        </div>
        <div className="field">
          <label htmlFor="confirm-password">Confirm password</label>
          <input
            id="confirm-password"
            type="password"
            autoComplete="new-password"
            value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)}
            required
            minLength={8}
          />
        </div>
        <button className="btn" type="submit" disabled={loading}>
          {loading ? 'Saving…' : 'Continue'}
        </button>
      </form>
    </div>
  );
}
