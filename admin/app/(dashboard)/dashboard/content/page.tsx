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
          <p>Publish campus posts and maintain the resource directory.</p>
        </div>
        <div className="seg-tabs">
          <button type="button" className={`seg-tab${tab === 'posts' ? ' active' : ''}`} onClick={() => setTab('posts')}>
            Posts
          </button>
          <button
            type="button"
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
