'use client';

import { useEffect, useState } from 'react';
import {
  acceptEmployerAgreement,
  policyDocument,
  toUserMessage,
  type MyEmployer,
} from '@/lib/api/client';

/**
 * Blocks the dashboard until the Employer Agreement is accepted.
 *
 * Rendered from `(dashboard)/layout.tsx`, which wraps every dashboard page — so one check covers
 * `/scholars`, `/scholars/[id]` and `/opportunities` without touching each of them. That matters
 * more here than on the student side: this is the only thing standing between an approved employer
 * account and student résumés.
 *
 * The server is the real gate: the scholar endpoints and opportunity submission sit behind
 * `require_agreed_employer`, so a caller who skips this screen gets a 403 rather than résumés.
 * This component is the experience; that dependency is the enforcement.
 */
export function AgreementGate({
  employer,
  accessToken,
  onAccepted,
  onSignOut,
}: {
  employer: MyEmployer;
  accessToken: string;
  onAccepted: (next: MyEmployer) => void;
  onSignOut: () => void;
}) {
  const [agreed, setAgreed] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [body, setBody] = useState<string | null>(null);
  const [bodyError, setBodyError] = useState<string | null>(null);

  useEffect(() => {
    void (async () => {
      try {
        setBody((await policyDocument('employer-agreement')).body);
      } catch (err) {
        setBodyError(toUserMessage(err, 'Could not load the agreement'));
      }
    })();
  }, []);

  async function onAccept() {
    if (!agreed || saving) return;
    setSaving(true);
    setError(null);
    try {
      onAccepted(await acceptEmployerAgreement(accessToken));
    } catch (err) {
      setError(toUserMessage(err, 'Could not save that. Please try again.'));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="auth-shell">
      <div className="auth-card agreement-card">
        <p className="eyebrow">Blueprint Bond</p>
        <h1>Employer Agreement</h1>
        <p className="subtitle">
          Before {employer.organization_name} can view scholar profiles, please read and accept the
          Employer Agreement.
        </p>

        {error ? <div className="error-banner">{error}</div> : null}

        <div className="agreement-body" tabIndex={0} aria-label="Employer Agreement">
          {bodyError ? (
            <p className="status">{bodyError}</p>
          ) : body === null ? (
            <p className="status">Loading the agreement…</p>
          ) : (
            // Rendered as plain pre-wrapped text rather than parsed markdown: it keeps a legal
            // document byte-faithful to the file that was reviewed, and avoids pulling a markdown
            // renderer into the portal for one screen.
            <pre className="agreement-text">{body}</pre>
          )}
        </div>

        <label className="agreement-consent">
          <input
            type="checkbox"
            checked={agreed}
            disabled={saving}
            onChange={(event) => setAgreed(event.target.checked)}
          />
          <span>
            I have read the Employer Agreement and I accept it on behalf of{' '}
            {employer.organization_name}.
          </span>
        </label>

        <button className="btn" type="button" disabled={!agreed || saving} onClick={() => void onAccept()}>
          {saving ? 'Saving…' : 'Accept and continue'}
        </button>

        <p className="hint">
          <button type="button" className="link-button" onClick={onSignOut}>
            Sign out
          </button>
        </p>
      </div>
    </div>
  );
}
