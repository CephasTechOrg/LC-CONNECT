'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type AdminUser = {
  id: string;
  email: string;
  role: string;
  status: string;
  is_active: boolean;
  is_verified: boolean;
  display_name: string | null;
};

function initials(name: string | null, email: string): string {
  const source = (name || email.split('@')[0]).replace(/[._-]+/g, ' ').trim();
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

export default function UsersPage() {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [query, setQuery] = useState('');
  const [roleFilter, setRoleFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');
  const [verifyFilter, setVerifyFilter] = useState('all');
  const [flash, setFlash] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setError(null);
    setLoading(true);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<AdminUser[]>('/admin/users', token);
      setUsers(data);
    } catch (err) {
      setError(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function suspend(userId: string, label: string) {
    const reason = window.prompt(`Reason for suspending ${label}?`)?.trim();
    if (!reason) return;
    if (!window.confirm(`Suspend ${label}? They will be signed out and blocked from the app.`)) return;
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/users/${userId}/suspend`, token, {
        method: 'POST',
        body: JSON.stringify({ reason }),
      });
      setError(null);
      setFlash(`Suspended ${label}.`);
      await load();
    } catch (err) {
      setError(toUserMessage(err, 'Could not suspend this account. Please try again.'));
    }
  }

  async function reactivate(userId: string, label: string) {
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/users/${userId}/reactivate`, token, { method: 'POST' });
      setError(null);
      setFlash(`Reactivated ${label}.`);
      await load();
    } catch (err) {
      setError(toUserMessage(err, 'Could not reactivate this account. Please try again.'));
    }
  }

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return users.filter((u) => {
      if (roleFilter !== 'all' && u.role !== roleFilter) return false;
      if (statusFilter !== 'all' && u.status !== statusFilter) return false;
      if (verifyFilter === 'verified' && !u.is_verified) return false;
      if (verifyFilter === 'unverified' && u.is_verified) return false;
      if (!q) return true;
      return u.email.toLowerCase().includes(q) || (u.display_name || '').toLowerCase().includes(q);
    });
  }, [users, query, roleFilter, statusFilter, verifyFilter]);

  const roles = useMemo(() => Array.from(new Set(users.map((u) => u.role))).sort(), [users]);

  return (
    <>
      <header className="ops-top">
        <div>
          <h1>Users</h1>
          <p>Search every account on LC Connect and manage account access.</p>
        </div>
      </header>
      <div className="content" style={{ paddingTop: 8 }}>
        {error ? <div className="error-banner">{error}</div> : null}

        <div className="ops-toolbar">
          <div className="ops-search">
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search by name or email"
              aria-label="Search users"
            />
          </div>
          <select className="ops-select" value={roleFilter} onChange={(e) => setRoleFilter(e.target.value)} aria-label="Role">
            <option value="all">All roles</option>
            {roles.map((role) => (
              <option key={role} value={role}>{role}</option>
            ))}
          </select>
          <select className="ops-select" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} aria-label="Status">
            <option value="all">All statuses</option>
            <option value="active">Active</option>
            <option value="suspended">Suspended</option>
          </select>
          <select className="ops-select" value={verifyFilter} onChange={(e) => setVerifyFilter(e.target.value)} aria-label="Verification">
            <option value="all">All verification</option>
            <option value="verified">Verified</option>
            <option value="unverified">Unverified</option>
          </select>
          <span className="ops-count">
            {loading ? '…' : `${filtered.length.toLocaleString()} of ${users.length.toLocaleString()} users`}
          </span>
          <button className="ops-btn" type="button" disabled={loading} onClick={() => void load()}>
            Refresh
          </button>
        </div>

        <div className="ops-table-wrap table-scroll">
          {loading ? (
            <OpsLoading label="Loading users…" />
          ) : filtered.length === 0 ? (
            <OpsEmpty title="No users found">
              {users.length === 0
                ? 'No accounts have signed in yet.'
                : 'Try clearing filters or searching a different name or email.'}
            </OpsEmpty>
          ) : (
            <table className="ops-table">
              <thead>
                <tr>
                  <th>User</th>
                  <th>Email</th>
                  <th>Role</th>
                  <th>Verification</th>
                  <th>Account Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((u) => {
                  const label = u.display_name || u.email;
                  return (
                    <tr key={u.id}>
                      <td>
                        <div className="ops-user-cell">
                          <div className="ops-avatar">{initials(u.display_name, u.email)}</div>
                          <div className="ops-cell-title">{u.display_name || '—'}</div>
                        </div>
                      </td>
                      <td>{u.email}</td>
                      <td style={{ textTransform: 'capitalize' }}>{u.role}</td>
                      <td>
                        <span className={u.is_verified ? 'ops-chip success' : 'ops-chip muted'}>
                          {u.is_verified ? 'Verified' : 'Unverified'}
                        </span>
                      </td>
                      <td>
                        <span
                          className={
                            u.status === 'active'
                              ? 'ops-chip success'
                              : u.status === 'suspended'
                                ? 'ops-chip danger'
                                : 'ops-chip muted'
                          }
                        >
                          {u.status}
                        </span>
                      </td>
                      <td>
                        <div className="ops-row-actions">
                          {u.role === 'admin' ? (
                            <span className="ops-cell-sub" style={{ fontStyle: 'italic' }}>
                              Managed in Admins &amp; Roles
                            </span>
                          ) : u.status === 'active' ? (
                            <button
                              className="ops-btn danger"
                              type="button"
                              onClick={() => void suspend(u.id, label)}
                            >
                              Suspend
                            </button>
                          ) : u.status === 'suspended' ? (
                            <button
                              className="ops-btn"
                              type="button"
                              onClick={() => void reactivate(u.id, label)}
                            >
                              Reactivate
                            </button>
                          ) : null}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
        {flash && !error ? <p className="ops-flash">{flash}</p> : null}
      </div>
    </>
  );
}
