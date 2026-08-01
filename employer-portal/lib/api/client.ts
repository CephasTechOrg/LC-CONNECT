export type MyEmployer = {
  organization_id: string;
  organization_name: string;
  organization_status: 'pending' | 'approved' | 'rejected';
  email: string;
  display_name: string | null;
};

function apiBase(): string {
  const base = process.env.NEXT_PUBLIC_API_BASE_URL;
  if (!base) throw new Error('Missing NEXT_PUBLIC_API_BASE_URL');
  return base.replace(/\/$/, '');
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
        : response.statusText;
    throw new Error(detail || `Request failed (${response.status})`);
  }

  return data as T;
}

export async function myEmployer(accessToken: string): Promise<MyEmployer> {
  return apiFetch<MyEmployer>('/employers/me', accessToken);
}

export async function forgotPassword(email: string): Promise<void> {
  await apiFetch('/auth/forgot-password', null, {
    method: 'POST',
    body: JSON.stringify({ email, portal: 'employer' }),
  });
}
