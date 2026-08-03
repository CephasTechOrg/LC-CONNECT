import type { ServiceStatus } from '@/lib/api/client';

export type AdminMembership = {
  id: string;
  role: string;
  status: string;
  user_email: string;
  display_name: string | null;
};

export const ROLE_SHORT: Record<string, string> = {
  super_admin: 'Super Admin',
  school_admin: 'School Admin',
  honors_admin: 'Honors Admin',
  content_admin: 'Content Admin',
  auditor: 'Auditor',
};

export const AVATAR_TONES = [
  'tone-purple',
  'tone-orange',
  'tone-cyan',
  'tone-green',
  'tone-yellow',
] as const;

export function firstNameFromEmail(email: string | undefined): string {
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

export function formatCount(n: number | null | undefined): string {
  if (n == null) return '—';
  return n.toLocaleString('en-US');
}

export function Chevron() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="m9 6 6 6-6 6" />
    </svg>
  );
}

export function ApprovalDonut({
  positions,
  employers,
  opportunities,
}: {
  positions: number;
  employers: number;
  opportunities: number;
}) {
  const total = positions + employers + opportunities;
  const r = 70;
  const c = 2 * Math.PI * r;

  const segments = [
    { value: positions, color: '#6F42E8' },
    { value: employers, color: '#F4C542' },
    { value: opportunities, color: '#F08A5D' },
  ];

  let offset = 0;
  const arcs =
    total === 0
      ? null
      : segments.map((seg) => {
          const len = (seg.value / total) * c;
          const dash = `${len} ${c - len}`;
          const el = (
            <circle
              key={seg.color}
              cx="90"
              cy="90"
              r={r}
              fill="none"
              stroke={seg.color}
              strokeWidth="18"
              strokeLinecap="round"
              strokeDasharray={dash}
              strokeDashoffset={-offset}
            />
          );
          offset += len;
          return el;
        });

  return (
    <div className="dash-donut">
      <svg width="200" height="200" viewBox="0 0 180 180" aria-hidden>
        <circle cx="90" cy="90" r={r} fill="none" stroke="#F0ECF7" strokeWidth="18" />
        <g transform="rotate(-90 90 90)">{arcs}</g>
      </svg>
      <div className="dash-donut-label">
        <div className="dash-donut-value">{total}</div>
        <div className="dash-donut-caption">Items Awaiting Review</div>
      </div>
    </div>
  );
}

export function StatusRow({ name, value }: { name: string; value: ServiceStatus }) {
  const ok = value === 'operational';
  return (
    <div className="dash-status-row">
      <div className="dash-status-icon" aria-hidden>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#6F42E8" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="9" />
          <path d="M3 12h18" />
        </svg>
      </div>
      <span className="dash-status-name">{name}</span>
      <span className={`status-dot${ok ? '' : ' down'}`} />
      <span className={`dash-status-value${ok ? '' : ' down'}`}>{ok ? 'Operational' : 'Down'}</span>
    </div>
  );
}
