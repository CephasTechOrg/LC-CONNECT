'use client';

import { ChangeEvent, useRef, useState } from 'react';

export type PostImage = {
  id: string;
  url: string;
  sort_order: number;
};

export default function PostImageStrip({
  images,
  remaining,
  busy,
  onAdd,
  onRemove,
}: {
  images: PostImage[];
  remaining: number;
  busy: boolean;
  onAdd: (file: File) => Promise<void>;
  onRemove: (imageId: string) => Promise<void>;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);

  async function onPick(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    setUploading(true);
    try {
      await onAdd(file);
    } finally {
      setUploading(false);
    }
  }

  const locked = busy || uploading;

  return (
    <div className="field">
      <label>Photos (optional)</label>
      <p className="ops-cell-sub" style={{ marginBottom: 8 }}>
        {remaining <= 0
          ? '4 photos attached — first is the cover.'
          : `${remaining} of 4 photos remaining. First is the cover.`}
      </p>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
        {images.map((image, index) => (
          <div key={image.id} style={{ position: 'relative', width: 72, height: 72 }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={image.url}
              alt={index === 0 ? 'Cover photo' : `Photo ${index + 1}`}
              style={{ width: 72, height: 72, objectFit: 'cover', borderRadius: 8, border: '1px solid var(--border, #e5e7eb)' }}
            />
            {index === 0 ? (
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
            <button
              type="button"
              className="ops-btn danger"
              disabled={locked}
              onClick={() => void onRemove(image.id)}
              aria-label={`Remove photo ${index + 1}`}
              style={{ position: 'absolute', top: -6, right: -6, width: 'auto', padding: '2px 6px', fontSize: 12 }}
            >
              ×
            </button>
          </div>
        ))}
        {remaining > 0 ? (
          <button
            type="button"
            className="ops-btn"
            disabled={locked}
            onClick={() => inputRef.current?.click()}
          >
            {uploading ? 'Uploading…' : 'Add photo'}
          </button>
        ) : null}
      </div>
      <input
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        hidden
        onChange={(event) => void onPick(event)}
      />
    </div>
  );
}
