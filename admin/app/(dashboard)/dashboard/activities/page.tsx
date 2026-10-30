'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { OpsEmpty, OpsLoading } from '@/components/ops-states';
import { apiFetch, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';
import { formatDate, humanize } from '@/lib/format';

type AdminActivity = {
  id: string;
  title: string;
  category: string;
  location: string;
  start_time: string;
  end_time: string | null;
  participant_count: number;
  max_participants: number | null;
  creator_name: string | null;
  featured_until: string | null;
};

/** `yyyy-mm-dd` for a date input, `days` from today in local time. */
function dayInput(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** End of the chosen day in the admin's own time zone, as an ISO instant. */
function endOfDay(day: string): string {
  return new Date(`${day}T23:59:59`).toISOString();
}

export default function ActivitiesPage() {
  const [items, setItems] = useState<AdminActivity[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [flash, setFlash] = useState<string | null>(null);
  const [q, setQ] = useState('');
  const [pinning, setPinning] = useState<AdminActivity | null>(null);
  const [until, setUntil] = useState(dayInput(7));
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      setItems(await apiFetch<AdminActivity[]>('/admin/activities', token));
    } catch (err) {
      setError(toUserMessage(err, 'Could not load activities. Please refresh and try again.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const pick = items.find((a) => a.featured_until);
  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    if (!needle) return items;
    return items.filter(
      (a) =>
        a.title.toLowerCase().includes(needle) ||
        a.location.toLowerCase().includes(needle) ||
        (a.creator_name || '').toLowerCase().includes(needle),
    );
  }, [items, q]);

  async function feature(activity: AdminActivity) {
    setBusy(true);
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/activities/${activity.id}/feature`, token, {
        method: 'POST',
        body: JSON.stringify({ until: endOfDay(until) }),
      });
      setFlash(`${activity.title} is the campus pick until ${formatDate(endOfDay(until))}.`);
      setPinning(null);
      await load();
    } catch (err) {
      setError(toUserMessage(err, 'Could not feature this activity.'));
    } finally {
      setBusy(false);
    }
  }

  async function unfeature(activity: AdminActivity) {
    setBusy(true);
    try {
      const token = await getAccessToken();
      if (!token) return;
      await apiFetch(`/admin/activities/${activity.id}/feature`, token, { method: 'DELETE' });
      setFlash(`${activity.title} is no longer featured. The app picks automatically again.`);
      await load();
    } catch (err) {
      setError(toUserMessage(err, 'Could not remove the campus pick.'));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <header className="ops-top">
        <div>
          <h1>Activities</h1>
          <p>
            Choose the campus pick that leads Activities and Home for every student. Without one,
            the app features what is starting soon, filling up or popular.
          </p>
        </div>
      </header>

      <div className="content" style={{ paddingTop: 8 }}>
        {error ? <div className="error-banner">{error}</div> : null}
        {pick ? (
          <p className="ops-flash">
            Campus pick: <strong>{pick.title}</strong>, until {formatDate(pick.featured_until)}.
          </p>
        ) : null}
        {flash ? <p className="ops-flash">{flash}</p> : null}

        <div className="ops-toolbar">
          <div className="ops-search">
            <input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Search by title, place, or organizer"
              aria-label="Search activities"
            />
          </div>
          <span className="ops-count">{loading ? '…' : `${filtered.length} upcoming`}</span>
          <button className="ops-btn" type="button" disabled={loading} onClick={() => void load()}>
            Refresh
          </button>
        </div>

        <div className="ops-table-wrap table-scroll">
          {loading ? (
            <OpsLoading label="Loading activities…" />
          ) : filtered.length === 0 ? (
            <OpsEmpty title={items.length === 0 ? 'Nothing upcoming' : 'No matches'}>
              {items.length === 0 ? 'No upcoming activities yet.' : 'Try a different search.'}
            </OpsEmpty>
          ) : (
            <table className="ops-table ops-cards-sm">
              <thead>
                <tr>
                  <th>Activity</th>
                  <th>When</th>
                  <th className="ops-col-hide-md">Going</th>
                  <th className="ops-col-hide-md">Organizer</th>
                  <th className="ops-col-actions">Campus pick</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((a) => (
                  <tr key={a.id}>
                    <td>
                      <div className="ops-cell-title" title={a.title}>{a.title}</div>
                      <div className="ops-cell-sub">
                        {humanize(a.category)} · {a.location}
                      </div>
                    </td>
                    <td data-label="When">{formatDate(a.start_time, { time: true })}</td>
                    <td className="ops-col-hide-md" data-label="Going">
                      {a.max_participants ? `${a.participant_count} / ${a.max_participants}` : a.participant_count}
                    </td>
                    <td className="ops-col-hide-md" data-label="Organizer">{a.creator_name || '—'}</td>
                    <td className="ops-col-actions ops-cell-actions">
                      <div className="ops-row-actions">
                        {a.featured_until ? (
                          <>
                            <span className="ops-chip success">Featured</span>
                            <button className="ops-btn" type="button" disabled={busy} onClick={() => void unfeature(a)}>
                              Remove
                            </button>
                          </>
                        ) : (
                          <button
                            className="ops-btn"
                            type="button"
                            disabled={busy}
                            onClick={() => {
                              setPinning(a);
                              setUntil(dayInput(7));
                            }}
                          >
                            Feature
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {pinning ? (
        <>
          <div className="ops-drawer-backdrop" onClick={() => setPinning(null)} aria-hidden />
          <aside className="ops-drawer" role="dialog" aria-label="Feature activity">
            <div className="ops-drawer-head">
              <div>
                <h2>Feature {pinning.title}</h2>
                <div className="ops-drawer-meta">
                  {formatDate(pinning.start_time, { time: true })} · {pinning.location}
                </div>
              </div>
              <button className="ops-drawer-close" type="button" aria-label="Close" onClick={() => setPinning(null)}>
                ✕
              </button>
            </div>
            <div className="field">
              <label htmlFor="feature-until">Feature until</label>
              <input
                id="feature-until"
                type="date"
                value={until}
                min={dayInput(0)}
                max={dayInput(60)}
                onChange={(e) => setUntil(e.target.value)}
              />
              <p className="ops-cell-sub">
                It leads Activities and Home until the end of that day, or until it ends. Featuring it
                replaces any current campus pick.
              </p>
            </div>
            <div className="ops-drawer-footer">
              <button className="btn secondary" type="button" onClick={() => setPinning(null)}>
                Cancel
              </button>
              <button className="btn" type="button" disabled={busy || !until} onClick={() => void feature(pinning)}>
                Feature
              </button>
            </div>
          </aside>
        </>
      ) : null}
    </>
  );
}
