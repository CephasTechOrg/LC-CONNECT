export type BootstrapUser = {
  id: string;
  email: string;
  role: string;
  status: string;
  is_verified: boolean;
  profile_completed: boolean;
  auth_user_id: string;
};

function apiBase(): string {
  const base = process.env.NEXT_PUBLIC_API_BASE_URL;
  if (!base) {
    // A misconfigured deploy is an operator problem, not something to explain to an admin in
    // raw form — log the real cause, show them something actionable.
    console.error('NEXT_PUBLIC_API_BASE_URL is not set');
    throw new Error('The portal is not configured correctly. Please contact your system administrator.');
  }
  return base.replace(/\/$/, '');
}

/**
 * The single place a caught error becomes text an administrator reads.
 *
 * Server-sent `detail` strings are already written for humans (they come from our own API), so
 * they pass through. Everything else — network stack errors like "Failed to fetch", thrown
 * config errors, unexpected shapes — is replaced with something actionable, and the technical
 * cause goes to the console for whoever is debugging.
 */
export function toUserMessage(err: unknown, fallback = 'Something went wrong. Please try again.'): string {
  if (err instanceof Error) {
    const raw = err.message;
    // Browsers phrase a dead/unreachable server several different ways.
    if (/failed to fetch|networkerror|load failed|fetch failed/i.test(raw)) {
      console.error(err);
      return 'Cannot reach the server. Check your connection and try again.';
    }
    if (raw) return raw;
  }
  console.error(err);
  return fallback;
}

export async function apiFetch<T>(
  path: string,
  accessToken: string | null,
  init: RequestInit = {},
): Promise<T> {
  const response = await fetch(`${apiBase()}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
      ...(init.headers || {}),
    },
  });

  const text = await response.text();
  let data: unknown = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }

  if (!response.ok) {
    const detail =
      data && typeof data === 'object' && data !== null && 'detail' in data
        ? String((data as { detail: unknown }).detail)
        : '';
    // Our own API's `detail` is already human-readable, so prefer it. Otherwise never surface
    // `statusText`/raw codes — map the status to something an administrator can act on.
    throw new Error(detail || statusMessage(response.status));
  }

  return data as T;
}

function statusMessage(status: number): string {
  if (status === 401) return 'Your session has expired. Please sign in again.';
  if (status === 403) return 'You do not have permission to perform this action.';
  if (status === 404) return 'That item could not be found. It may have been removed.';
  if (status === 409) return 'That action conflicts with the current state. Refresh and try again.';
  if (status === 429) return 'Too many requests. Please wait a moment and try again.';
  if (status >= 500) return 'The server encountered a problem. Please try again shortly.';
  return 'Something went wrong. Please try again.';
}

export async function bootstrapUser(accessToken: string): Promise<BootstrapUser> {
  return apiFetch<BootstrapUser>('/auth/bootstrap', accessToken, { method: 'POST' });
}

export type AdminDashboardSummary = {
  total_users: number;
  open_reports: number;
  pending_positions: number;
  active_scholars: number | null;
  employer_partners: number | null;
  active_opportunities: number | null;
  pending_employer_approvals: number | null;
  pending_opportunity_reviews: number | null;
};

export async function dashboardSummary(accessToken: string): Promise<AdminDashboardSummary> {
  return apiFetch<AdminDashboardSummary>('/admin/dashboard/summary', accessToken);
}

export type ServiceStatus = 'operational' | 'down';

export type SystemStatus = {
  api_gateway: ServiceStatus;
  database: ServiceStatus;
  auth: ServiceStatus;
  storage: ServiceStatus;
};

export async function systemStatus(accessToken: string): Promise<SystemStatus> {
  return apiFetch<SystemStatus>('/admin/system-status', accessToken);
}

export async function forgotPassword(email: string): Promise<void> {
  await apiFetch('/auth/forgot-password', null, {
    method: 'POST',
    body: JSON.stringify({ email, portal: 'admin' }),
  });
}
