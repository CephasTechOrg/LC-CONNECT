'use client';

import { FormEvent, useState } from 'react';
import { forgotPassword, toUserMessage } from '@/lib/api/client';

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState('');
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setLoading(true);
    try {
      await forgotPassword(email.trim());
      setSubmitted(true);
    } catch (err) {
      setError(toUserMessage(err, 'Something went wrong. Please try again.'));
    } finally {
      setLoading(false);
    }
  }

  if (submitted) {
    return (
      <div className="auth-shell">
        <div className="auth-card">
          <p className="eyebrow">LC Connect</p>
          <h1>Check your email</h1>
          <p className="subtitle">
            If an account exists for that email, we&rsquo;ve sent a reset link and code to it.
          </p>
          <a className="btn" href="/reset-password">
            I have my code
          </a>
          <p className="hint">
            <a href="/login">Back to sign in</a>
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="auth-shell">
      <form className="auth-card" onSubmit={onSubmit}>
        <p className="eyebrow">LC Connect</p>
        <h1>Reset your password</h1>
        <p className="subtitle">Enter your email and we&rsquo;ll send you a reset link and code.</p>
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
        <button className="btn" type="submit" disabled={loading}>
          {loading ? 'Sending…' : 'Send reset link'}
        </button>
        <p className="hint">
          <a href="/login">Back to sign in</a>
        </p>
      </form>
    </div>
  );
}
