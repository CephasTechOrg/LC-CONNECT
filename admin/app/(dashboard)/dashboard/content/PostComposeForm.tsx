'use client';

import { FormEvent, useEffect, useRef, useState } from 'react';
import { apiFetch, apiUpload, toUserMessage } from '@/lib/api/client';
import { getAccessToken } from '@/lib/auth/session';
import PostImageStrip from './PostImageStrip';
import {
  categoriesForKind,
  withNetworkRetry,
  type Post,
  type PostImage,
} from './post-shared';
import {
  clearComposeDraft,
  loadDraftFields,
  loadPendingFiles,
  saveDraftFields,
  savePendingFiles,
} from './compose-draft-storage';

type PendingFile = {
  localId: string;
  file: File;
  previewUrl: string;
};

export default function PostComposeForm({
  existing,
  onCancel,
  onSaved,
}: {
  existing: Post | null;
  onCancel: () => void;
  onSaved: (flash: string) => void;
}) {
  const isNew = existing == null;

  const [kind, setKind] = useState(existing?.kind ?? 'announcement');
  const [category, setCategory] = useState(
    existing?.category ?? Object.keys(categoriesForKind(existing?.kind ?? 'announcement'))[0],
  );
  const [priority, setPriority] = useState(existing?.priority ?? 'normal');
  const [audience, setAudience] = useState(existing?.audience ?? 'all');
  const [title, setTitle] = useState(existing?.title ?? '');
  const [summary, setSummary] = useState(existing?.summary ?? '');
  const [body, setBody] = useState(existing?.body ?? '');
  const [externalUrl, setExternalUrl] = useState(existing?.external_url ?? '');
  const [expiresAt, setExpiresAt] = useState(existing?.expires_at ? existing.expires_at.slice(0, 10) : '');

  const [postId, setPostId] = useState<string | null>(existing?.id ?? null);
  const [uploaded, setUploaded] = useState<PostImage[]>(existing?.images ?? []);
  const [pending, setPending] = useState<PendingFile[]>([]);
  const [saving, setSaving] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [hydrated, setHydrated] = useState(!isNew);

  const isPublished = existing?.status === 'published';
  const isOpportunity = kind === 'opportunity';

  // Revoke object URLs for queued photos when the form unmounts.
  const pendingRef = useRef(pending);
  pendingRef.current = pending;
  useEffect(() => () => pendingRef.current.forEach((p) => URL.revokeObjectURL(p.previewUrl)), []);

  // Restore an unsaved draft (text + queued photos) only for a brand-new compose.
  useEffect(() => {
    if (!isNew) return;
    const fields = loadDraftFields();
    if (fields) {
      setKind(fields.kind);
      setCategory(fields.category);
      setPriority(fields.priority);
      setAudience(fields.audience);
      setTitle(fields.title);
      setSummary(fields.summary);
      setBody(fields.body);
      setExternalUrl(fields.externalUrl);
      setExpiresAt(fields.expiresAt);
    }
    void loadPendingFiles().then((stored) => {
      if (stored.length === 0) return;
      setPending(
        stored.map((s) => ({ localId: s.localId, file: s.file, previewUrl: URL.createObjectURL(s.file) })),
      );
    });
    setHydrated(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Persist text fields while the post has not yet been created on the server.
  useEffect(() => {
    if (!isNew || postId || !hydrated) return;
    saveDraftFields({ kind, category, priority, audience, title, summary, body, externalUrl, expiresAt });
  }, [isNew, postId, hydrated, kind, category, priority, audience, title, summary, body, externalUrl, expiresAt]);

  // Persist queued photo blobs on the same pre-create window.
  useEffect(() => {
    if (!isNew || postId || !hydrated) return;
    void savePendingFiles(pending.map((p) => ({ localId: p.localId, file: p.file })));
  }, [isNew, postId, hydrated, pending]);

  function onKindChange(nextKind: string) {
    setKind(nextKind);
    setCategory(Object.keys(categoriesForKind(nextKind))[0]);
  }

  function addFiles(files: File[]) {
    setPending((prev) => {
      const room = 4 - (uploaded.length + prev.length);
      if (room <= 0) return prev;
      const next = files.slice(0, room).map((file) => ({
        localId: crypto.randomUUID(),
        file,
        previewUrl: URL.createObjectURL(file),
      }));
      return [...prev, ...next];
    });
  }

  function removePending(localId: string) {
    setPending((prev) => {
      const found = prev.find((p) => p.localId === localId);
      if (found) URL.revokeObjectURL(found.previewUrl);
      return prev.filter((p) => p.localId !== localId);
    });
  }

  async function removeUploaded(imageId: string) {
    if (!postId) return;
    setSaving(true);
    setErrorMsg(null);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const updated = await withNetworkRetry(() =>
        apiFetch<Post>(`/admin/campus-posts/${postId}/images/${imageId}`, token, { method: 'DELETE' }),
      );
      setUploaded(updated.images ?? []);
    } catch (err) {
      setErrorMsg(toUserMessage(err, 'Could not remove photo'));
    } finally {
      setSaving(false);
    }
  }

  function validate(): string | null {
    if (!title.trim()) return 'Title is required.';
    if (isOpportunity && !summary.trim()) return 'Opportunities need a brief summary.';
    if (!isOpportunity && !body.trim()) return 'Announcements need a body.';
    return null;
  }

  async function submit(publish: boolean) {
    const problem = validate();
    if (problem) {
      setErrorMsg(problem);
      return;
    }
    if (publish && (priority === 'urgent' || priority === 'important')) {
      if (!window.confirm(`Publish as ${priority}? This may send a push notification.`)) return;
    }

    setSaving(true);
    setErrorMsg(null);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error('Not signed in');
      const payload = {
        kind,
        category,
        priority,
        audience,
        title: title.trim(),
        summary: summary.trim() || null,
        body: isOpportunity ? '' : body.trim(),
        external_url: externalUrl.trim() || null,
        // End of the chosen day where the admin is, not in UTC: `T23:59:59Z` closed posts at about
        // 7–8 PM on campus, hours before the date shown to students.
        expires_at: expiresAt ? new Date(`${expiresAt}T23:59:59`).toISOString() : null,
      };

      let post: Post;
      if (postId) {
        post = await withNetworkRetry(() =>
          apiFetch<Post>(`/admin/campus-posts/${postId}`, token, {
            method: 'PATCH',
            body: JSON.stringify(payload),
          }),
        );
      } else {
        post = await withNetworkRetry(() =>
          apiFetch<Post>('/admin/campus-posts', token, { method: 'POST', body: JSON.stringify(payload) }),
        );
        setPostId(post.id);
        // The server draft is now the source of truth — stop restoring this as an unsaved draft.
        await clearComposeDraft();
      }

      let leftover = pending;
      for (const item of pending) {
        try {
          const form = new FormData();
          form.append('file', item.file);
          post = await withNetworkRetry(() =>
            apiUpload<Post>(`/admin/campus-posts/${post.id}/images`, token, form),
          );
          URL.revokeObjectURL(item.previewUrl);
          leftover = leftover.filter((x) => x.localId !== item.localId);
          setPending(leftover);
        } catch {
          setPending(leftover);
          setUploaded(post.images ?? []);
          throw new Error(
            'Some photos did not upload. The post was saved as a draft — press Publish or Save draft to retry the remaining photos.',
          );
        }
      }
      setUploaded(post.images ?? []);

      if (publish) {
        await withNetworkRetry(() =>
          apiFetch(`/admin/campus-posts/${post.id}/publish`, token, { method: 'POST' }),
        );
      }

      onSaved(publish ? 'Published.' : isNew ? 'Draft saved.' : 'Changes saved.');
    } catch (err) {
      setErrorMsg(toUserMessage(err, 'Could not save post'));
    } finally {
      setSaving(false);
    }
  }

  function onSubmitForm(event: FormEvent) {
    event.preventDefault();
    void submit(false);
  }

  const priorityNote =
    priority === 'urgent'
      ? 'Urgent posts can send a push notification to everyone in the audience.'
      : priority === 'important'
        ? 'Important posts may send a push notification.'
        : null;

  return (
    <form className="compose" onSubmit={onSubmitForm} aria-labelledby="compose-title">
      <button
        type="button"
        className="compose-back"
        onClick={() => {
          if (isNew) void clearComposeDraft();
          onCancel();
        }}
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          <path d="m15 6-6 6 6 6" />
        </svg>
        All posts
      </button>

      <header className="page-header">
        <div className="page-header-copy">
          <h1 id="compose-title">{isNew ? 'New post' : 'Edit post'}</h1>
          <p>
            {isNew
              ? 'Write it, choose who sees it, then publish or keep it as a draft.'
              : isPublished
                ? 'This post is live. Changes show on Campus Hub as soon as you save.'
                : 'This draft is only visible to admins until you publish it.'}
          </p>
        </div>
      </header>

      <div className="compose-grid">
        {/* What the post says */}
        <section className="compose-card" aria-label="Content">
          <div className="compose-field">
            <label htmlFor="title">Title</label>
            <input
              id="title"
              className="compose-title-input"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              required
              maxLength={200}
              placeholder="A short, clear headline"
              autoFocus={isNew}
            />
          </div>

          <div className="compose-field">
            <label htmlFor="summary">
              {isOpportunity ? 'Brief summary' : 'Summary'}
              {isOpportunity ? null : <span className="compose-optional"> · optional</span>}
            </label>
            <input
              id="summary"
              value={summary}
              onChange={(e) => setSummary(e.target.value)}
              maxLength={400}
              required={isOpportunity}
              placeholder={isOpportunity ? 'One or two lines students see on the card' : 'One line shown in the feed'}
            />
          </div>

          {!isOpportunity ? (
            <div className="compose-field">
              <label htmlFor="body">Details</label>
              <textarea
                id="body"
                rows={8}
                value={body}
                onChange={(e) => setBody(e.target.value)}
                required
                placeholder="Write the full message…"
              />
            </div>
          ) : null}

          {!isOpportunity ? (
            <PostImageStrip
              uploaded={uploaded}
              pending={pending.map((p) => ({ localId: p.localId, previewUrl: p.previewUrl }))}
              busy={saving}
              onAddFiles={addFiles}
              onRemoveUploaded={(imageId) => void removeUploaded(imageId)}
              onRemovePending={removePending}
            />
          ) : null}
        </section>

        {/* Who sees it, and how */}
        <aside className="compose-card" aria-label="Settings">
          <h2>Settings</h2>

          <div className="compose-field">
            <span className="compose-label" id="kind-label">Type</span>
            <Segmented
              labelledBy="kind-label"
              value={kind}
              options={[
                ['announcement', 'Announcement'],
                ['opportunity', 'Opportunity'],
              ]}
              onChange={onKindChange}
              disabled={!isNew}
            />
            {!isNew ? <p className="compose-hint">The type is fixed once a post exists.</p> : null}
          </div>

          <div className="compose-field">
            <label htmlFor="category">Category</label>
            <select id="category" value={category} onChange={(e) => setCategory(e.target.value)}>
              {Object.entries(categoriesForKind(kind)).map(([value, label]) => (
                <option key={value} value={value}>{label}</option>
              ))}
            </select>
          </div>

          <div className="compose-field">
            <span className="compose-label" id="audience-label">Audience</span>
            <Segmented
              labelledBy="audience-label"
              value={audience}
              options={[
                ['all', 'Everyone'],
                ['students', 'Students'],
                ['staff', 'Staff'],
              ]}
              onChange={setAudience}
            />
          </div>

          <div className="compose-field">
            <span className="compose-label" id="priority-label">Priority</span>
            <Segmented
              labelledBy="priority-label"
              value={priority}
              options={[
                ['normal', 'Normal'],
                ['important', 'Important'],
                ['urgent', 'Urgent'],
              ]}
              onChange={setPriority}
            />
            {/* Said here, while choosing — not only in a confirm box at the last moment. */}
            {priorityNote ? <p className="compose-hint warn">{priorityNote}</p> : null}
          </div>

          <div className="compose-field">
            <label htmlFor="external_url">
              {isOpportunity ? 'Application or details link' : 'Link'}
              <span className="compose-optional"> · optional</span>
            </label>
            <input
              id="external_url"
              type="url"
              value={externalUrl}
              onChange={(e) => setExternalUrl(e.target.value)}
              placeholder="https://…"
            />
          </div>

          <div className="compose-field">
            <label htmlFor="expires_at">
              Closes on<span className="compose-optional"> · optional</span>
            </label>
            <input id="expires_at" type="date" value={expiresAt} onChange={(e) => setExpiresAt(e.target.value)} />
          </div>
        </aside>
      </div>

      {errorMsg ? <p className="error-banner" role="alert">{errorMsg}</p> : null}

      {/* Pinned, so publishing never means scrolling back down a long post. One primary action. */}
      <div className="compose-actions">
        <span className="compose-status">
          {isNew && !postId ? 'Your draft is kept on this device until you save it.' : null}
        </span>
        <button
          className="btn-quiet"
          type="button"
          onClick={() => {
            if (isNew) void clearComposeDraft();
            onCancel();
          }}
        >
          Cancel
        </button>
        {isPublished ? (
          <button className="btn-primary" type="submit" disabled={saving}>
            {saving ? 'Saving…' : 'Save changes'}
          </button>
        ) : (
          <>
            <button className="btn-secondary" type="submit" disabled={saving}>
              {saving ? 'Saving…' : 'Save draft'}
            </button>
            <button className="btn-primary" type="button" disabled={saving} onClick={() => void submit(true)}>
              {saving ? 'Working…' : 'Publish'}
            </button>
          </>
        )}
      </div>
    </form>
  );
}

/** A choice of two or three, shown all at once — a tinted track with the selected option raised. */
function Segmented({
  value,
  options,
  onChange,
  labelledBy,
  disabled = false,
}: {
  value: string;
  options: [string, string][];
  onChange: (value: string) => void;
  labelledBy: string;
  disabled?: boolean;
}) {
  return (
    <div className="seg-tabs" role="radiogroup" aria-labelledby={labelledBy}>
      {options.map(([optionValue, label]) => (
        <button
          key={optionValue}
          type="button"
          role="radio"
          aria-checked={value === optionValue}
          disabled={disabled}
          className={`seg-tab${value === optionValue ? ' active' : ''}`}
          onClick={() => onChange(optionValue)}
        >
          {label}
        </button>
      ))}
    </div>
  );
}
