'use client';

import { useEffect, useState } from 'react';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

export type ScholarProfileReviewItem = {
  id: string;
  user_id: string;
  user_email: string;
  display_name: string | null;
  summary: string | null;
  skills: string[];
  career_interests: string[];
  internships: Array<{
    title?: string;
    organization?: string;
    start_date?: string | null;
    end_date?: string | null;
    is_current?: boolean;
    description?: string | null;
  }>;
  projects: Array<{
    name?: string;
    role?: string | null;
    url?: string | null;
    description?: string | null;
  }>;
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

type SignedUrl = { url: string; expires_in: number };

function statusChip(status: string): string {
  if (status === 'approved') return 'ops-chip success';
  if (status === 'revoked') return 'ops-chip danger';
  if (status === 'changes_requested' || status === 'pending_review') return 'ops-chip warn';
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

function experienceRange(item: ScholarProfileReviewItem['internships'][number]): string | null {
  const start = item.start_date?.trim();
  if (!start && !item.is_current && !item.end_date) return null;
  if (item.is_current) return start ? `${start} – Present` : 'Current';
  const end = item.end_date?.trim();
  if (start && end) return `${start} – ${end}`;
  return start || end || null;
}

type Props = {
  item: ScholarProfileReviewItem;
  tab: 'pending_review' | 'approved' | 'changes_requested' | 'revoked';
  note: string;
  busy: boolean;
  onNoteChange: (value: string) => void;
  onClose: () => void;
  onApprove: () => void;
  onRequestChanges: () => void;
  onRevoke: () => void;
  onError: (message: string) => void;
};

export function ScholarProfileReviewDrawer({
  item,
  tab,
  note,
  busy,
  onNoteChange,
  onClose,
  onApprove,
  onRequestChanges,
  onRevoke,
  onError,
}: Props) {
  const [headshotUrl, setHeadshotUrl] = useState<string | null>(null);
  const [openingResume, setOpeningResume] = useState(false);
  const [mediaLoading, setMediaLoading] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setHeadshotUrl(null);
    if (!item.has_headshot) return;

    async function loadHeadshot() {
      setMediaLoading(true);
      try {
        const token = await getAccessToken();
        if (!token) throw new Error('Not signed in');
        const signed = await apiFetch<SignedUrl>(
          `/admin/scholar-profiles/${item.id}/headshot-url`,
          token,
        );
        if (!cancelled) setHeadshotUrl(signed.url);
      } catch (err) {
        if (!cancelled) {
          onError(toUserMessage(err, 'Could not load headshot for review.'));
        }
      } finally {
        if (!cancelled) setMediaLoading(false);
      }
    }

    void loadHeadshot();
    return () => {
      cancelled = true;
    };
  }, [item.id, item.has_headshot, onError]);

  async function openResume() {
    setOpeningResume(true);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const signed = await apiFetch<SignedUrl>(
        `/admin/scholar-profiles/${item.id}/resume-url`,
        token,
      );
      window.open(signed.url, '_blank', 'noopener,noreferrer');
    } catch (err) {
      onError(toUserMessage(err, 'Could not open résumé.'));
    } finally {
      setOpeningResume(false);
    }
  }

  const linkedin = safeExternalHref(item.linkedin_url);
  const handshake = safeExternalHref(item.handshake_url);

  return (
    <>
      <div className="ops-drawer-backdrop" onClick={onClose} aria-hidden />
      <aside className="ops-drawer ops-drawer-wide" role="dialog" aria-label="Review Blueprint Bond profile">
        <div className="ops-drawer-head">
          <div className="bb-review-identity">
            <div className="bb-review-photo">
              {headshotUrl ? (
                // Short-lived signed URL — next/image needs remote host config.
                // eslint-disable-next-line @next/next/no-img-element
                <img src={headshotUrl} alt={item.display_name || 'Scholar headshot'} />
              ) : (
                <div className="bb-review-photo-fallback" aria-hidden>
                  {mediaLoading && item.has_headshot
                    ? '…'
                    : initials(item.display_name, item.user_email)}
                </div>
              )}
            </div>
            <div className="bb-review-identity-text">
              <h2>{item.display_name || 'Scholar'}</h2>
              <p className="bb-review-email">{item.user_email}</p>
              <div className="ops-drawer-meta bb-review-meta">
                <span className={statusChip(item.review_status)}>
                  {statusLabel(item.review_status)}
                </span>
                <span className={item.employer_visibility_consent ? 'ops-chip success' : 'ops-chip muted'}>
                  {item.employer_visibility_consent ? 'Consent on' : 'Consent off'}
                </span>
              </div>
              <p className="bb-review-submitted">Submitted {when(item.submitted_at)}</p>
            </div>
          </div>
          <button className="ops-drawer-close" type="button" aria-label="Close" onClick={onClose}>
            ✕
          </button>
        </div>

        <div className="bb-review-docs">
          <div className="bb-review-doc">
            <span className="bb-review-doc-label">Headshot</span>
            <span className={item.has_headshot ? 'ops-chip success' : 'ops-chip muted'}>
              {item.has_headshot ? (mediaLoading && !headshotUrl ? 'Loading…' : 'On file') : 'Missing'}
            </span>
          </div>
          <div className="bb-review-doc">
            <span className="bb-review-doc-label">Résumé</span>
            {item.has_resume ? (
              <button
                type="button"
                className="ops-btn primary"
                disabled={openingResume}
                onClick={() => void openResume()}
              >
                {openingResume ? 'Opening…' : 'Open résumé'}
              </button>
            ) : (
              <span className="ops-chip muted">Missing</span>
            )}
          </div>
        </div>

        <section className="bb-review-section">
          <h3>Professional summary</h3>
          {item.summary ? (
            <p className="bb-review-prose">{item.summary}</p>
          ) : (
            <p className="bb-review-empty">No summary provided.</p>
          )}
        </section>

        {(item.internships?.length ?? 0) > 0 ? (
          <section className="bb-review-section">
            <h3>Experience</h3>
            <ul className="bb-review-list">
              {item.internships.map((entry, idx) => (
                <li key={`${entry.title}-${entry.organization}-${idx}`}>
                  <div className="bb-review-list-title">
                    {entry.title || 'Role'}
                    {entry.organization ? <span> · {entry.organization}</span> : null}
                  </div>
                  {experienceRange(entry) ? (
                    <div className="bb-review-list-meta">{experienceRange(entry)}</div>
                  ) : null}
                  {entry.description ? (
                    <p className="bb-review-prose bb-review-prose-sm">{entry.description}</p>
                  ) : null}
                </li>
              ))}
            </ul>
          </section>
        ) : null}

        {(item.projects?.length ?? 0) > 0 ? (
          <section className="bb-review-section">
            <h3>Projects</h3>
            <ul className="bb-review-list">
              {item.projects.map((project, idx) => {
                const href = safeExternalHref(project.url);
                return (
                  <li key={`${project.name}-${idx}`}>
                    <div className="bb-review-list-title">
                      {project.name || 'Project'}
                      {project.role ? <span> · {project.role}</span> : null}
                    </div>
                    {href ? (
                      <a href={href} target="_blank" rel="noopener noreferrer" className="bb-review-link">
                        View project
                      </a>
                    ) : null}
                    {project.description ? (
                      <p className="bb-review-prose bb-review-prose-sm">{project.description}</p>
                    ) : null}
                  </li>
                );
              })}
            </ul>
          </section>
        ) : null}

        {item.skills.length > 0 ? (
          <section className="bb-review-section">
            <h3>Skills</h3>
            <div className="tag-row" style={{ justifyContent: 'flex-start' }}>
              {item.skills.map((skill) => (
                <span className="tag" key={skill}>{skill}</span>
              ))}
            </div>
          </section>
        ) : null}

        {item.career_interests.length > 0 ? (
          <section className="bb-review-section">
            <h3>Career interests</h3>
            <div className="tag-row" style={{ justifyContent: 'flex-start' }}>
              {item.career_interests.map((interest) => (
                <span className="tag" key={interest}>{interest}</span>
              ))}
            </div>
          </section>
        ) : null}

        {(linkedin || handshake) ? (
          <section className="bb-review-section">
            <h3>Links</h3>
            <div className="bb-review-links">
              {linkedin ? (
                <a href={linkedin} target="_blank" rel="noopener noreferrer" className="bb-review-link">
                  LinkedIn profile
                </a>
              ) : null}
              {handshake ? (
                <a href={handshake} target="_blank" rel="noopener noreferrer" className="bb-review-link">
                  Handshake profile
                </a>
              ) : null}
            </div>
          </section>
        ) : null}

        {item.review_note ? (
          <section className="bb-review-section">
            <h3>Last review note</h3>
            <p className="bb-review-prose">{item.review_note}</p>
          </section>
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
              onChange={(e) => onNoteChange(e.target.value)}
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
              <button className="btn ghost" type="button" disabled={busy} onClick={onRequestChanges}>
                Request changes
              </button>
              <button className="btn" type="button" disabled={busy} onClick={onApprove}>
                {busy ? 'Working…' : 'Approve for partners'}
              </button>
            </>
          ) : null}
          {tab === 'approved' ? (
            <button className="btn danger" type="button" disabled={busy} onClick={onRevoke}>
              {busy ? 'Working…' : 'Revoke visibility'}
            </button>
          ) : null}
        </div>
      </aside>
    </>
  );
}
