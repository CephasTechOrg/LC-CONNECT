'use client';

import { useSearchParams } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import { apiFetch, toUserMessage } from '@/lib/api/client';
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

function statusChip(tab: StatusTab): string {
  if (tab === 'approved') return 'ops-chip success';
  if (tab === 'rejected') return 'ops-chip danger';
  return 'ops-chip warn';
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
  const [orgLoading, setOrgLoading] = useState(true);
  const [oppLoading, setOppLoading] = useState(true);
  const [error, setError] = useState(false);
  const [status, setStatus] = useState('');
  const [flash, setFlash] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [orgDrawer, setOrgDrawer] = useState<EmployerOrganization | null>(null);
  const [oppDrawer, setOppDrawer] = useState<OpportunitySubmission | null>(null);
  const [note, setNote] = useState('');

  const loadOrgs = useCallback(async (which: StatusTab) => {
    setOrgLoading(true);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<EmployerOrganization[]>(`/admin/employers?status=${which}`, token);
      setOrgs(data);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    } finally {
      setOrgLoading(false);
    }
  }, []);

  const loadOpps = useCallback(async (which: StatusTab) => {
    setOppLoading(true);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<OpportunitySubmission[]>(`/admin/employers/opportunities?status=${which}`, token);
      setOpps(data);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    } finally {
      setOppLoading(false);
    }
  }, []);

  useEffect(() => {
    setOrgDrawer(null);
    setOppDrawer(null);
    setNote('');
    if (mainTab === 'organizations') void loadOrgs(orgTab);
    else void loadOpps(oppTab);
  }, [mainTab, orgTab, oppTab, loadOrgs, loadOpps]);

  const statusTab = mainTab === 'organizations' ? orgTab : oppTab;
  const setStatusTab = mainTab === 'organizations' ? setOrgTab : setOppTab;

  async function actOrg(action: 'approve' | 'reject', item: EmployerOrganization) {
    setBusy(item.id);
    try {
      const token = await getAccessToken();
      if (!token) return;
      const body = action === 'reject' ? JSON.stringify({ reason: note.trim() || null }) : undefined;
      await apiFetch(`/admin/employers/${item.id}/${action}`, token, { method: 'POST', body });
      setError(false);
      setFlash(`${action[0].toUpperCase() + action.slice(1)}d ${item.name}.`);
      setOrgDrawer(null);
      setNote('');
      await loadOrgs(orgTab);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, `Could not ${action} this item. Please try again.`));
    } finally {
      setBusy(null);
    }
  }

  async function onResendOrgInvite(item: EmployerOrganization) {
    setBusy(item.id);
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/employers/${item.id}/resend-invite`, token, { method: 'POST' });
      setError(false);
      setFlash(`Resent invite to ${item.name}.`);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not resend the invitation. Please try again.'));
    } finally {
      setBusy(null);
    }
  }

  async function actOpp(action: 'approve' | 'reject', item: OpportunitySubmission) {
    if (action === 'reject' && !note.trim()) {
      setError(true);
      setStatus('A reason is required to reject a submission.');
      return;
    }
    setBusy(item.id);
    try {
      const token = await getAccessToken();
      if (!token) return;
      const body = action === 'reject' ? JSON.stringify({ reason: note.trim() }) : undefined;
      await apiFetch(`/admin/employers/opportunities/${item.id}/${action}`, token, { method: 'POST', body });
      setError(false);
      setFlash(`${action[0].toUpperCase() + action.slice(1)}d ${item.title}.`);
      setOppDrawer(null);
      setNote('');
      await loadOpps(oppTab);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, `Could not ${action} this item. Please try again.`));
    } finally {
      setBusy(null);
    }
  }

  const tableLoading = mainTab === 'organizations' ? orgLoading : oppLoading;

  return (
    <>
      <header className="ops-top">
        <div>
          <h1>Employer Partners</h1>
          <p>Review employer organizations and their opportunity submissions — Blueprint Bond.</p>
        </div>
        <div className="seg-tabs">
          <button
            type="button"
            className={`seg-tab${mainTab === 'organizations' ? ' active' : ''}`}
            onClick={() => setMainTab('organizations')}
          >
            Organizations
          </button>
          <button
            type="button"
            className={`seg-tab${mainTab === 'opportunities' ? ' active' : ''}`}
            onClick={() => setMainTab('opportunities')}
          >
            Opportunities
          </button>
        </div>
      </header>

      <div className="content" style={{ paddingTop: 8 }}>
        {error ? <div className="error-banner">{status}</div> : null}

        <div className="ops-toolbar">
          <div className="seg-tabs">
            {(['pending', 'approved', 'rejected'] as StatusTab[]).map((t) => (
              <button
                key={t}
                type="button"
                className={`seg-tab${statusTab === t ? ' active' : ''}`}
                onClick={() => setStatusTab(t)}
              >
                {t[0].toUpperCase() + t.slice(1)}
              </button>
            ))}
          </div>
          <span className="ops-count">
            {mainTab === 'organizations' ? `${orgs.length} organizations` : `${opps.length} submissions`}
          </span>
          <button
            className="ops-btn"
            type="button"
            disabled={tableLoading}
            onClick={() => (mainTab === 'organizations' ? void loadOrgs(orgTab) : void loadOpps(oppTab))}
          >
            Refresh
          </button>
        </div>

        {flash ? <p className="ops-flash">{flash}</p> : null}

        {mainTab === 'organizations' ? (
          <div className="ops-table-wrap table-scroll">
            {orgLoading ? (
              <OpsLoading label="Loading organizations…" />
            ) : orgs.length === 0 ? (
              <OpsEmpty title={`No ${orgTab} organizations`}>
                {`No ${orgTab} employer organizations.`}
              </OpsEmpty>
            ) : (
              <table className="ops-table">
                <thead>
                  <tr>
                    <th>Organization</th>
                    <th>Contact</th>
                    <th>Email</th>
                    <th>Status</th>
                    <th>Review Note</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {orgs.map((item) => (
                    <tr key={item.id}>
                      <td><div className="ops-cell-title">{item.name}</div></td>
                      <td>{item.contact_name || '—'}</td>
                      <td>{item.contact_email}</td>
                      <td><span className={statusChip(orgTab)}>{item.status}</span></td>
                      <td>
                        {item.review_note ? (
                          <span className="ops-cell-sub">{item.review_note}</span>
                        ) : (
                          <span className="ops-cell-sub">—</span>
                        )}
                      </td>
                      <td>
                        <div className="ops-row-actions">
                          {orgTab === 'pending' ? (
                            <button
                              className="ops-btn primary"
                              type="button"
                              onClick={() => {
                                setOrgDrawer(item);
                                setNote('');
                              }}
                            >
                              Review
                            </button>
                          ) : null}
                          {orgTab === 'approved' ? (
                            <button
                              className="ops-btn"
                              type="button"
                              disabled={busy === item.id}
                              onClick={() => void onResendOrgInvite(item)}
                            >
                              Resend invite
                            </button>
                          ) : null}
                          {orgTab === 'rejected' ? (
                            <span className="ops-cell-sub">Read-only</span>
                          ) : null}
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        ) : (
          <div className="ops-table-wrap table-scroll">
            {oppLoading ? (
              <OpsLoading label="Loading opportunities…" />
            ) : opps.length === 0 ? (
              <OpsEmpty title={`No ${oppTab} submissions`}>
                {`No ${oppTab} opportunity submissions.`}
              </OpsEmpty>
            ) : (
              <table className="ops-table">
                <thead>
                  <tr>
                    <th>Opportunity</th>
                    <th>Organization</th>
                    <th>Category</th>
                    <th>Link</th>
                    <th>Status</th>
                    <th>Review</th>
                  </tr>
                </thead>
                <tbody>
                  {opps.map((item) => (
                    <tr key={item.id}>
                      <td>
                        <div className="ops-cell-title">{item.title}</div>
                        <div className="ops-cell-sub">{item.description.slice(0, 90)}</div>
                      </td>
                      <td>{item.organization_name}</td>
                      <td style={{ textTransform: 'capitalize' }}>{item.category}</td>
                      <td>
                        {item.external_url ? (
                          <a href={item.external_url} target="_blank" rel="noopener noreferrer">
                            Link
                          </a>
                        ) : (
                          <span className="ops-cell-sub">—</span>
                        )}
                      </td>
                      <td><span className={statusChip(oppTab)}>{item.status}</span></td>
                      <td>
                        <div className="ops-row-actions">
                          {oppTab === 'pending' ? (
                            <button
                              className="ops-btn primary"
                              type="button"
                              onClick={() => {
                                setOppDrawer(item);
                                setNote('');
                              }}
                            >
                              Review
                            </button>
                          ) : (
                            <span className="ops-cell-sub">
                              {item.review_note ? `Note: ${item.review_note}` : 'Read-only'}
                            </span>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        )}
      </div>

      {orgDrawer ? (
        <>
          <div className="ops-drawer-backdrop" onClick={() => setOrgDrawer(null)} aria-hidden />
          <aside className="ops-drawer" role="dialog" aria-label="Review employer organization">
            <div className="ops-drawer-head">
              <div>
                <h2>{orgDrawer.name}</h2>
                <div className="ops-drawer-meta"><span className="ops-chip warn">Pending review</span></div>
              </div>
              <button className="ops-drawer-close" type="button" aria-label="Close" onClick={() => setOrgDrawer(null)}>✕</button>
            </div>
            <div className="ops-drawer-grid">
              <div className="ops-drawer-field">
                <label>Contact name</label>
                <div>{orgDrawer.contact_name || '—'}</div>
              </div>
              <div className="ops-drawer-field">
                <label>Contact email</label>
                <div>{orgDrawer.contact_email}</div>
              </div>
            </div>
            <div className="field">
              <label htmlFor="org-note">Review note</label>
              <textarea
                id="org-note"
                rows={3}
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="Optional note sent if rejected"
              />
            </div>
            <div className="ops-drawer-footer">
              <button className="btn danger" type="button" disabled={busy === orgDrawer.id} onClick={() => void actOrg('reject', orgDrawer)}>
                Reject
              </button>
              <button className="btn" type="button" disabled={busy === orgDrawer.id} onClick={() => void actOrg('approve', orgDrawer)}>
                Approve
              </button>
            </div>
          </aside>
        </>
      ) : null}

      {oppDrawer ? (
        <>
          <div className="ops-drawer-backdrop" onClick={() => setOppDrawer(null)} aria-hidden />
          <aside className="ops-drawer" role="dialog" aria-label="Review opportunity submission">
            <div className="ops-drawer-head">
              <div>
                <h2>{oppDrawer.title}</h2>
                <div className="ops-drawer-meta">
                  <span className="ops-chip warn">Pending review</span>
                </div>
              </div>
              <button className="ops-drawer-close" type="button" aria-label="Close" onClick={() => setOppDrawer(null)}>✕</button>
            </div>
            <div className="ops-drawer-grid">
              <div className="ops-drawer-field">
                <label>Organization</label>
                <div>{oppDrawer.organization_name}</div>
              </div>
              <div className="ops-drawer-field">
                <label>Category</label>
                <div style={{ textTransform: 'capitalize' }}>{oppDrawer.category}</div>
              </div>
            </div>
            <div className="field">
              <label>Description</label>
              <p className="meta" style={{ margin: 0 }}>{oppDrawer.description}</p>
            </div>
            {oppDrawer.external_url ? (
              <div className="field">
                <label>External link</label>
                <a href={oppDrawer.external_url} target="_blank" rel="noopener noreferrer">
                  {oppDrawer.external_url}
                </a>
              </div>
            ) : null}
            <div className="field">
              <label htmlFor="opp-note">Reject reason (required to reject)</label>
              <textarea
                id="opp-note"
                rows={3}
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="Required if rejecting"
              />
            </div>
            <div className="ops-drawer-footer">
              <button
                className="btn danger"
                type="button"
                disabled={busy === oppDrawer.id || !note.trim()}
                onClick={() => void actOpp('reject', oppDrawer)}
              >
                Reject
              </button>
              <button
                className="btn"
                type="button"
                disabled={busy === oppDrawer.id}
                onClick={() => void actOpp('approve', oppDrawer)}
              >
                Approve &amp; Publish
              </button>
            </div>
          </aside>
        </>
      ) : null}
    </>
  );
}
