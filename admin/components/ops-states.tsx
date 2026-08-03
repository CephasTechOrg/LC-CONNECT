import type { ReactNode } from 'react';

/** Shared loading / empty states for admin ops tables. */

export function OpsLoading({ label = 'Loading…' }: { label?: string }) {
  return (
    <div className="ops-empty ops-loading" role="status" aria-live="polite">
      <span className="ops-spinner" aria-hidden />
      <p>{label}</p>
    </div>
  );
}

export function OpsEmpty({
  title,
  children,
}: {
  title?: string;
  children: ReactNode;
}) {
  return (
    <div className="ops-empty">
      {title ? <p className="ops-empty-title">{title}</p> : null}
      <p className="ops-empty-body">{children}</p>
    </div>
  );
}
