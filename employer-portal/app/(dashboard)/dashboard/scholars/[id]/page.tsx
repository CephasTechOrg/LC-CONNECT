'use client';

import { useCallback, useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type ScholarView = {
  user_id: string;
  display_name: string | null;
  linkedin_url: string | null;
  handshake_url: string | null;
  summary: string | null;
  skills: string[];
  career_interests: string[];
  has_headshot: boolean;
  has_resume: boolean;
  headshot_url: string | null;
};

type SignedUrl = { url: string; expires_in: number };

function initials(name: string | null): string {
  const source = (name || 'Scholar').trim();
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0][0].toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

export default function ScholarDetailPage() {
  const params = useParams<{ id: string }>();
  const id = params.id;
  const [scholar, setScholar] = useState<ScholarView | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [openingResume, setOpeningResume] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    setLoading(true);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<ScholarView>(`/employers/scholars/${id}`, token);
      setScholar(data);
    } catch (err) {
      setError(toUserMessage(err, 'Could not load this scholar'));
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    void load();
  }, [load]);

  async function openResume() {
    setOpeningResume(true);
    try {
      const token = await getAccessToken();
      if (!token) return;
      const signed = await apiFetch<SignedUrl>(`/employers/scholars/${id}/resume-url`, token);
      window.open(signed.url, '_blank', 'noopener,noreferrer');
    } catch (err) {
      setError(toUserMessage(err, 'Could not open the résumé. Please try again.'));
    } finally {
      setOpeningResume(false);
    }
  }

  if (loading) {
    return (
      <div className="ops-table-wrap">
        <OpsLoading label="Loading scholar…" />
      </div>
    );
  }

  if (error && !scholar) {
    return (
      <div className="ops-table-wrap">
        <OpsEmpty title="Could not load profile">{error}</OpsEmpty>
        <div className="actions" style={{ justifyContent: 'center', paddingBottom: 24 }}>
          <Link className="btn ghost" href="/dashboard/scholars">
            Back to directory
          </Link>
        </div>
      </div>
    );
  }

  if (!scholar) return null;

  return (
    <>
      <header className="ops-top">
        <div>
          <Link href="/dashboard/scholars" style={{ fontSize: 13, fontWeight: 600 }}>
            ← Scholar Directory
          </Link>
          <h1 style={{ marginTop: 8 }}>{scholar.display_name || 'Presidential Scholar'}</h1>
          <p>Presidential Scholar • Blueprint Bond</p>
        </div>
      </header>

      {error ? <div className="error-banner">{error}</div> : null}

      <div className="dashboard-grid" style={{ marginTop: 8 }}>
        <div className="panel">
          <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
            {scholar.headshot_url ? (
              /* Short-lived signed Supabase URL — next/image needs remote-host config. */
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={scholar.headshot_url}
                alt={scholar.display_name || 'Scholar headshot'}
                className="scholar-avatar"
                style={{ margin: 0, width: 88, height: 88, objectFit: 'cover' }}
              />
            ) : (
              <div className="scholar-avatar" style={{ margin: 0, width: 88, height: 88, fontSize: 26 }}>
                {initials(scholar.display_name)}
              </div>
            )}
            <div>
              <h2 style={{ margin: '0 0 4px', fontSize: 20 }}>
                {scholar.display_name || 'Presidential Scholar'}
              </h2>
              <p className="meta" style={{ margin: 0 }}>
                Opted in to employer visibility
              </p>
            </div>
          </div>

          {scholar.summary ? (
            <>
              <h3 style={{ fontSize: 13.5, marginTop: 20, marginBottom: 6, color: 'var(--text-mid)' }}>
                Summary
              </h3>
              <p style={{ margin: 0, fontSize: 14, lineHeight: 1.6, color: 'var(--text)' }}>{scholar.summary}</p>
            </>
          ) : null}

          {scholar.skills.length > 0 ? (
            <>
              <h3 style={{ fontSize: 13.5, marginTop: 20, marginBottom: 8, color: 'var(--text-mid)' }}>Skills</h3>
              <div className="tag-row" style={{ justifyContent: 'flex-start' }}>
                {scholar.skills.map((s) => (
                  <span className="tag" key={s}>{s}</span>
                ))}
              </div>
            </>
          ) : null}

          {scholar.career_interests.length > 0 ? (
            <>
              <h3 style={{ fontSize: 13.5, marginTop: 20, marginBottom: 8, color: 'var(--text-mid)' }}>
                Career interests
              </h3>
              <div className="tag-row" style={{ justifyContent: 'flex-start' }}>
                {scholar.career_interests.map((s) => (
                  <span className="tag" key={s}>{s}</span>
                ))}
              </div>
            </>
          ) : null}
        </div>

        <div className="panel">
          <div className="panel-head">
            <h2>Contact &amp; documents</h2>
          </div>
          {scholar.linkedin_url ? (
            <p style={{ fontSize: 13.5, marginBottom: 8 }}>
              <a href={scholar.linkedin_url} target="_blank" rel="noopener noreferrer">
                LinkedIn profile
              </a>
            </p>
          ) : null}
          {scholar.handshake_url ? (
            <p style={{ fontSize: 13.5, marginBottom: 8 }}>
              <a href={scholar.handshake_url} target="_blank" rel="noopener noreferrer">
                Handshake profile
              </a>
            </p>
          ) : null}
          <div className="actions" style={{ justifyContent: 'flex-start', marginTop: 0, gap: 8 }}>
            {scholar.has_resume ? (
              <button
                className="btn ghost"
                type="button"
                disabled={openingResume}
                onClick={() => void openResume()}
              >
                {openingResume ? 'Opening…' : 'View résumé'}
              </button>
            ) : null}
          </div>
          {!scholar.has_resume ? (
            <p className="hint" style={{ marginTop: 0 }}>
              No résumé on file yet.
            </p>
          ) : null}
        </div>
      </div>
    </>
  );
}
