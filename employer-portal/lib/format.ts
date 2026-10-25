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

/** A month from a date-only value: "2025-06-01" → "Jun 2025". Anything unparseable passes through. */
export function formatMonth(value: string): string {
  const match = /^(\d{4})-(\d{2})/.exec(value);
  if (!match) return value;
  const d = new Date(Number(match[1]), Number(match[2]) - 1, 1);
  return d.toLocaleString('en-US', { month: 'short', year: 'numeric' });
}
