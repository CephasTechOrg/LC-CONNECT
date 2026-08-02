'use client';

import { FormEvent, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { toUserMessage } from '@/lib/api/client';

type Mode = 'checking' | 'code' | 'password';

export default function AcceptInvitePage() {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>('checking');

  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [verifying, setVerifying] = useState(false);

  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [saving, setSaving] = useState(false);

  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void (async () => {
      const supabase = createClient();
      // Clicking the invite link auto-establishes a session (Supabase's client detects the
      // token in the URL). If that already happened, skip straight to setting a password —
      // otherwise fall back to the "enter the code from your email" step, since some mail
      // clients strip/mangle the link and Supabase's invite email includes a one-time code too.
      const { data } = await supabase.auth.getSession();
      setMode(data.session ? 'password' : 'code');
    })();
  }, []);

  async function onVerifyCode(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setVerifying(true);
    try {
      const supabase = createClient();
      const { error: verifyError } = await supabase.auth.verifyOtp({
        email: email.trim(),
        token: code.trim(),
        type: 'invite',
      });
      if (verifyError) throw verifyError;
      setMode('password');
    } catch (err) {
      setError(toUserMessage(err, 'That code is invalid or has expired.'));
    } finally {
      setVerifying(false);
    }
  }

  async function onSetPassword(event: FormEvent) {
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
    setSaving(true);
    try {
      const supabase = createClient();
      const { error: updateError } = await supabase.auth.updateUser({ password });
      if (updateError) throw updateError;
      router.replace('/mfa');
    } catch (err) {
      setError(toUserMessage(err, 'Could not set your password'));
    } finally {
      setSaving(false);
    }
  }

  if (mode === 'checking') {
    return (
      <div className="auth-shell">
        <p className="status">Preparing your invite…</p>
      </div>
    );
  }

  if (mode === 'code') {
    return (
      <div className="auth-shell">
        <form className="auth-card" onSubmit={onVerifyCode}>
          <p className="eyebrow">LC Connect</p>
          <h1>Enter your invite code</h1>
          <p className="subtitle">
            You&rsquo;ve been invited as an admin. Enter your email and the code from your invite
            email.
          </p>
          {error ? <div className="error-banner">{error}</div> : null}
          <div className="field">
            <label htmlFor="email">Email</label>
            <input
              id="email"
              type="email"
              autoComplete="username"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
          </div>
          <div className="field">
            <label htmlFor="code">Invite code</label>
            <input
              id="code"
              inputMode="numeric"
              autoComplete="one-time-code"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              required
            />
          </div>
          <button className="btn" type="submit" disabled={verifying}>
            {verifying ? 'Verifying…' : 'Continue'}
          </button>
          <p className="hint">
            Code expired or never arrived? Ask whoever invited you to send a new one, or{' '}
            <a href="/login">sign in</a> if you already set a password.
          </p>
        </form>
      </div>
    );
  }

  return (
    <div className="auth-shell">
      <form className="auth-card" onSubmit={onSetPassword}>
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
        <button className="btn" type="submit" disabled={saving}>
          {saving ? 'Saving…' : 'Continue'}
        </button>
      </form>
    </div>
  );
}
