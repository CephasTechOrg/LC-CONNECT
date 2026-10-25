import type { ReactNode } from 'react';

/**
 * Building blocks every admin page opens with — the same set the InterviewPrep admin console
 * uses (PageHeader, SectionTitle, StatRow). Styles live in `dashboard/dashboard.css`.
 */

/** The large title and one-line summary that open a page, with an optional right-hand action. */
export function PageHeader({
  title,
  subtitle,
  action,
}: {
  title: string;
  subtitle?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <header className="page-header">
      <div className="page-header-copy">
        <h1>{title}</h1>
        {subtitle ? <p>{subtitle}</p> : null}
      </div>
      {action ? <div className="page-header-action">{action}</div> : null}
    </header>
  );
}

/** A section heading with an optional muted line and a right-hand slot. */
export function SectionTitle({
  title,
  detail,
  aside,
  id,
}: {
  title: string;
  detail?: ReactNode;
  aside?: ReactNode;
  id?: string;
}) {
  return (
    <div className="section-title">
      <div>
        <h2 id={id}>{title}</h2>
        {detail ? <p>{detail}</p> : null}
      </div>
      {aside}
    </div>
  );
}

export type StatItem = { key: string; value: ReactNode; label: string; hint?: ReactNode };

/** Headline numbers as a row of cards, the first raised in the sidebar's blue. */
export function StatRow({ items, label, loading }: { items: StatItem[]; label: string; loading?: boolean }) {
  return (
    <section aria-label={label} className="stat-row" style={{ ['--stat-cols' as string]: String(items.length) }}>
      {items.map((item) => (
        <div className="stat" key={item.key}>
          {/* A placeholder while loading — never a fake 0 that reads as a real count. */}
          <span className="stat-value">{loading ? '–' : item.value}</span>
          <span className="stat-label">{item.label}</span>
          {item.hint ? <span className="stat-hint">{item.hint}</span> : null}
        </div>
      ))}
    </section>
  );
}

export function ChevronRight({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="m9 6 6 6-6 6" />
    </svg>
  );
}

export function RefreshIcon({ spinning = false }: { spinning?: boolean }) {
  return (
    <svg
      width="15"
      height="15"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
      style={spinning ? { animation: 'spin 0.9s linear infinite' } : undefined}
    >
      <path d="M20 11a8 8 0 1 0-.9 4.5" />
      <path d="M20 4.5V11h-6.2" />
    </svg>
  );
}
