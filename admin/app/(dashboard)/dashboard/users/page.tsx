'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
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

export default function UsersPage() {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('Loading…');
  const [error, setError] = useState(false);

  const load = useCallback(async () => {
    setError(false);
    setStatus('Loading…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<AdminUser[]>('/admin/users', token);
      setUsers(data);
      setStatus(`${data.length} user(s).`);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function suspend(userId: string, label: string) {
    const ok = window.confirm(`Suspend ${label}? They will be signed out and blocked from the app.`);
    if (!ok) return;
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/users/${userId}/suspend`, token, {
        method: 'POST',
        body: JSON.stringify({ reason: null }),
      });
      setError(false);
      setStatus(`Suspended ${label}.`);
      await load();
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not suspend this account. Please try again.'));
    }
  }

  async function reactivate(userId: string, label: string) {
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/users/${userId}/reactivate`, token, { method: 'POST' });
      setError(false);
      setStatus(`Reactivated ${label}.`);
      await load();
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not reactivate this account. Please try again.'));
    }
  }

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return users;
    return users.filter((u) => u.email.toLowerCase().includes(q) || (u.display_name || '').toLowerCase().includes(q));
  }, [users, query]);

  return (
    <>
      <header className="topbar">
        <div>
          <h1>Users</h1>
          <p>Search every account on LC Connect and act on abusive ones</p>
        </div>
      </header>
      <div className="content">
        <div className="actions" style={{ justifyContent: 'space-between', alignItems: 'center', marginTop: 0 }}>
          <p className={`status${error ? ' error' : ''}`} style={{ margin: 0 }}>
            {status}
          </p>
          <button className="btn ghost" type="button" onClick={() => void load()} style={{ width: 'auto' }}>
            Refresh
          </button>
        </div>

        <div className="field" style={{ maxWidth: 360 }}>
          <label htmlFor="user-search">Search users</label>
          <input
            id="user-search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Name or email"
          />
        </div>

        <div className="panel table-scroll">
          <table className="rows">
            <thead>
              <tr>
                <th>Name</th>
                <th>Email</th>
                <th>Role</th>
                <th>Status</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {filtered.map((u) => (
                <tr key={u.id}>
                  <td>{u.display_name || '—'}</td>
                  <td>{u.email}</td>
                  <td style={{ textTransform: 'capitalize' }}>{u.role}</td>
                  <td>
                    <span
                      className={
                        u.status === 'active' ? 'badge success' : u.status === 'suspended' ? 'badge danger' : 'badge muted'
                      }
                    >
                      {u.status}
                    </span>
                  </td>
                  <td style={{ textAlign: 'right' }}>
                    {u.status === 'active' && u.role !== 'admin' ? (
                      <button
                        className="btn danger"
                        type="button"
                        style={{ width: 'auto', minHeight: 34, padding: '6px 12px', fontSize: 13 }}
                        onClick={() => void suspend(u.id, u.display_name || u.email)}
                      >
                        Suspend
                      </button>
                    ) : u.status === 'suspended' ? (
                      <button
                        className="btn ghost"
                        type="button"
                        style={{ width: 'auto', minHeight: 34, padding: '6px 12px', fontSize: 13 }}
                        onClick={() => void reactivate(u.id, u.display_name || u.email)}
                      >
                        Reactivate
                      </button>
                    ) : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
}
