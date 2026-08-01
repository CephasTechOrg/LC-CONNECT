'use client';

import { useCallback, useEffect, useState } from 'react';
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

// Which roles the current admin is allowed to grant — mirrors the backend's `can_invite` matrix.
// The backend is the source of truth (it 403s outside this), this only avoids offering an
// invite that would just bounce.
const INVITABLE_ROLES: Record<string, string[]> = {
  super_admin: ['super_admin', 'school_admin', 'honors_admin', 'content_admin', 'auditor'],
  school_admin: ['honors_admin', 'content_admin', 'auditor'],
};

export default function AdminsPage() {
  const [items, setItems] = useState<AdminMembership[]>([]);
  const [myScopes, setMyScopes] = useState<string[]>([]);
  const [status, setStatus] = useState('Loading…');
  const [error, setError] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);

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
      setStatus(roster.length ? `${roster.length} admin(s).` : 'No admins yet.');
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

  async function onInvite(e: React.FormEvent) {
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
      <header className="topbar">
        <div>
          <h1>Admins</h1>
          <p>Invite and manage scoped admin access</p>
        </div>
      </header>
      <div className="content">
        {invitableRoles.length > 0 && (
          <div className="panel">
            <h2>Invite an admin</h2>
            <form onSubmit={onInvite}>
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
                  <option value="" disabled>
                    Select a role…
                  </option>
                  {invitableRoles.map((role) => (
                    <option key={role} value={role}>
                      {ROLE_LABELS[role]}
                    </option>
                  ))}
                </select>
              </div>
              <button className="btn" type="submit" disabled={inviting}>
                {inviting ? 'Sending invite…' : 'Send invite'}
              </button>
            </form>
          </div>
        )}

        <div className="actions" style={{ justifyContent: 'space-between', alignItems: 'center' }}>
          <p className={`status${error ? ' error' : ''}`} style={{ margin: 0 }}>
            {status}
          </p>
          <button className="btn ghost" type="button" onClick={() => void load()} style={{ width: 'auto' }}>
            Refresh
          </button>
        </div>

        {items.length === 0 ? (
          <div className="panel empty">No admins yet.</div>
        ) : (
          <div className="card-list">
            {items.map((item) => {
              const label = item.display_name || item.user_email;
              const canRevoke = invitableRoles.includes(item.role);
              return (
                <article key={item.id} className="card">
                  <div className="card-head">
                    <div>
                      <h3>{label}</h3>
                      <p className="meta">{item.user_email}</p>
                    </div>
                    <span className="badge">{ROLE_LABELS[item.role] ?? item.role}</span>
                  </div>
                  {canRevoke && (
                    <div className="actions">
                      <button
                        className="btn ghost"
                        type="button"
                        disabled={busy === item.id}
                        onClick={() => void onResendInvite(item)}
                      >
                        Resend invite
                      </button>
                      <button
                        className="btn danger"
                        type="button"
                        disabled={busy === item.id}
                        onClick={() => void onRevoke(item)}
                      >
                        Revoke
                      </button>
                    </div>
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
