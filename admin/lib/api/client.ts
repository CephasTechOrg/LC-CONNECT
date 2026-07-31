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
  if (!base) throw new Error('Missing NEXT_PUBLIC_API_BASE_URL');
  return base.replace(/\/$/, '');
}

export async function apiFetch<T>(
  path: string,
  accessToken: string,
  init: RequestInit = {},
): Promise<T> {
  const response = await fetch(`${apiBase()}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
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
        : response.statusText;
    throw new Error(detail || `Request failed (${response.status})`);
  }

  return data as T;
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
