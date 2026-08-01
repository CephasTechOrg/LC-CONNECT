'use client';

import { useCallback, useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
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
  const [scholar, setScholar] = useState<ScholarView | null>(null);
  const [status, setStatus] = useState('Loading…');
  const [error, setError] = useState(false);
  const [busyDocument, setBusyDocument] = useState<'headshot' | 'resume' | null>(null);

  const load = useCallback(async () => {
    setError(false);
    setStatus('Loading…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<ScholarView>(`/employers/scholars/${params.id}`, token);
      setScholar(data);
      setStatus('');
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load this scholar'));
    }
  }, [params.id]);

  useEffect(() => {
    void load();
  }, [load]);

  async function openDocument(kind: 'headshot' | 'resume') {
    setBusyDocument(kind);
    try {
      const token = await getAccessToken();
      if (!token) return;
      const signed = await apiFetch<SignedUrl>(`/employers/scholars/${params.id}/${kind}-url`, token);
      window.open(signed.url, '_blank', 'noopener,noreferrer');
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, `Could not open ${kind}`));
    } finally {
      setBusyDocument(null);
    }
  }

  if (error && !scholar) {
    return (
      <div className="panel">
        <div className="empty">{status}</div>
        <div className="actions" style={{ justifyContent: 'center' }}>
          <Link className="btn ghost" href="/dashboard/scholars" style={{ width: 'auto' }}>
            Back to directory
          </Link>
        </div>
      </div>
    );
  }

  if (!scholar) {
    return <p className="status">{status}</p>;
  }

  return (
    <>
      <div className="page-header">
        <Link href="/dashboard/scholars" style={{ fontSize: 13, fontWeight: 600 }}>
          ← Scholar Directory
        </Link>
      </div>

      <div className="dashboard-grid">
        <div className="panel">
          <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
            <div className="scholar-avatar" style={{ margin: 0, width: 88, height: 88, fontSize: 26 }}>
              {initials(scholar.display_name)}
            </div>
            <div>
              <h2 style={{ margin: '0 0 4px', fontSize: 20 }}>
                {scholar.display_name || 'Presidential Scholar'}
              </h2>
              <p className="meta" style={{ margin: 0 }}>
                Presidential Scholar • Blueprint Bond
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
                  <span className="tag" key={s}>
                    {s}
                  </span>
                ))}
              </div>
            </>
          ) : null}

          {scholar.career_interests.length > 0 ? (
            <>
              <h3 style={{ fontSize: 13.5, marginTop: 20, marginBottom: 8, color: 'var(--text-mid)' }}>
                Career Interests
              </h3>
              <div className="tag-row" style={{ justifyContent: 'flex-start' }}>
                {scholar.career_interests.map((s) => (
                  <span className="tag" key={s}>
                    {s}
                  </span>
                ))}
              </div>
            </>
          ) : null}
        </div>

        <div className="panel">
          <div className="panel-head">
            <h2>Contact &amp; Documents</h2>
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
            {scholar.has_headshot ? (
              <button
                className="btn ghost"
                type="button"
                disabled={busyDocument === 'headshot'}
                onClick={() => void openDocument('headshot')}
                style={{ width: 'auto' }}
              >
                {busyDocument === 'headshot' ? 'Opening…' : 'View headshot'}
              </button>
            ) : null}
            {scholar.has_resume ? (
              <button
                className="btn ghost"
                type="button"
                disabled={busyDocument === 'resume'}
                onClick={() => void openDocument('resume')}
                style={{ width: 'auto' }}
              >
                {busyDocument === 'resume' ? 'Opening…' : 'View résumé'}
              </button>
            ) : null}
          </div>
          {!scholar.has_headshot && !scholar.has_resume ? (
            <p className="hint" style={{ marginTop: 0 }}>
              No headshot or résumé on file yet.
            </p>
          ) : null}
        </div>
      </div>
    </>
  );
}
