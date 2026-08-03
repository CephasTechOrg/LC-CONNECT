'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
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

function statusChip(status: Submission['status']): string {
  if (status === 'approved') return 'ops-chip success';
  if (status === 'rejected') return 'ops-chip danger';
  return 'ops-chip warn';
}

function when(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString();
}

export default function OpportunitiesPage() {
  const [submissions, setSubmissions] = useState<Submission[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);

  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [category, setCategory] = useState<Category>('internship');
  const [externalUrl, setExternalUrl] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [flash, setFlash] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    setLoading(true);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<Submission[]>('/employers/opportunities/me', token);
      setSubmissions(data);
    } catch (err) {
      setError(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setFlash(null);
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
      setFlash('Submitted for Honors Program review.');
      setTitle('');
      setDescription('');
      setCategory('internship');
      setExternalUrl('');
      setShowForm(false);
      await load();
    } catch (err) {
      setError(toUserMessage(err, 'Could not submit opportunity'));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <>
      <header className="ops-top">
        <div>
          <h1>Opportunities</h1>
          <p>Submit roles for Presidential Scholars — every submission is reviewed before it goes live.</p>
        </div>
        <button
          className="ops-btn primary"
          type="button"
          onClick={() => setShowForm((v) => !v)}
        >
          {showForm ? 'Close form' : 'New opportunity'}
        </button>
      </header>

      <div style={{ paddingTop: 8 }}>
        {error ? <div className="error-banner">{error}</div> : null}
        {flash && !error ? <p className="ops-flash">{flash}</p> : null}

        {showForm ? (
          <form className="ops-form" onSubmit={onSubmit}>
            <h2>New opportunity</h2>
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
            <div className="actions">
              <button className="btn" type="submit" disabled={submitting}>
                {submitting ? 'Submitting…' : 'Submit for review'}
              </button>
              <button className="btn ghost" type="button" onClick={() => setShowForm(false)}>
                Cancel
              </button>
            </div>
          </form>
        ) : null}

        <div className="ops-toolbar">
          <span className="ops-count" style={{ marginLeft: 0 }}>
            {loading ? '…' : `${submissions.length} submission${submissions.length === 1 ? '' : 's'}`}
          </span>
          <button className="ops-btn" type="button" disabled={loading} onClick={() => void load()}>
            Refresh
          </button>
        </div>

        <div className="ops-table-wrap table-scroll">
          {loading ? (
            <OpsLoading label="Loading opportunities…" />
          ) : submissions.length === 0 ? (
            <OpsEmpty title="Nothing submitted yet">
              Use New opportunity to send a role for Honors Program review.
            </OpsEmpty>
          ) : (
            <table className="ops-table">
              <thead>
                <tr>
                  <th>Opportunity</th>
                  <th>Category</th>
                  <th>Link</th>
                  <th>Submitted</th>
                  <th>Status</th>
                  <th>Review note</th>
                </tr>
              </thead>
              <tbody>
                {submissions.map((s) => (
                  <tr key={s.id}>
                    <td>
                      <div className="ops-cell-title">{s.title}</div>
                      <div className="ops-cell-sub">{s.description.slice(0, 90)}</div>
                    </td>
                    <td style={{ textTransform: 'capitalize' }}>{s.category}</td>
                    <td>
                      {s.external_url ? (
                        <a href={s.external_url} target="_blank" rel="noopener noreferrer">
                          Link
                        </a>
                      ) : (
                        <span className="ops-cell-sub">—</span>
                      )}
                    </td>
                    <td>{when(s.created_at)}</td>
                    <td><span className={statusChip(s.status)}>{s.status}</span></td>
                    <td>
                      {s.review_note ? (
                        <span className="ops-cell-sub">{s.review_note}</span>
                      ) : (
                        <span className="ops-cell-sub">—</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </>
  );
}
