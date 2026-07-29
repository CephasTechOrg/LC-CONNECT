'use client';

import { useState } from 'react';
import PostsPanel from './PostsPanel';
import ResourcesPanel from './ResourcesPanel';

type Tab = 'posts' | 'resources';

export default function ContentPage() {
  const [tab, setTab] = useState<Tab>('posts');

  return (
    <>
      <header className="topbar">
        <div>
          <h1>Content</h1>
          <p>Publish campus posts and maintain the resource directory</p>
        </div>
        <div className="tabs">
          <button
            type="button"
            className={`tab${tab === 'posts' ? ' active' : ''}`}
            onClick={() => setTab('posts')}
          >
            Posts
          </button>
          <button
            type="button"
            className={`tab${tab === 'resources' ? ' active' : ''}`}
            onClick={() => setTab('resources')}
          >
            Resources
          </button>
        </div>
      </header>
      <div className="content">{tab === 'posts' ? <PostsPanel /> : <ResourcesPanel />}</div>
    </>
  );
}
