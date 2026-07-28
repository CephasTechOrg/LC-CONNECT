'use client';

import { FormEvent, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

export default function MfaPage() {
  const router = useRouter();
  const [mode, setMode] = useState<'loading' | 'enroll' | 'verify'>('loading');
  const [factorId, setFactorId] = useState<string | null>(null);
  const [qr, setQr] = useState<string | null>(null);
  const [secret, setSecret] = useState<string | null>(null);
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    void (async () => {
      const supabase = createClient();
      const { data: sessionData } = await supabase.auth.getSession();
      if (!sessionData.session) {
        router.replace('/login');
        return;
      }

      const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
      if (aal?.currentLevel === 'aal2') {
        router.replace('/dashboard');
        return;
      }

      const { data: factors } = await supabase.auth.mfa.listFactors();
      const verified = factors?.totp?.find((f) => f.status === 'verified');
      if (verified) {
        setFactorId(verified.id);
        setMode('verify');
        return;
      }

      const { data: enroll, error: enrollError } = await supabase.auth.mfa.enroll({
        factorType: 'totp',
        friendlyName: 'LC Connect Admin',
      });
      if (enrollError) {
        setError(enrollError.message);
        setMode('verify');
        return;
      }
      setFactorId(enroll.id);
      setQr(enroll.totp.qr_code);
      setSecret(enroll.totp.secret);
      setMode('enroll');
    })();
  }, [router]);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    if (!factorId) return;
    setLoading(true);
    setError(null);
    try {
      const supabase = createClient();
      const challenge = await supabase.auth.mfa.challenge({ factorId });
      if (challenge.error) throw challenge.error;
      const verified = await supabase.auth.mfa.verify({
        factorId,
        challengeId: challenge.data.id,
        code: code.trim(),
      });
      if (verified.error) throw verified.error;
      router.replace('/dashboard');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'MFA verification failed');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="auth-shell">
      <form className="auth-card" onSubmit={onSubmit}>
        <p className="eyebrow">Security</p>
        <h1>{mode === 'enroll' ? 'Set up MFA' : 'Enter MFA code'}</h1>
        <p className="subtitle">
          Admin APIs require authenticator assurance level 2 (TOTP).
        </p>
        {error ? <div className="error-banner">{error}</div> : null}
        {mode === 'loading' ? <p className="status">Preparing MFA…</p> : null}
        {mode === 'enroll' && qr ? (
          <div style={{ textAlign: 'center', marginBottom: 16 }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={qr} alt="MFA QR code" width={180} height={180} />
            {secret ? (
              <p className="hint">
                Or enter secret manually: <code>{secret}</code>
              </p>
            ) : null}
          </div>
        ) : null}
        {mode !== 'loading' ? (
          <>
            <div className="field">
              <label htmlFor="code">Authenticator code</label>
              <input
                id="code"
                inputMode="numeric"
                autoComplete="one-time-code"
                value={code}
                onChange={(e) => setCode(e.target.value)}
                required
              />
            </div>
            <button className="btn" type="submit" disabled={loading || !factorId}>
              {loading ? 'Verifying…' : 'Continue'}
            </button>
          </>
        ) : null}
      </form>
    </div>
  );
}
