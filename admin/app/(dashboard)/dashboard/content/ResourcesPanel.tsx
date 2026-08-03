'use client';

import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';

type Resource = {
  id: string;
  category: string;
  title: string;
  description: string;
  location: string | null;
  hours: string | null;
  contact_email: string | null;
  phone: string | null;
  is_active: boolean;
  sort_order: number;
};

const CATEGORIES = [
  'housing',
  'advising',
  'financial_aid',
  'registrar',
  'safety',
  'it',
  'academic_support',
  'other',
];

function labelCat(c: string): string {
  return c.replaceAll('_', ' ');
}

export default function ResourcesPanel() {
  const [items, setItems] = useState<Resource[]>([]);
  const [status, setStatus] = useState('Loading resources…');
  const [error, setError] = useState(false);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [category, setCategory] = useState('advising');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [location, setLocation] = useState('');
  const [hours, setHours] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [phone, setPhone] = useState('');
  const [saving, setSaving] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [q, setQ] = useState('');
  const [filterCat, setFilterCat] = useState('all');
  const [filterActive, setFilterActive] = useState<'all' | 'active' | 'inactive'>('all');

  function resetForm() {
    setEditingId(null);
    setCategory('advising');
    setTitle('');
    setDescription('');
    setLocation('');
    setHours('');
    setContactEmail('');
    setPhone('');
    setShowForm(false);
  }

  function startEdit(item: Resource) {
    setEditingId(item.id);
    setCategory(item.category);
    setTitle(item.title);
    setDescription(item.description);
    setLocation(item.location ?? '');
    setHours(item.hours ?? '');
    setContactEmail(item.contact_email ?? '');
    setPhone(item.phone ?? '');
    setShowForm(true);
  }

  const load = useCallback(async () => {
    setError(false);
    setStatus('Loading resources…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<Resource[]>('/admin/campus-resources', token);
      setItems(data);
      setStatus(`${data.filter((r) => r.is_active).length} active resources`);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return items.filter((item) => {
      if (filterCat !== 'all' && item.category !== filterCat) return false;
      if (filterActive === 'active' && !item.is_active) return false;
      if (filterActive === 'inactive' && item.is_active) return false;
      if (!needle) return true;
      return (
        item.title.toLowerCase().includes(needle) ||
        item.description.toLowerCase().includes(needle) ||
        (item.location || '').toLowerCase().includes(needle)
      );
    });
  }, [items, q, filterCat, filterActive]);

  async function submitForm(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const fields = {
        category,
        title: title.trim(),
        description: description.trim(),
        location: location.trim() || null,
        hours: hours.trim() || null,
        contact_email: contactEmail.trim() || null,
        phone: phone.trim() || null,
      };
      if (editingId) {
        await apiFetch(`/admin/campus-resources/${editingId}`, token, {
          method: 'PATCH',
          body: JSON.stringify(fields),
        });
        setStatus('Changes saved.');
      } else {
        await apiFetch('/admin/campus-resources', token, {
          method: 'POST',
          body: JSON.stringify({ ...fields, sort_order: 0, is_active: true }),
        });
        setStatus('Resource created.');
      }
      resetForm();
      await load();
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not save resource'));
    } finally {
      setSaving(false);
    }
  }

  async function run(id: string, label: string, doIt: (token: string) => Promise<void>) {
    if (busy) return;
    setBusy(id);
    setError(false);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      await doIt(token);
      setStatus(label);
      if (editingId === id) resetForm();
      await load();
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not complete that action. Please try again.'));
    } finally {
      setBusy(null);
    }
  }

  function setActive(item: Resource, isActive: boolean) {
    void run(item.id, `${isActive ? 'Restored' : 'Deactivated'} “${item.title}”.`, (token) =>
      apiFetch(`/admin/campus-resources/${item.id}`, token, {
        method: 'PATCH',
        body: JSON.stringify({ is_active: isActive }),
      }),
    );
  }

  function remove(item: Resource) {
    if (!window.confirm(`Permanently delete “${item.title}”? This cannot be undone.`)) return;
    void run(item.id, `Deleted “${item.title}”.`, (token) =>
      apiFetch(`/admin/campus-resources/${item.id}`, token, { method: 'DELETE' }),
    );
  }

  return (
    <>
      <div className="ops-toolbar">
        <div className="ops-search">
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search resources" aria-label="Search resources" />
        </div>
        <select className="ops-select" value={filterCat} onChange={(e) => setFilterCat(e.target.value)} aria-label="Category">
          <option value="all">All categories</option>
          {CATEGORIES.map((c) => (
            <option key={c} value={c}>{labelCat(c)}</option>
          ))}
        </select>
        <select
          className="ops-select"
          value={filterActive}
          onChange={(e) => setFilterActive(e.target.value as 'all' | 'active' | 'inactive')}
          aria-label="Active filter"
        >
          <option value="all">All</option>
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
        </select>
        <span className="ops-count">{filtered.length} shown</span>
        <button className="ops-btn" type="button" onClick={() => void load()}>Refresh</button>
        <button
          className="ops-btn primary"
          type="button"
          onClick={() => {
            resetForm();
            setShowForm(true);
          }}
        >
          Add resource
        </button>
      </div>

      {error ? <div className="error-banner">{status}</div> : null}

      {showForm ? (
        <form className="ops-form" onSubmit={submitForm}>
          <h2>{editingId ? 'Edit resource' : 'Add resource'}</h2>
          <div className="grid-2">
            <div className="field">
              <label htmlFor="category">Category</label>
              <select id="category" value={category} onChange={(e) => setCategory(e.target.value)}>
                {CATEGORIES.map((c) => (
                  <option key={c} value={c}>{labelCat(c)}</option>
                ))}
              </select>
            </div>
            <div className="field">
              <label htmlFor="res-title">Title</label>
              <input id="res-title" value={title} onChange={(e) => setTitle(e.target.value)} required />
            </div>
          </div>
          <div className="field">
            <label htmlFor="description">Description</label>
            <textarea id="description" rows={3} value={description} onChange={(e) => setDescription(e.target.value)} required />
          </div>
          <div className="grid-2">
            <div className="field">
              <label htmlFor="location">Location</label>
              <input id="location" value={location} onChange={(e) => setLocation(e.target.value)} />
            </div>
            <div className="field">
              <label htmlFor="hours">Hours</label>
              <input id="hours" value={hours} onChange={(e) => setHours(e.target.value)} />
            </div>
            <div className="field">
              <label htmlFor="res-email">Contact email</label>
              <input id="res-email" type="email" value={contactEmail} onChange={(e) => setContactEmail(e.target.value)} />
            </div>
            <div className="field">
              <label htmlFor="phone">Phone</label>
              <input id="phone" value={phone} onChange={(e) => setPhone(e.target.value)} />
            </div>
          </div>
          <div className="actions">
            <button className="btn" type="submit" disabled={saving} style={{ width: 'auto' }}>
              {saving ? 'Saving…' : editingId ? 'Save changes' : 'Create resource'}
            </button>
            <button className="btn ghost" type="button" onClick={resetForm} style={{ width: 'auto' }}>
              Cancel
            </button>
          </div>
        </form>
      ) : null}

      <div className="ops-table-wrap table-scroll">
        {filtered.length === 0 ? (
          <div className="ops-empty">No resources match these filters.</div>
        ) : (
          <table className="ops-table">
            <thead>
              <tr>
                <th>Resource</th>
                <th>Category</th>
                <th>Location</th>
                <th>Contact</th>
                <th>Status</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {filtered.map((item) => (
                <tr key={item.id}>
                  <td>
                    <div className="ops-cell-title">{item.title}</div>
                    <div className="ops-cell-sub">{item.description.slice(0, 90)}</div>
                  </td>
                  <td style={{ textTransform: 'capitalize' }}>{labelCat(item.category)}</td>
                  <td>{item.location || '—'}</td>
                  <td>{item.contact_email || item.phone || '—'}</td>
                  <td>
                    <span className={item.is_active ? 'ops-chip success' : 'ops-chip muted'}>
                      {item.is_active ? 'Active' : 'Inactive'}
                    </span>
                  </td>
                  <td>
                    <div className="ops-row-actions">
                      <button className="ops-btn" type="button" disabled={busy === item.id} onClick={() => startEdit(item)}>Edit</button>
                      {item.is_active ? (
                        <button className="ops-btn" type="button" disabled={busy === item.id} onClick={() => setActive(item, false)}>Deactivate</button>
                      ) : (
                        <button className="ops-btn primary" type="button" disabled={busy === item.id} onClick={() => setActive(item, true)}>Restore</button>
                      )}
                      <button className="ops-btn danger" type="button" disabled={busy === item.id} onClick={() => remove(item)}>Delete</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
      {!error ? <p className="status" style={{ marginTop: 12 }}>{status}</p> : null}
    </>
  );
}
