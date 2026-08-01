'use client';

import { FormEvent, useState } from 'react';
import Link from 'next/link';
import { apiFetch, toUserMessage } from '@/lib/api/client';

export default function RegisterPage() {
  const [organizationName, setOrganizationName] = useState('');
  const [contactName, setContactName] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await apiFetch('/employers/register', null, {
        method: 'POST',
        body: JSON.stringify({
          organization_name: organizationName.trim(),
          contact_name: contactName.trim(),
          contact_email: contactEmail.trim().toLowerCase(),
        }),
      });
      setSubmitted(true);
    } catch (err) {
      setError(toUserMessage(err, 'Could not submit your application. Please try again.'));
    } finally {
      setSubmitting(false);
    }
  }

  if (submitted) {
    return (
      <div className="auth-shell">
        <div className="auth-card">
          <p className="eyebrow">Blueprint Bond</p>
          <h1>Application received</h1>
          <p className="subtitle">
            Thank you for registering. An Honors Program administrator will review your
            organization. Once approved, we&apos;ll send an invite email to set your password and
            sign in.
          </p>
          <Link className="btn" href="/login">
            Back to sign in
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="auth-shell">
      <form className="auth-card" onSubmit={onSubmit}>
        <p className="eyebrow">Blueprint Bond • Powered by LC Connect</p>
        <h1>Register your organization</h1>
        <p className="subtitle">
          Employer partners are reviewed by Livingstone College&apos;s Honors Program before
          gaining access. Tell us about your organization to get started.
        </p>
        {error ? <div className="error-banner">{error}</div> : null}
        <div className="field">
          <label htmlFor="organization-name">Organization name</label>
          <input
            id="organization-name"
            type="text"
            value={organizationName}
            onChange={(e) => setOrganizationName(e.target.value)}
            required
          />
        </div>
        <div className="field">
          <label htmlFor="contact-name">Your name</label>
          <input
            id="contact-name"
            type="text"
            value={contactName}
            onChange={(e) => setContactName(e.target.value)}
            required
          />
        </div>
        <div className="field">
          <label htmlFor="contact-email">Work email</label>
          <input
            id="contact-email"
            type="email"
            value={contactEmail}
            onChange={(e) => setContactEmail(e.target.value)}
            required
          />
        </div>
        <button className="btn" type="submit" disabled={submitting}>
          {submitting ? 'Submitting…' : 'Submit for review'}
        </button>
        <p className="hint">
          Already approved? <Link href="/login">Sign in</Link>
        </p>
      </form>
    </div>
  );
}
