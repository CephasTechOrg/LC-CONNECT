'use client';

import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type AdminMembership = {
  id: string;
  user_id: string;
  role: string;
  status: string;
  invited_at: string;
  revoked_at: string | null;
  user_email: string;
  display_name: string | null;
};

const ROLE_LABELS: Record<string, string> = {
  super_admin: 'Super Admin',
  school_admin: 'School Admin',
  honors_admin: 'Honors Admin',
  content_admin: 'Content Admin',
  auditor: 'Auditor',
};

const ROLE_REFERENCE: { role: string; blurb: string }[] = [
  { role: 'super_admin', blurb: 'Full platform access, including inviting any admin role.' },
  { role: 'school_admin', blurb: 'Campus operations plus inviting honors, content, and auditor roles.' },
  { role: 'honors_admin', blurb: 'Presidential Scholars and Employer Partners workflows.' },
  { role: 'content_admin', blurb: 'Campus Hub posts and resources publishing.' },
  { role: 'auditor', blurb: 'Read-oriented access for review and oversight.' },
];

const INVITABLE_ROLES: Record<string, string[]> = {
  super_admin: ['super_admin', 'school_admin', 'honors_admin', 'content_admin', 'auditor'],
  school_admin: ['honors_admin', 'content_admin', 'auditor'],
};

