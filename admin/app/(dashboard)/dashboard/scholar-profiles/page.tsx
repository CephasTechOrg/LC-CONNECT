'use client';

import { useCallback, useEffect, useState } from 'react';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type ScholarProfile = {
  id: string;
  user_id: string;
  user_email: string;
  display_name: string | null;
  summary: string | null;
  skills: string[];
  career_interests: string[];
  internships: Array<{ title?: string; organization?: string; description?: string | null }>;
  projects: Array<{ name?: string; role?: string | null; url?: string | null; description?: string | null }>;
  linkedin_url: string | null;
  handshake_url: string | null;
  has_headshot: boolean;
  has_resume: boolean;
  employer_visibility_consent: boolean;
  review_status: string;
  review_note: string | null;
  submitted_at: string | null;
  reviewed_at: string | null;
};

type StatusTab = 'pending_review' | 'approved' | 'changes_requested' | 'revoked';

const TABS: { id: StatusTab; label: string }[] = [
  { id: 'pending_review', label: 'Pending' },
  { id: 'approved', label: 'Approved' },
  { id: 'changes_requested', label: 'Changes requested' },
  { id: 'revoked', label: 'Revoked' },
];

function statusChip(status: string): string {
  if (status === 'approved') return 'ops-chip success';
  if (status === 'revoked') return 'ops-chip danger';
  if (status === 'changes_requested') return 'ops-chip warn';
  if (status === 'pending_review') return 'ops-chip warn';
  return 'ops-chip muted';
}

function statusLabel(status: string): string {
  return status.replace(/_/g, ' ');
}

function when(iso: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString();
}

