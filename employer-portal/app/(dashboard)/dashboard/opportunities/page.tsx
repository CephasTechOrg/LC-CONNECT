'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

const CATEGORIES = ['internship', 'job', 'volunteer', 'leadership'] as const;
type Category = (typeof CATEGORIES)[number];

type Submission = {
  id: string;
  title: string;
  description: string;
  category: string;
  external_url: string | null;
  status: 'pending' | 'approved' | 'rejected';
  review_note: string | null;
  created_at: string;
};

function badgeClass(status: Submission['status']): string {
  if (status === 'approved') return 'badge success';
  if (status === 'rejected') return 'badge danger';
  return 'badge';
}

export default function OpportunitiesPage() {
  const [submissions, setSubmissions] = useState<Submission[]>([]);
  const [status, setStatus] = useState('Loading…');
  const [error, setError] = useState(false);

  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [category, setCategory] = useState<Category>('internship');
  const [externalUrl, setExternalUrl] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [formSuccess, setFormSuccess] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(false);
    setStatus('Loading…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<Submission[]>('/employers/opportunities/me', token);
      setSubmissions(data);
      setStatus(data.length ? `${data.length} submission(s).` : 'No opportunities submitted yet.');
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setFormError(null);
    setFormSuccess(null);
    setSubmitting(true);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      await apiFetch('/employers/opportunities', token, {
        method: 'POST',
        body: JSON.stringify({
          title: title.trim(),
          description: description.trim(),
          category,
          external_url: externalUrl.trim() || null,
        }),
      });
      setFormSuccess('Submitted for Honors Program review.');
      setTitle('');
      setDescription('');
      setCategory('internship');
      setExternalUrl('');
      await load();
    } catch (err) {
      setFormError(toUserMessage(err, 'Could not submit opportunity'));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <>
      <div className="page-header">
        <h1>Opportunities</h1>
        <p>Submit roles for Presidential Scholars — every submission is reviewed before it goes live</p>
      </div>

      <div className="dashboard-grid">
        <div className="panel">
          <div className="panel-head">
            <h2>New Opportunity</h2>
          </div>
          <form onSubmit={onSubmit}>
            {formError ? <div className="error-banner">{formError}</div> : null}
            {formSuccess ? <div className="success-banner">{formSuccess}</div> : null}
            <div className="field">
              <label htmlFor="title">Title</label>
              <input
                id="title"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                required
                maxLength={200}
              />
            </div>
            <div className="field">
              <label htmlFor="category">Category</label>
              <select id="category" value={category} onChange={(e) => setCategory(e.target.value as Category)}>
                {CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {c[0].toUpperCase() + c.slice(1)}
                  </option>
                ))}
              </select>
            </div>
            <div className="field">
              <label htmlFor="description">Description</label>
              <textarea
                id="description"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                required
                maxLength={8000}
                rows={5}
              />
            </div>
            <div className="field">
              <label htmlFor="external_url">External link (optional)</label>
              <input
                id="external_url"
                type="url"
                value={externalUrl}
                onChange={(e) => setExternalUrl(e.target.value)}
                placeholder="https://…"
              />
            </div>
            <button className="btn" type="submit" disabled={submitting}>
              {submitting ? 'Submitting…' : 'Submit for review'}
            </button>
          </form>
        </div>

        <div className="panel">
          <div className="panel-head">
            <h2>Your Submissions</h2>
            <button className="btn ghost" type="button" onClick={() => void load()} style={{ width: 'auto' }}>
              Refresh
            </button>
          </div>
          <p className={`status${error ? ' error' : ''}`}>{status}</p>
          {submissions.length === 0 ? (
            <div className="empty">Nothing submitted yet.</div>
          ) : (
            <div className="card-list">
              {submissions.map((s) => (
                <div className="card" key={s.id}>
                  <div className="actions" style={{ justifyContent: 'space-between', marginTop: 0 }}>
                    <strong>{s.title}</strong>
                    <span className={badgeClass(s.status)}>{s.status}</span>
                  </div>
                  <p className="meta" style={{ margin: '4px 0' }}>
                    {s.category}
                    {s.external_url ? (
                      <>
                        {' • '}
                        <a href={s.external_url} target="_blank" rel="noopener noreferrer">
                          link
                        </a>
                      </>
                    ) : null}
                  </p>
                  <p style={{ fontSize: 13.5, margin: '4px 0' }}>{s.description}</p>
                  {s.review_note ? (
                    <p className="hint" style={{ margin: '4px 0 0' }}>
                      Reviewer note: {s.review_note}
                    </p>
                  ) : null}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </>
  );
}