function initials(name: string | null, email: string): string {
  const source = (name || email.split('@')[0]).replace(/[._-]+/g, ' ').trim();
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

function when(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString();
}

export default function AdminsPage() {
  const [items, setItems] = useState<AdminMembership[]>([]);
  const [myScopes, setMyScopes] = useState<string[]>([]);
  const [status, setStatus] = useState('Loading…');
  const [error, setError] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [showInvite, setShowInvite] = useState(false);
  const [inviteEmail, setInviteEmail] = useState('');
  const [inviteRole, setInviteRole] = useState('');
  const [inviting, setInviting] = useState(false);

  const load = useCallback(async () => {
    setError(false);
    setStatus('Loading…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const [roster, scopes] = await Promise.all([
        apiFetch<AdminMembership[]>('/admin/admins', token),
        apiFetch<{ scopes: string[] }>('/admin/admins/me/scopes', token),
      ]);
      setItems(roster);
      setMyScopes(scopes.scopes);
      setStatus(roster.length ? `${roster.length} admin(s)` : 'No admins yet.');
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const invitableRoles = myScopes.includes('super_admin')
    ? INVITABLE_ROLES.super_admin
    : myScopes.includes('school_admin')
      ? INVITABLE_ROLES.school_admin
      : [];

  const activeCount = useMemo(() => items.filter((i) => i.status === 'active').length, [items]);

  async function onInvite(e: FormEvent) {
    e.preventDefault();
    if (!inviteEmail.trim() || !inviteRole) return;
    setInviting(true);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      await apiFetch('/admin/admins/invite', token, {
        method: 'POST',
        body: JSON.stringify({ email: inviteEmail.trim().toLowerCase(), role: inviteRole }),
      });
      setStatus(`Invited ${inviteEmail.trim()}.`);
      setInviteEmail('');
      setInviteRole('');
      setShowInvite(false);
      await load();
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not send the invitation. Please try again.'));
    } finally {
      setInviting(false);
    }
  }

  async function onRevoke(item: AdminMembership) {
    const label = item.display_name || item.user_email;
    if (!window.confirm(`Revoke ${label}'s ${ROLE_LABELS[item.role] ?? item.role} access?`)) return;
    setBusy(item.id);
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/admins/${item.id}/revoke`, token, { method: 'POST' });
      setError(false);
      setStatus(`Revoked ${label}.`);
      await load();
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not revoke access. Please try again.'));
    } finally {
      setBusy(null);
    }
  }

  async function onResendInvite(item: AdminMembership) {
    const label = item.display_name || item.user_email;
    setBusy(item.id);
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/admins/${item.id}/resend-invite`, token, { method: 'POST' });
      setError(false);
      setStatus(`Resent invite to ${label}.`);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not resend the invitation. Please try again.'));
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <header className="ops-top">
        <div>
          <h1>Admins &amp; Roles</h1>
          <p>Invite administrators and manage scoped access.</p>
        </div>
        {invitableRoles.length > 0 ? (
          <button
            className="ops-btn primary"
            type="button"
            onClick={() => setShowInvite((v) => !v)}
          >
            {showInvite ? 'Close invite' : 'Invite administrator'}
          </button>
        ) : null}
      </header>

      <div className="content" style={{ paddingTop: 8 }}>
        {error ? <div className="error-banner">{status}</div> : null}

        <div className="dash-kpi-grid" style={{ gridTemplateColumns: 'repeat(2, minmax(0, 1fr))', marginBottom: 18 }}>
          <div className="dash-kpi">
            <div className="dash-kpi-icon tone-purple-soft">
              <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="#6F42E8" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                <circle cx="10" cy="8" r="3" />
                <path d="M4 19.5c.5-3 2.9-4.8 6-4.8" />
              </svg>
            </div>
            <div>
              <div className="dash-kpi-value">{items.length}</div>
              <div className="dash-kpi-title">Total administrators</div>
              <div className="dash-kpi-sub">All seats on roster</div>
            </div>
          </div>
          <div className="dash-kpi">
            <div className="dash-kpi-icon tone-green">
              <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="#2DAA72" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                <path d="M20 6 9 17l-5-5" />
              </svg>
            </div>
            <div>
              <div className="dash-kpi-value">{activeCount}</div>
              <div className="dash-kpi-title">Active memberships</div>
              <div className="dash-kpi-sub">Currently granted access</div>
            </div>
          </div>
        </div>

        {showInvite && invitableRoles.length > 0 ? (
          <form className="ops-form" onSubmit={onInvite}>
            <h2>Invite an administrator</h2>
            <div className="grid-2">
              <div className="field">
                <label htmlFor="invite-email">Email</label>
                <input
                  id="invite-email"
                  type="email"
                  value={inviteEmail}
                  onChange={(e) => setInviteEmail(e.target.value)}
                  placeholder="name@livingstone.edu"
                  required
                />
              </div>
              <div className="field">
                <label htmlFor="invite-role">Role</label>
                <select id="invite-role" value={inviteRole} onChange={(e) => setInviteRole(e.target.value)} required>
                  <option value="" disabled>Select a role…</option>
                  {invitableRoles.map((role) => (
                    <option key={role} value={role}>{ROLE_LABELS[role]}</option>
                  ))}
                </select>
              </div>
            </div>
            <div className="actions">
              <button className="btn" type="submit" disabled={inviting} style={{ width: 'auto' }}>
                {inviting ? 'Sending invite…' : 'Send invite'}
              </button>
              <button className="btn ghost" type="button" onClick={() => setShowInvite(false)} style={{ width: 'auto' }}>
                Cancel
              </button>
            </div>
          </form>
        ) : null}

        <div className="ops-toolbar" style={{ marginTop: 0 }}>
          <span className="ops-count" style={{ marginLeft: 0 }}>Admin roster</span>
          <button className="ops-btn" type="button" onClick={() => void load()}>Refresh</button>
        </div>
        <div className="ops-table-wrap table-scroll">
          {items.length === 0 ? (
            <div className="ops-empty">No admins yet.</div>
          ) : (
            <table className="ops-table">
              <thead>
                <tr>
                  <th>Administrator</th>
                  <th>Email</th>
                  <th>Role</th>
                  <th>Status</th>
                  <th>Invited</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {items.map((item) => {
                  const label = item.display_name || item.user_email;
                  const canManage = invitableRoles.includes(item.role) && item.status !== 'revoked';
                  const statusClass =
                    item.status === 'active'
                      ? 'ops-chip success'
                      : item.status === 'invited'
                        ? 'ops-chip warn'
                        : 'ops-chip muted';
                  return (
                    <tr key={item.id}>
                      <td>
                        <div className="ops-user-cell">
                          <div className="ops-avatar">{initials(item.display_name, item.user_email)}</div>
                          <div className="ops-cell-title">{label}</div>
                        </div>
                      </td>
                      <td>{item.user_email}</td>
                      <td><span className="ops-chip">{ROLE_LABELS[item.role] ?? item.role}</span></td>
                      <td><span className={statusClass}>{item.status}</span></td>
                      <td>{when(item.invited_at)}</td>
                      <td>
                        {canManage ? (
                          <div className="ops-row-actions">
                            {item.status === 'invited' ? (
                              <button
                                className="ops-btn"
                                type="button"
                                disabled={busy === item.id}
                                onClick={() => void onResendInvite(item)}
                              >
                                Resend
                              </button>
                            ) : null}
                            <button
                              className="ops-btn danger"
                              type="button"
                              disabled={busy === item.id}
                              onClick={() => void onRevoke(item)}
                            >
                              Revoke
                            </button>
                          </div>
                        ) : (
                          <span className="ops-cell-sub">
                            {item.status === 'revoked' ? 'Read-only' : '—'}
                          </span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>

        <section className="dash-panel" style={{ marginTop: 18 }}>
          <div className="dash-panel-title" style={{ marginBottom: 14 }}>Role reference</div>
          <div
            className="dash-actions"
            style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 14 }}
          >
            {ROLE_REFERENCE.map((entry) => (
              <div key={entry.role} style={{ cursor: 'default' }}>
                <span className="ops-chip">{ROLE_LABELS[entry.role]}</span>
                <div className="dash-action-desc" style={{ marginTop: 8 }}>{entry.blurb}</div>
              </div>
            ))}
          </div>
        </section>

        {!error ? <p className="status" style={{ marginTop: 12 }}>{status}</p> : null}
      </div>
    </>
  );
}
