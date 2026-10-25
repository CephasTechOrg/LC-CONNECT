import type { BootstrapUser } from '@/lib/api/client';

export type AdminMembership = {
  id: string;
  role: string;
  status: string;
  user_email: string;
  display_name: string | null;
};

export const ROLE_SHORT: Record<string, string> = {
  super_admin: 'Super admin',
  school_admin: 'School admin',
  honors_admin: 'Honors admin',
  content_admin: 'Content admin',
  auditor: 'Auditor',
};

/** The first name the dashboard greets: from signup when the account has one, else the address. */
export function greetingName(user: BootstrapUser | null): string {
  const fromSignup = user?.first_name?.trim();
  if (fromSignup) return fromSignup;
  const email = user?.email;
  if (!email) return 'there';
  const raw = email.split('@')[0].replace(/[._-]+/g, ' ').trim();
  if (!raw) return 'there';
  const part = raw.split(/\s+/)[0];
  return part.charAt(0).toUpperCase() + part.slice(1);
}

export function initialsFrom(name: string, email: string): string {
  const source = name.trim() || email.split('@')[0];
  const parts = source.replace(/[._-]+/g, ' ').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}
