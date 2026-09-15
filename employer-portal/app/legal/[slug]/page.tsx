import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { marked } from 'marked';
import { policyDocument } from '@/lib/api/client';

/**
 * Public, unauthenticated policy pages.
 *
 * These exist because the App Store requires a **publicly reachable, human-readable** privacy
 * policy URL before a build can go to external TestFlight testers. The backend already serves
 * every policy as JSON at `/api/v1/policies/{slug}`, which satisfies the app but not a reviewer
 * or a student reading it in a browser.
 *
 * Hosted in the employer portal rather than the admin portal simply because this is the
 * externally-reachable deployment; nothing here is employer-specific.
 */

/** Mirrors `PUBLIC_POLICY_SLUGS` in `backend/app/shared/policy_versions.py`. An allowlist, not a
 *  passthrough — the backend keeps internal working documents in the same folder, and this route
 *  must never become a way to fetch one by guessing a filename. */
const PUBLIC_SLUGS = [
  'privacy-policy',
  'terms-of-service',
  'community-guidelines',
  'employer-agreement',
] as const;

// Rendered on first request and cached for an hour, NOT prerendered at build time. Prerendering
// would couple every deploy to the API being awake, so a momentary API blip would fail the whole
// build. A policy edit still reaches readers within the hour without a redeploy.
export const revalidate = 3600;

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  if (!PUBLIC_SLUGS.includes(slug as (typeof PUBLIC_SLUGS)[number])) return {};
  try {
    const doc = await policyDocument(slug);
    return { title: `${doc.title} · LC Connect`, description: `LC Connect ${doc.title}.` };
  } catch {
    return { title: 'LC Connect' };
  }
}

export default async function PolicyPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  if (!PUBLIC_SLUGS.includes(slug as (typeof PUBLIC_SLUGS)[number])) notFound();

  let doc: Awaited<ReturnType<typeof policyDocument>>;
  try {
    doc = await policyDocument(slug);
  } catch {
    // This URL is what the App Store holds on file, so it must never go dead. If the API is
    // unreachable, say so plainly and point at somewhere the text can still be read — a 404
    // here would read as "this app has no privacy policy".
    return (
      <main className="policy-shell">
        <header className="policy-head">
          <Link className="policy-back" href="/">
            LC Connect
          </Link>
        </header>
        <article className="policy-body">
          <h1>Temporarily unavailable</h1>
          <p>
            This document could not be loaded just now. Please try again in a moment, or email{' '}
            <a href="mailto:support@livingstone.edu">support@livingstone.edu</a> and we will send
            it to you directly.
          </p>
        </article>
      </main>
    );
  }

  // The source is our own markdown, committed in `docs/policies/` and served by our own API —
  // not user input — so rendering it as HTML is safe. `html: false` keeps it that way even if
  // that ever stops being true.
  const html = await marked.parse(doc.body, { gfm: true, breaks: false, async: true });

  return (
    <main className="policy-shell">
      <header className="policy-head">
        <Link className="policy-back" href="/">
          LC Connect
        </Link>
      </header>
      <article className="policy-body" dangerouslySetInnerHTML={{ __html: html }} />
      <footer className="policy-foot">
        <nav>
          {PUBLIC_SLUGS.filter((s) => s !== slug).map((s) => (
            <Link key={s} href={`/legal/${s}`}>
              {s.replace(/-/g, ' ')}
            </Link>
          ))}
        </nav>
        <p>Questions about this document? Contact support@livingstone.edu.</p>
      </footer>
    </main>
  );
}
