'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api/client';
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

export default function ResourcesPage() {
  const [items, setItems] = useState<Resource[]>([]);
  const [status, setStatus] = useState('Load resources to begin.');
  const [error, setError] = useState(false);
  const [category, setCategory] = useState('advising');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [location, setLocation] = useState('');
  const [hours, setHours] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [phone, setPhone] = useState('');
  const [saving, setSaving] = useState(false);

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
      setStatus(err instanceof Error ? err.message : 'Failed to load');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function createResource(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      await apiFetch('/admin/campus-resources', token, {
        method: 'POST',
        body: JSON.stringify({
          category,
          title: title.trim(),
          description: description.trim(),
          location: location.trim() || null,
          hours: hours.trim() || null,
          contact_email: contactEmail.trim() || null,
          phone: phone.trim() || null,
          sort_order: 0,
          is_active: true,
        }),
      });
      setTitle('');
      setDescription('');
      setLocation('');
      setHours('');
      setContactEmail('');
      setPhone('');
      setStatus('Resource created.');
      await load();
    } catch (err) {
      setError(true);
      setStatus(err instanceof Error ? err.message : 'Could not create resource');
    } finally {
      setSaving(false);
    }
  }

  async function deactivate(item: Resource) {
    const token = await getAccessToken();
    if (!token) return;
    await apiFetch(`/admin/campus-resources/${item.id}`, token, {
      method: 'PATCH',
      body: JSON.stringify({ is_active: false }),
    });
    setStatus(`Deactivated “${item.title}”.`);
    await load();
  }

  return (
    <>
      <header className="topbar">
        <div>
          <h1>Campus Resources</h1>
          <p>Evergreen offices and support listings</p>
        </div>
        <button className="btn secondary" type="button" onClick={() => void load()} style={{ width: 'auto' }}>
          Refresh
        </button>
      </header>
      <div className="content">
        <form className="panel" onSubmit={createResource}>
          <h2>Add resource</h2>
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
              <label htmlFor="title">Title</label>
              <input id="title" value={title} onChange={(e) => setTitle(e.target.value)} required />
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
              <label htmlFor="email">Contact email</label>
              <input
                id="email"
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
          <button className="btn" type="submit" disabled={saving} style={{ width: 'auto' }}>
            {saving ? 'Saving…' : 'Create resource'}
          </button>
        </form>

        <p className={`status${error ? ' error' : ''}`}>{status}</p>
        <div className="card-list">
          {items.map((item) => (
            <article key={item.id} className="card">
              <div className="card-head">
                <div>
                  <h3>{item.title}</h3>
                  <p className="meta">
                    {item.category.replaceAll('_', ' ')} · {item.is_active ? 'active' : 'inactive'}
                  </p>
                </div>
                <span className="badge">{item.is_active ? 'active' : 'inactive'}</span>
              </div>
              <p className="meta">{item.description}</p>
              {item.location ? <p className="meta">Location: {item.location}</p> : null}
              {item.hours ? <p className="meta">Hours: {item.hours}</p> : null}
              {item.is_active ? (
                <div className="actions">
                  <button className="btn danger" type="button" onClick={() => void deactivate(item)}>
                    Deactivate
                  </button>
                </div>
              ) : null}
            </article>
          ))}
        </div>
      </div>
    </>
  );
}
