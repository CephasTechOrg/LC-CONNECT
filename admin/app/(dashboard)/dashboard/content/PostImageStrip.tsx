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
    <div className="field">
      <label>Photos (optional)</label>
      <p className="ops-cell-sub" style={{ marginBottom: 8 }}>
        {remaining <= 0
          ? '4 photos attached — the first is the cover.'
          : `${remaining} of 4 photos remaining. The first is the cover.`}
      </p>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
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
          <button
            type="button"
            className="ops-btn"
            disabled={busy}
            onClick={() => inputRef.current?.click()}
          >
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
    <div style={{ position: 'relative', width: 72, height: 72 }}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={src}
        alt={label}
        style={{
          width: 72,
          height: 72,
          objectFit: 'cover',
          borderRadius: 8,
          border: '1px solid var(--border, #e5e7eb)',
          opacity: uploading ? 0.72 : 1,
        }}
      />
      {isCover ? (
        <span
          style={{
            position: 'absolute',
            left: 4,
            bottom: 4,
            background: 'rgba(0,0,0,0.65)',
            color: '#fff',
            fontSize: 10,
            fontWeight: 700,
            padding: '1px 5px',
            borderRadius: 4,
          }}
        >
          Cover
        </span>
      ) : null}
      {uploading ? (
        <span
          style={{
            position: 'absolute',
            right: 4,
            bottom: 4,
            background: 'rgba(0,0,0,0.6)',
            color: '#fff',
            fontSize: 9,
            fontWeight: 700,
            padding: '1px 5px',
            borderRadius: 4,
          }}
        >
          Not saved
        </span>
      ) : null}
      <button
        type="button"
        className="ops-btn danger"
        disabled={busy}
        onClick={onRemove}
        aria-label={`Remove ${label}`}
        style={{ position: 'absolute', top: -6, right: -6, width: 'auto', padding: '2px 6px', fontSize: 12 }}
      >
        ×
      </button>
    </div>
  );
}
