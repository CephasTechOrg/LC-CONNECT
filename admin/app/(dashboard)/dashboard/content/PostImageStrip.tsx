'use client';

import { ChangeEvent, useRef } from 'react';
import type { PostImage } from './post-shared';

export type { PostImage };

export type PendingImage = {
  localId: string;
  previewUrl: string;
};

export default function PostImageStrip({
  uploaded,
  pending,
  busy,
  onAddFiles,
  onRemoveUploaded,
  onRemovePending,
}: {
  uploaded: PostImage[];
  pending: PendingImage[];
  busy: boolean;
  onAddFiles: (files: File[]) => void;
  onRemoveUploaded: (imageId: string) => void;
  onRemovePending: (localId: string) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);

  const total = uploaded.length + pending.length;
  const remaining = Math.max(0, 4 - total);

  function onPick(event: ChangeEvent<HTMLInputElement>) {
    const picked = Array.from(event.target.files ?? []);
    event.target.value = '';
    if (picked.length === 0) return;
    onAddFiles(picked.slice(0, remaining));
  }

  return (
    <div className="compose-field">
      <span className="compose-label">
        Photos<span className="compose-optional"> · optional</span>
      </span>
      <p className="compose-hint">
        {remaining <= 0
          ? 'Four photos attached. The first is the cover.'
          : `Up to ${remaining} more. The first is the cover.`}
      </p>
      <div className="photo-strip">
        {uploaded.map((image, index) => (
          <Thumb
            key={image.id}
            src={image.url}
            isCover={index === 0}
            label={index === 0 ? 'Cover photo' : `Photo ${index + 1}`}
            busy={busy}
            onRemove={() => onRemoveUploaded(image.id)}
          />
        ))}
        {pending.map((image, index) => {
          const position = uploaded.length + index;
          return (
            <Thumb
              key={image.localId}
              src={image.previewUrl}
              isCover={position === 0}
              label={position === 0 ? 'Cover photo' : `Photo ${position + 1}`}
              uploading
              busy={busy}
              onRemove={() => onRemovePending(image.localId)}
            />
          );
        })}
        {remaining > 0 ? (
          // A tile the size of a photo, so the strip reads as "slots", not as a stray button.
          <button
            type="button"
            className="photo-add"
            disabled={busy}
            onClick={() => inputRef.current?.click()}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden>
              <path d="M12 5v14M5 12h14" />
            </svg>
            Add photo
          </button>
        ) : null}
      </div>
      <input
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        multiple
        hidden
        onChange={onPick}
      />
    </div>
  );
}

function Thumb({
  src,
  isCover,
  label,
  busy,
  uploading,
  onRemove,
}: {
  src: string;
  isCover: boolean;
  label: string;
  busy: boolean;
  uploading?: boolean;
  onRemove: () => void;
}) {
  return (
    <div className="photo-thumb">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={src} alt={label} style={uploading ? { opacity: 0.72 } : undefined} />
      {isCover ? <span className="photo-tag left">Cover</span> : null}
      {uploading ? <span className="photo-tag right">Not saved</span> : null}
      <button type="button" className="photo-remove" disabled={busy} onClick={onRemove} aria-label={`Remove ${label}`}>
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" aria-hidden>
          <path d="M6 6l12 12M18 6 6 18" />
        </svg>
      </button>
    </div>
  );
}
