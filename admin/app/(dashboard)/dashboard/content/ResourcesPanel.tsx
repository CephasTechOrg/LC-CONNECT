'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
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

export default function ResourcesPanel() {
  const [items, setItems] = useState<Resource[]>([]);
  const [status, setStatus] = useState('Loading resources…');
  const [error, setError] = useState(false);
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

  function resetForm() {
    setEditingId(null);
    setCategory('advising');
    setTitle('');
    setDescription('');
    setLocation('');
    setHours('');
    setContactEmail('');
    setPhone('');
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
    if (typeof window !== 'undefined') window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  const load = useCallback(async () => {
    setError(false);
    setStatus('Loading resources…');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const data = await apiFetch<Resource[]>('/admin/campus-resources', token);
      setItems(data);
      setStatus(`${data.length} resource(s).`);
    } catch (err) {
      setError(true);
      setStatus(toUserMessage(err, 'Could not load this page. Please refresh and try again.'));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

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

  // Hardened per-item runner: blocks double-clicks, always catches + surfaces errors, reloads.
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
      <form className="panel" onSubmit={submitForm}>
        <h2>{editingId ? 'Edit resource' : 'Add resource'}</h2>
        <div className="grid-2">
          <div className="field">
            <label htmlFor="category">Category</label>
            <select id="category" value={category} onChange={(e) => setCategory(e.target.value)}>
              {CATEGORIES.map((c) => (
                <option key={c} value={c}>
                  {c.replaceAll('_', ' ')}
                </option>
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
          <textarea
            id="description"
            rows={3}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            required
          />
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
            <input
              id="res-email"
              type="email"
              value={contactEmail}
              onChange={(e) => setContactEmail(e.target.value)}
            />
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
          {editingId ? (
            <button className="btn ghost" type="button" onClick={resetForm} style={{ width: 'auto' }}>
              Cancel
            </button>
          ) : null}
        </div>
      </form>

      <div className="actions" style={{ justifyContent: 'space-between', alignItems: 'center' }}>
        <p className={`status${error ? ' error' : ''}`} style={{ margin: 0 }}>
          {status}
        </p>
        <button className="btn ghost" type="button" onClick={() => void load()} style={{ width: 'auto' }}>
          Refresh
        </button>
      </div>
      <div className="card-list">
        {items.map((item) => (
          <article key={item.id} className="card">
            <div className="card-head">
              <div>
                <h3>{item.title}</h3>
                <p className="meta">{item.category.replaceAll('_', ' ')}</p>
              </div>
              <span className={item.is_active ? 'badge success' : 'badge muted'}>
                {item.is_active ? 'active' : 'inactive'}
              </span>
            </div>
            <p className="meta">{item.description}</p>
            {item.location ? <p className="meta">Location: {item.location}</p> : null}
            {item.hours ? <p className="meta">Hours: {item.hours}</p> : null}
            <div className="actions">
              <button className="btn ghost" type="button" disabled={busy === item.id} onClick={() => startEdit(item)}>
                Edit
              </button>
              {item.is_active ? (
                <button className="btn ghost" type="button" disabled={busy === item.id} onClick={() => setActive(item, false)}>
                  Deactivate
                </button>
              ) : (
                <button className="btn secondary" type="button" disabled={busy === item.id} onClick={() => setActive(item, true)}>
                  Restore
                </button>
              )}
              <button className="btn danger" type="button" disabled={busy === item.id} onClick={() => remove(item)}>
                Delete
              </button>
            </div>
          </article>
        ))}
      </div>
    </>
  );
}
