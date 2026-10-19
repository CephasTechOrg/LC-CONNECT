'use client';

import { useCallback, useEffect, useState } from 'react';
import {
  ScholarProfileReviewDrawer,
  type ScholarProfileReviewItem,
} from '@/components/scholar-profile-review-drawer';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

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

export default function ScholarProfilesPage() {
  const [tab, setTab] = useState<StatusTab>('pending_review');
  const [items, setItems] = useState<ScholarProfileReviewItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [status, setStatus] = useState('');
  const [flash, setFlash] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [drawer, setDrawer] = useState<ScholarProfileReviewItem | null>(null);
  const [note, setNote] = useState('');

  const load = useCallback(async (which: StatusTab) => {
    setLoading(true);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<ScholarProfileReviewItem[]>(
        `/admin/scholar-profiles?status=${which}`,
        token,
      );
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

  const reportDrawerError = useCallback((message: string) => {
    setError(true);
    setStatus(message);
  }, []);

  async function onApprove(item: ScholarProfileReviewItem) {
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

  async function onRequestChanges(item: ScholarProfileReviewItem) {
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

  async function onRevoke(item: ScholarProfileReviewItem) {
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
            Review professional profiles — photo, résumé, and story — before they appear to employer
            partners.
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
                : 'No profiles in this status.'}
            </OpsEmpty>
          ) : (
            <table className="ops-table ops-cards-sm">
              <thead>
                <tr>
                  <th>Scholar</th>
                  <th>Documents</th>
                  <th>Submitted</th>
                  <th>Status</th>
                  <th className="ops-col-actions" />
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
                          <div className="ops-user-cell-text">
                            <div className="ops-cell-title" title={label}>{label}</div>
                            <div className="ops-cell-sub" title={item.user_email}>{item.user_email}</div>
                          </div>
                        </div>
                      </td>
                      <td data-label="Documents">
                        <div className="ops-chip-stack">
                          <span className={item.has_headshot ? 'ops-chip success' : 'ops-chip muted'}>
                            Photo
                          </span>
                          <span className={item.has_resume ? 'ops-chip success' : 'ops-chip muted'}>
                            Résumé
                          </span>
                          <span
                            className={
                              item.employer_visibility_consent ? 'ops-chip success' : 'ops-chip muted'
                            }
                          >
                            Consent
                          </span>
                        </div>
                      </td>
                      <td data-label="Submitted" className="meta">{when(item.submitted_at)}</td>
                      <td data-label="Status">
                        <span className={statusChip(item.review_status)}>
                          {statusLabel(item.review_status)}
                        </span>
                      </td>
                      <td className="ops-col-actions ops-cell-actions">
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
        <ScholarProfileReviewDrawer
          item={drawer}
          tab={tab}
          note={note}
          busy={busy === drawer.id}
          onNoteChange={setNote}
          onClose={() => setDrawer(null)}
          onApprove={() => void onApprove(drawer)}
          onRequestChanges={() => void onRequestChanges(drawer)}
          onRevoke={() => void onRevoke(drawer)}
          onError={reportDrawerError}
        />
      ) : null}
    </>
  );
}
