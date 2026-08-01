'use client';

import { FormEvent, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

type Mode = 'checking' | 'code' | 'password';

export default function ResetPasswordPage() {
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
      // Clicking the reset link auto-establishes a session (Supabase's client detects the token
      // in the URL). If that already happened, skip straight to choosing a new password —
      // otherwise fall back to the "enter the code from your email" step.
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
        type: 'recovery',
      });
      if (verifyError) throw verifyError;
      setMode('password');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'That code is invalid or has expired.');
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
      router.replace('/dashboard');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not set your password');
    } finally {
      setSaving(false);
    }
  }

  if (mode === 'checking') {
    return (
      <div className="auth-shell">
        <p className="status">Preparing…</p>
      </div>
    );
  }

  if (mode === 'code') {
    return (
      <div className="auth-shell">
        <form className="auth-card" onSubmit={onVerifyCode}>
          <p className="eyebrow">Blueprint Bond • Powered by LC Connect</p>
          <h1>Enter your reset code</h1>
          <p className="subtitle">
            Enter your email and the code from your password reset email (some mail clients
            don&rsquo;t open the link directly, so we accept the code too).
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
            <label htmlFor="code">Reset code</label>
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
            No code yet? <a href="/forgot-password">Request a reset</a>, or{' '}
            <a href="/login">sign in</a> if you remember your password.
          </p>
        </form>
      </div>
    );
  }

  return (
    <div className="auth-shell">
      <form className="auth-card" onSubmit={onSetPassword}>
        <p className="eyebrow">Blueprint Bond • Powered by LC Connect</p>
        <h1>Choose a new password</h1>
        <p className="subtitle">Set a new password for your employer partner account.</p>
        {error ? <div className="error-banner">{error}</div> : null}
        <div className="field">
          <label htmlFor="password">New password</label>
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
          <label htmlFor="confirm-password">Confirm new password</label>
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
