'use client';

import { useSearchParams } from 'next/navigation';
import { useEffect, useState } from 'react';
import { PageHeader } from '@/components/admin-page';
import PostComposeForm from './PostComposeForm';
import PostsPanel from './PostsPanel';
import ResourcesPanel from './ResourcesPanel';
import type { Post } from './post-shared';
import './content.css';

type Tab = 'posts' | 'resources';

function tabFromParams(value: string | null): Tab {
  return value === 'resources' ? 'resources' : 'posts';
}

/** `'new'` for a fresh post, the post itself when editing, null when showing the list. */
type Composing = Post | 'new' | null;

export default function ContentPage() {
  const searchParams = useSearchParams();
  const [tab, setTab] = useState<Tab>(() => tabFromParams(searchParams.get('tab')));
  const [composing, setComposing] = useState<Composing>(null);
  const [flash, setFlash] = useState<string | null>(null);

  useEffect(() => {
    setTab(tabFromParams(searchParams.get('tab')));
  }, [searchParams]);

  // Writing a post is its own focused view, not a form wedged between the toolbar and the list:
  // the list steps aside while you write and comes back when you are done.
  if (composing) {
    return (
      <PostComposeForm
        key={composing === 'new' ? 'new' : composing.id}
        existing={composing === 'new' ? null : composing}
        onCancel={() => setComposing(null)}
        onSaved={(message) => {
          setComposing(null);
          setFlash(message);
        }}
      />
    );
  }

  return (
    <div className="page" style={{ gap: 32 }}>
      <PageHeader
        title="Campus Hub"
        subtitle="Publish posts and keep the campus resource directory up to date."
        action={
          tab === 'posts' ? (
            <button
              className="btn-primary"
              type="button"
              onClick={() => {
                setFlash(null);
                setComposing('new');
              }}
            >
              New post
            </button>
          ) : undefined
        }
      />

      <div>
        <div className="seg-tabs" role="tablist" aria-label="Campus Hub sections" style={{ marginBottom: 24 }}>
          <button
            type="button"
            role="tab"
            aria-selected={tab === 'posts'}
            className={`seg-tab${tab === 'posts' ? ' active' : ''}`}
            onClick={() => setTab('posts')}
          >
            Posts
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={tab === 'resources'}
            className={`seg-tab${tab === 'resources' ? ' active' : ''}`}
            onClick={() => setTab('resources')}
          >
            Resources
          </button>
        </div>
        {tab === 'posts' ? (
          <PostsPanel
            flash={flash}
            onEdit={(post) => {
              setFlash(null);
              setComposing(post);
            }}
            onCreate={() => setComposing('new')}
          />
        ) : (
          <ResourcesPanel />
        )}
      </div>
    </div>
  );
}
