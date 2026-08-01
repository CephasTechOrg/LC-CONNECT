'use client';

import { useSearchParams } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type EmployerOrganization = {
  id: string;
  name: string;
  status: string;
  contact_email: string;
  contact_name: string | null;
  review_note: string | null;
};

type OpportunitySubmission = {
  id: string;
  title: string;
  description: string;
  category: string;
  external_url: string | null;
  status: string;
  review_note: string | null;
  organization_id: string;
  organization_name: string;
};

type MainTab = 'organizations' | 'opportunities';
type StatusTab = 'pending' | 'approved' | 'rejected';

function badgeClass(tab: StatusTab): string {
  if (tab === 'approved') return 'badge success';
  if (tab === 'rejected') return 'badge danger';
  return 'badge';
}

export default function EmployersPage() {
  const searchParams = useSearchParams();
  const [mainTab, setMainTab] = useState<MainTab>(
    searchParams.get('tab') === 'opportunities' ? 'opportunities' : 'organizations',
  );
  const [orgTab, setOrgTab] = useState<StatusTab>('pending');
  const [oppTab, setOppTab] = useState<StatusTab>('pending');

  const [orgs, setOrgs] = useState<EmployerOrganization[]>([]);
  const [opps, setOpps] = useState<OpportunitySubmission[]>([]);
  const [status, setStatus] = useState('Loading…');
  const [error, setError] = useState(false);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);

  const loadOrgs = useCallback(async (which: StatusTab) => {
    setError(false);
    setStatus('Loading…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<EmployerOrganization[]>(`/admin/employers?status=${which}`, token);
      setOrgs(data);
      setStatus(data.length ? `${data.length} ${which} organization(s).` : `No ${which} organizations.`);
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Failed to load');
    }
  }, []);

  const loadOpps = useCallback(async (which: StatusTab) => {
    setError(false);
    setStatus('Loading…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<OpportunitySubmission[]>(`/admin/employers/opportunities?status=${which}`, token);
      setOpps(data);
      setStatus(data.length ? `${data.length} ${which} submission(s).` : `No ${which} submissions.`);
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Failed to load');
    }
  }, []);

  useEffect(() => {
    if (mainTab === 'organizations') void loadOrgs(orgTab);
    else void loadOpps(oppTab);
  }, [mainTab, orgTab, oppTab, loadOrgs, loadOpps]);

  async function actOrg(id: string, action: 'approve' | 'reject', label: string) {
    setBusy(id);
    try {
      const token = await getAccessToken();
      if (!token) return;
      const body = action === 'reject' ? JSON.stringify({ reason: notes[id]?.trim() || null }) : undefined;
      await apiFetch(`/admin/employers/${id}/${action}`, token, { method: 'POST', body });
      setError(false);
      setStatus(`${action[0].toUpperCase() + action.slice(1)}d ${label}.`);
      await loadOrgs(orgTab);
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : `${action} failed`);
    } finally {
      setBusy(null);
    }
  }

  async function onResendOrgInvite(id: string, label: string) {
    setBusy(id);
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/employers/${id}/resend-invite`, token, { method: 'POST' });
      setError(false);
      setStatus(`Resent invite to ${label}.`);
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Resend failed');
    } finally {
      setBusy(null);
    }
  }

  async function actOpp(id: string, action: 'approve' | 'reject', label: string) {
    if (action === 'reject' && !notes[id]?.trim()) {
      setError(true);
      setStatus('A reason is required to reject a submission.');
      return;
    }
    setBusy(id);
    try {
      const token = await getAccessToken();
      if (!token) return;
      const body = action === 'reject' ? JSON.stringify({ reason: notes[id]?.trim() }) : undefined;
      await apiFetch(`/admin/employers/opportunities/${id}/${action}`, token, { method: 'POST', body });
      setError(false);
      setStatus(`${action[0].toUpperCase() + action.slice(1)}d ${label}.`);
      await loadOpps(oppTab);
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : `${action} failed`);
    } finally {
      setBusy(null);
    }
  }

  const statusTab = mainTab === 'organizations' ? orgTab : oppTab;
  const setStatusTab = mainTab === 'organizations' ? setOrgTab : setOppTab;

  return (
    <>
      <header className="topbar">
        <div>
          <h1>Employer Partners</h1>
          <p>Review employer organizations and their opportunity submissions — Blueprint Bond</p>
        </div>
      </header>
      <div className="content">
        <div className="tabs" style={{ marginBottom: 16 }}>
          <button
            type="button"
            className={`tab${mainTab === 'organizations' ? ' active' : ''}`}
            onClick={() => setMainTab('organizations')}
          >
            Organizations
          </button>
          <button
            type="button"
            className={`tab${mainTab === 'opportunities' ? ' active' : ''}`}
            onClick={() => setMainTab('opportunities')}
          >
            Opportunities
          </button>
        </div>

        <div className="actions" style={{ justifyContent: 'space-between', alignItems: 'center', marginTop: 0 }}>
          <div className="tabs">
            {(['pending', 'approved', 'rejected'] as StatusTab[]).map((t) => (
              <button
                key={t}
                type="button"
                className={`tab${statusTab === t ? ' active' : ''}`}
                onClick={() => setStatusTab(t)}
              >
                {t[0].toUpperCase() + t.slice(1)}
              </button>
            ))}
          </div>
          <button
            className="btn ghost"
            type="button"
            onClick={() => (mainTab === 'organizations' ? void loadOrgs(orgTab) : void loadOpps(oppTab))}
            style={{ width: 'auto' }}
          >
            Refresh
          </button>
        </div>

        <p className={`status${error ? ' error' : ''}`}>{status}</p>

        {mainTab === 'organizations' ? (
          orgs.length === 0 ? (
            <div className="panel empty">{`No ${orgTab} organizations.`}</div>
          ) : (
            <div className="card-list">
              {orgs.map((item) => {
                const label = item.name;
                return (
                  <article key={item.id} className="card">
                    <div className="card-head">
                      <div>
                        <h3>{label}</h3>
                        <p className="meta">
                          {item.contact_name ? `${item.contact_name} · ` : ''}
                          {item.contact_email}
                        </p>
                        {item.review_note && <p className="meta">Note: {item.review_note}</p>}
                      </div>
                      <span className={badgeClass(orgTab)}>{item.status}</span>
                    </div>

                    {orgTab === 'pending' && (
                      <>
                        <div className="field" style={{ marginTop: 12, marginBottom: 0 }}>
                          <label htmlFor={`org-note-${item.id}`}>Note (sent on reject)</label>
                          <textarea
                            id={`org-note-${item.id}`}
                            rows={2}
                            value={notes[item.id] || ''}
                            onChange={(e) => setNotes((prev) => ({ ...prev, [item.id]: e.target.value }))}
                            placeholder="Optional"
                          />
                        </div>
                        <div className="actions">
                          <button
                            className="btn"
                            type="button"
                            disabled={busy === item.id}
                            onClick={() => void actOrg(item.id, 'approve', label)}
                          >
                            Approve
                          </button>
                          <button
                            className="btn danger"
                            type="button"
                            disabled={busy === item.id}
                            onClick={() => void actOrg(item.id, 'reject', label)}
                          >
                            Reject
                          </button>
                        </div>
                      </>
                    )}

                    {orgTab === 'approved' && (
                      <div className="actions">
                        <button
                          className="btn ghost"
                          type="button"
                          disabled={busy === item.id}
                          onClick={() => void onResendOrgInvite(item.id, label)}
                        >
                          Resend invite
                        </button>
                      </div>
                    )}
                  </article>
                );
              })}
            </div>
          )
        ) : opps.length === 0 ? (
          <div className="panel empty">{`No ${oppTab} submissions.`}</div>
        ) : (
          <div className="card-list">
            {opps.map((item) => {
              const label = item.title;
              return (
                <article key={item.id} className="card">
                  <div className="card-head">
                    <div>
                      <h3>{label}</h3>
                      <p className="meta">
                        {item.organization_name} · {item.category}
                        {item.external_url ? (
                          <>
                            {' · '}
                            <a href={item.external_url} target="_blank" rel="noopener noreferrer">
                              link
                            </a>
                          </>
                        ) : null}
                      </p>
                      <p className="meta">{item.description}</p>
                      {item.review_note && <p className="meta">Note: {item.review_note}</p>}
                    </div>
                    <span className={badgeClass(oppTab)}>{item.status}</span>
                  </div>

                  {oppTab === 'pending' && (
                    <>
                      <div className="field" style={{ marginTop: 12, marginBottom: 0 }}>
                        <label htmlFor={`opp-note-${item.id}`}>Reason (required to reject)</label>
                        <textarea
                          id={`opp-note-${item.id}`}
                          rows={2}
                          value={notes[item.id] || ''}
                          onChange={(e) => setNotes((prev) => ({ ...prev, [item.id]: e.target.value }))}
                          placeholder="Required only if rejecting"
                        />
                      </div>
                      <div className="actions">
                        <button
                          className="btn"
                          type="button"
                          disabled={busy === item.id}
                          onClick={() => void actOpp(item.id, 'approve', label)}
                        >
                          Approve &amp; Publish
                        </button>
                        <button
                          className="btn danger"
                          type="button"
                          disabled={busy === item.id}
                          onClick={() => void actOpp(item.id, 'reject', label)}
                        >
                          Reject
                        </button>
                      </div>
                    </>
                  )}
                </article>
              );
            })}
          </div>
        )}
      </div>
    </>
  );
}