function initials(name: string | null, email: string): string {
  const source = (name || email.split('@')[0]).replace(/[._-]+/g, ' ').trim();
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/** Defense in depth — only render http(s) links even if a stale row slipped past validation. */
function safeExternalHref(url: string | null | undefined): string | null {
  if (!url) return null;
  try {
    const parsed = new URL(url);
    if (parsed.protocol === 'http:' || parsed.protocol === 'https:') return parsed.href;
  } catch {
    /* ignore */
  }
  return null;
}

export default function ScholarProfilesPage() {
  const [tab, setTab] = useState<StatusTab>('pending_review');
  const [items, setItems] = useState<ScholarProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [status, setStatus] = useState('');
  const [flash, setFlash] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [drawer, setDrawer] = useState<ScholarProfile | null>(null);
  const [note, setNote] = useState('');

  const load = useCallback(async (which: StatusTab) => {
    setLoading(true);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<ScholarProfile[]>(`/admin/scholar-profiles?status=${which}`, token);
      setItems(data);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    setDrawer(null);
    setNote('');
    setFlash(null);
    void load(tab);
  }, [tab, load]);

  async function onApprove(item: ScholarProfile) {
    setBusy(item.id);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/scholar-profiles/${item.id}/approve`, token, { method: 'POST' });
      setFlash(`Approved ${item.display_name || item.user_email} — now visible to employer partners.`);
      setDrawer(null);
      await load(tab);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not approve this profile.'));
    } finally {
      setBusy(null);
    }
  }

  async function onRequestChanges(item: ScholarProfile) {
    const reason = note.trim();
    if (!reason) {
      setStatus('Add a short note explaining what to change.');
      setError(true);
      return;
    }
    setBusy(item.id);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/scholar-profiles/${item.id}/request-changes`, token, {
        method: 'POST',
        body: JSON.stringify({ reason }),
      });
      setFlash(`Sent ${item.display_name || item.user_email} back for changes.`);
      setDrawer(null);
      setNote('');
      await load(tab);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not request changes.'));
    } finally {
      setBusy(null);
    }
  }

  async function onRevoke(item: ScholarProfile) {
    if (!window.confirm(`Revoke employer visibility for ${item.display_name || item.user_email}?`)) return;
    setBusy(item.id);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/scholar-profiles/${item.id}/revoke`, token, {
        method: 'POST',
        body: JSON.stringify({ reason: note.trim() || null }),
      });
      setFlash(`Revoked ${item.display_name || item.user_email} from the partner directory.`);
      setDrawer(null);
      await load(tab);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not revoke this profile.'));
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <header className="ops-top">
        <div>
          <h1>Blueprint Bond profiles</h1>
          <p>
            Review professional profiles before they appear to employer partners. Consent alone is not
            enough — Honors approval is required.
          </p>
        </div>
      </header>

      <div className="content" style={{ paddingTop: 8 }}>
        {error ? <div className="error-banner">{status}</div> : null}

        <div className="ops-toolbar">
          <div className="seg-tabs">
            {TABS.map((t) => (
              <button
                key={t.id}
                type="button"
                className={`seg-tab${tab === t.id ? ' active' : ''}`}
                onClick={() => setTab(t.id)}
              >
                {t.label}
              </button>
            ))}
          </div>
          <span className="ops-count">{loading ? '…' : `${items.length} profiles`}</span>
          <button className="ops-btn" type="button" disabled={loading} onClick={() => void load(tab)}>
            Refresh
          </button>
        </div>

        {flash ? <p className="ops-flash">{flash}</p> : null}

        <div className="ops-table-wrap table-scroll">
          {loading ? (
            <OpsLoading label="Loading profiles…" />
          ) : items.length === 0 ? (
            <OpsEmpty title={`No ${TABS.find((t) => t.id === tab)?.label.toLowerCase()} profiles`}>
              {tab === 'pending_review'
                ? 'No profiles are waiting for Honors review.'
                : `No profiles in this status.`}
            </OpsEmpty>
          ) : (
            <table className="ops-table">
              <thead>
                <tr>
                  <th>Scholar</th>
                  <th>Email</th>
                  <th>Submitted</th>
                  <th>Status</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {items.map((item) => {
                  const label = item.display_name || item.user_email;
                  return (
                    <tr key={item.id}>
                      <td>
                        <div className="ops-user-cell">
                          <div className="ops-avatar">{initials(item.display_name, item.user_email)}</div>
                          <div className="ops-cell-title">{label}</div>
                        </div>
                      </td>
                      <td>{item.user_email}</td>
                      <td className="meta">{when(item.submitted_at)}</td>
                      <td>
                        <span className={statusChip(item.review_status)}>
                          {statusLabel(item.review_status)}
                        </span>
                      </td>
                      <td className="ops-col-actions">
                        <div className="ops-row-actions">
                          <button
                            type="button"
                            className="ops-btn"
                            onClick={() => {
                              setDrawer(item);
                              setNote('');
                              setError(false);
                            }}
                          >
                            Review
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {drawer ? (
        <>
          <div className="ops-drawer-backdrop" onClick={() => setDrawer(null)} aria-hidden />
          <aside className="ops-drawer" role="dialog" aria-label="Review Blueprint Bond profile">
            <div className="ops-drawer-head">
              <div>
                <h2>{drawer.display_name || 'Scholar'}</h2>
                <div className="ops-drawer-meta">
                  <span className={statusChip(drawer.review_status)}>
                    {statusLabel(drawer.review_status)}
                  </span>
                </div>
              </div>
              <button
                className="ops-drawer-close"
                type="button"
                aria-label="Close"
                onClick={() => setDrawer(null)}
              >
                ✕
              </button>
            </div>

            <div className="ops-drawer-grid">
              <div className="ops-drawer-field">
                <label>Email</label>
                <div>{drawer.user_email}</div>
              </div>
              <div className="ops-drawer-field">
                <label>Documents</label>
                <div>
                  Headshot {drawer.has_headshot ? '✓' : '—'} · Résumé {drawer.has_resume ? '✓' : '—'} · Consent{' '}
                  {drawer.employer_visibility_consent ? '✓' : '—'}
                </div>
              </div>
            </div>

            {drawer.summary ? (
              <div className="field">
                <label>Summary</label>
                <p className="meta" style={{ margin: 0, whiteSpace: 'pre-wrap' }}>{drawer.summary}</p>
              </div>
            ) : null}

            {drawer.skills.length > 0 ? (
              <div className="field">
                <label>Skills</label>
                <div className="tag-row" style={{ justifyContent: 'flex-start' }}>
                  {drawer.skills.map((s) => (
                    <span className="tag" key={s}>{s}</span>
                  ))}
                </div>
              </div>
            ) : null}

            {drawer.career_interests.length > 0 ? (
              <div className="field">
                <label>Career interests</label>
                <div className="tag-row" style={{ justifyContent: 'flex-start' }}>
                  {drawer.career_interests.map((s) => (
                    <span className="tag" key={s}>{s}</span>
                  ))}
                </div>
              </div>
            ) : null}

            {(drawer.internships?.length ?? 0) > 0 ? (
              <div className="field">
                <label>Experience</label>
                <ul style={{ margin: 0, paddingLeft: 18, fontSize: 13.5 }}>
                  {drawer.internships.map((i, idx) => (
                    <li key={idx}>
                      <strong>{i.title}</strong> · {i.organization}
                      {i.description ? <div className="meta">{i.description}</div> : null}
                    </li>
                  ))}
                </ul>
              </div>
            ) : null}

            {(drawer.projects?.length ?? 0) > 0 ? (
              <div className="field">
                <label>Projects</label>
                <ul style={{ margin: 0, paddingLeft: 18, fontSize: 13.5 }}>
                  {drawer.projects.map((p, idx) => (
                    <li key={idx}>
                      <strong>{p.name}</strong>
                      {p.role ? ` · ${p.role}` : ''}
                      {safeExternalHref(p.url) ? (
                        <>
                          {' · '}
                          <a href={safeExternalHref(p.url)!} target="_blank" rel="noopener noreferrer">Link</a>
                        </>
                      ) : null}
                      {p.description ? <div className="meta">{p.description}</div> : null}
                    </li>
                  ))}
                </ul>
              </div>
            ) : null}

            {(safeExternalHref(drawer.linkedin_url) || safeExternalHref(drawer.handshake_url)) ? (
              <div className="field">
                <label>Links</label>
                <div style={{ fontSize: 13.5 }}>
                  {safeExternalHref(drawer.linkedin_url) ? (
                    <div>
                      <a href={safeExternalHref(drawer.linkedin_url)!} target="_blank" rel="noopener noreferrer">
                        LinkedIn
                      </a>
                    </div>
                  ) : null}
                  {safeExternalHref(drawer.handshake_url) ? (
                    <div>
                      <a href={safeExternalHref(drawer.handshake_url)!} target="_blank" rel="noopener noreferrer">
                        Handshake
                      </a>
                    </div>
                  ) : null}
                </div>
              </div>
            ) : null}

            {drawer.review_note ? (
              <div className="field">
                <label>Last review note</label>
                <p className="meta" style={{ margin: 0 }}>{drawer.review_note}</p>
              </div>
            ) : null}

            {(tab === 'pending_review' || tab === 'approved') ? (
              <div className="field">
                <label htmlFor="profile-note">
                  {tab === 'pending_review' ? 'Note (required to request changes)' : 'Note (optional for revoke)'}
                </label>
                <textarea
                  id="profile-note"
                  rows={3}
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder={
                    tab === 'pending_review'
                      ? 'What should the scholar fix before you approve?'
                      : 'Optional reason for revoking visibility'
                  }
                />
              </div>
            ) : null}

            <div className="ops-drawer-footer">
              {tab === 'pending_review' ? (
                <>
                  <button
                    className="btn ghost"
                    type="button"
                    disabled={busy === drawer.id}
                    onClick={() => void onRequestChanges(drawer)}
                  >
                    Request changes
                  </button>
                  <button
                    className="btn"
                    type="button"
                    disabled={busy === drawer.id}
                    onClick={() => void onApprove(drawer)}
                  >
                    {busy === drawer.id ? 'Working…' : 'Approve'}
                  </button>
                </>
              ) : null}
              {tab === 'approved' ? (
                <button
                  className="btn danger"
                  type="button"
                  disabled={busy === drawer.id}
                  onClick={() => void onRevoke(drawer)}
                >
                  {busy === drawer.id ? 'Working…' : 'Revoke visibility'}
                </button>
              ) : null}
            </div>
          </aside>
        </>
      ) : null}
    </>
  );
}
