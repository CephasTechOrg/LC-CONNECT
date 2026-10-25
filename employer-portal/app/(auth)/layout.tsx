import Image from 'next/image';
import type { ReactNode } from 'react';
import './auth.css';

/** Every employer sign-in step (sign in, apply, reset, invite) sits beside the same brand panel. */
export default function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <div className="auth-split">
      <aside className="auth-brand">
        <div className="auth-brand-head">
          <div className="auth-brand-mark">
            <Image src="/lclogo.png" alt="Livingstone College" width={40} height={40} priority />
          </div>
          <div>
            <div className="auth-brand-name">Blueprint Bond</div>
            <div className="auth-brand-portal">Employer partner portal</div>
          </div>
        </div>
        <div className="auth-brand-copy">
          <h2>Meet Livingstone College’s Presidential Scholars.</h2>
          <p>Browse the profiles scholars choose to share, and post opportunities reviewed by the Honors Program.</p>
        </div>
        <div className="auth-brand-foot">Powered by LC Connect · Livingstone College</div>
      </aside>
      <main className="auth-main">{children}</main>
    </div>
  );
}
