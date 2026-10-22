export type PostImage = {
  id: string;
  url: string;
  sort_order: number;
};

export type Post = {
  id: string;
  kind: string;
  title: string;
  summary: string | null;
  body: string;
  audience: string;
  category: string | null;
  priority: string;
  status: string;
  external_url: string | null;
  expires_at: string | null;
  images?: PostImage[];
};

export const ANNOUNCEMENT_CATEGORIES: Record<string, string> = {
  general: 'General',
  academic: 'Academic',
  campus: 'Campus',
  events: 'Events',
  safety: 'Safety',
};

export const OPPORTUNITY_CATEGORIES: Record<string, string> = {
  internship: 'Internships',
  job: 'Jobs',
  volunteer: 'Volunteering',
  leadership: 'Leadership',
};

export function categoriesForKind(kind: string): Record<string, string> {
  return kind === 'opportunity' ? OPPORTUNITY_CATEGORIES : ANNOUNCEMENT_CATEGORIES;
}

export function priorityChip(priority: string): string {
  if (priority === 'urgent') return 'ops-chip danger';
  if (priority === 'important') return 'ops-chip warn';
  return 'ops-chip muted';
}

export function statusChip(status: string): string {
  if (status === 'published') return 'ops-chip success';
  if (status === 'archived') return 'ops-chip muted';
  return 'ops-chip warn';
}

/** A browser-side network failure (dead/unreachable server), worth one retry. */
export function isNetworkError(err: unknown): boolean {
  if (!(err instanceof Error)) return false;
  return /failed to fetch|networkerror|load failed|fetch failed/i.test(err.message);
}

/** Run `fn`, retrying exactly once when the failure is a transient network error. */
export async function withNetworkRetry<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (err) {
    if (isNetworkError(err)) return fn();
    throw err;
  }
}
