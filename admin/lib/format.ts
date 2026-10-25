/**
 * An API value as a label, in sentence case: `pending_review` → "Pending review".
 * Labels used to be Title Cased by CSS (`text-transform: capitalize`), which turned every chip
 * into "Already A Scholar"; the portal writes sentence case like the student app.
 */
export function humanize(value: string | null | undefined): string {
  if (!value) return '';
  const words = value.replace(/[_-]+/g, ' ').trim().toLowerCase();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

/** A day as people say it: "Oct 23, 2026". With `time`, "Oct 23, 2026, 9:47 PM" — never seconds. */
export function formatDate(iso: string | null | undefined, { time = false }: { time?: boolean } = {}): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    ...(time ? { hour: 'numeric', minute: '2-digit' } : {}),
  });
}
