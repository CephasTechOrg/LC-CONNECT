import Image from 'next/image';
import type { ReactNode } from 'react';
import './auth.css';

/** Every admin sign-in step (sign in, MFA, reset, invite) sits beside the same brand panel. */
export default function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <div className="auth-split">
      <aside className="auth-brand">
        <div className="auth-brand-head">
          <div className="auth-brand-mark">
            <Image src="/lclogo.png" alt="Livingstone College" width={40} height={40} priority />
          </div>
          <div>
            <div className="auth-brand-name">LC Connect</div>
            <div className="auth-brand-portal">Admin portal</div>
          </div>
        </div>
        <div className="auth-brand-copy">
          <h2>Everything that keeps LC Connect running, in one place.</h2>
          <p>Review posts, people and reports. Every admin account signs in with two-factor authentication.</p>
        </div>
        <div className="auth-brand-foot">Livingstone College · Salisbury, North Carolina</div>
      </aside>
      <main className="auth-main">{children}</main>
    </div>
  );
}
