'use client';

import { useSearchParams } from 'next/navigation';
import { useEffect, useState } from 'react';
import PostsPanel from './PostsPanel';
import ResourcesPanel from './ResourcesPanel';

type Tab = 'posts' | 'resources';

function tabFromParams(value: string | null): Tab {
  return value === 'resources' ? 'resources' : 'posts';
}

export default function ContentPage() {
  const searchParams = useSearchParams();
  const [tab, setTab] = useState<Tab>(() => tabFromParams(searchParams.get('tab')));

  useEffect(() => {
    setTab(tabFromParams(searchParams.get('tab')));
  }, [searchParams]);

  return (
    <>
      <header className="ops-top">
        <div>
          <h1>Campus Hub</h1>
          <p>Publish posts and keep the campus resource directory up to date.</p>
        </div>
        <div className="seg-tabs" role="tablist" aria-label="Campus Hub sections">
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
      </header>
      <div className="content" style={{ paddingTop: 8 }}>
        {tab === 'posts' ? <PostsPanel /> : <ResourcesPanel />}
      </div>
    </>
  );
}
