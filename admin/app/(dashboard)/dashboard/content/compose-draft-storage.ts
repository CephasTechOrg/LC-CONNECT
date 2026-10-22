'use client';

/**
 * Persist an in-progress (unsaved) campus-post compose so leaving Campus Hub and coming back
 * restores the admin's text and queued photos. Text fields live in sessionStorage; queued photo
 * blobs live in IndexedDB (sessionStorage cannot hold File data). Everything is cleared the moment
 * the post is actually created on the server — after that the server draft is the source of truth.
 */

const FIELDS_KEY = 'lc-connect.campus-post-compose';
const DB_NAME = 'lc-connect.compose';
const STORE = 'pending-photos';
const PHOTOS_KEY = 'photos';

export type ComposeDraftFields = {
  kind: string;
  category: string;
  priority: string;
  audience: string;
  title: string;
  summary: string;
  body: string;
  externalUrl: string;
  expiresAt: string;
};

export type StoredPending = {
  localId: string;
  file: File;
};

export function loadDraftFields(): ComposeDraftFields | null {
  if (typeof window === 'undefined') return null;
  try {
    const raw = window.sessionStorage.getItem(FIELDS_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as ComposeDraftFields;
  } catch {
    return null;
  }
}

export function saveDraftFields(fields: ComposeDraftFields): void {
  if (typeof window === 'undefined') return;
  try {
    window.sessionStorage.setItem(FIELDS_KEY, JSON.stringify(fields));
  } catch {
    // Storage full or disabled — drafting is best-effort, never block composing.
  }
}

export async function clearComposeDraft(): Promise<void> {
  if (typeof window === 'undefined') return;
  try {
    window.sessionStorage.removeItem(FIELDS_KEY);
  } catch {
    // ignore
  }
  await writePending(null).catch(() => undefined);
}

export async function loadPendingFiles(): Promise<StoredPending[]> {
  const db = await openDb().catch(() => null);
  if (!db) return [];
  try {
    const value = await requestToPromise<StoredPending[] | undefined>(
      db.transaction(STORE, 'readonly').objectStore(STORE).get(PHOTOS_KEY),
    );
    return Array.isArray(value) ? value : [];
  } catch {
    return [];
  } finally {
    db.close();
  }
}

export async function savePendingFiles(files: StoredPending[]): Promise<void> {
  await writePending(files.length > 0 ? files : null).catch(() => undefined);
}

async function writePending(files: StoredPending[] | null): Promise<void> {
  const db = await openDb().catch(() => null);
  if (!db) return;
  try {
    const store = db.transaction(STORE, 'readwrite').objectStore(STORE);
    if (files) {
      await requestToPromise(store.put(files, PHOTOS_KEY));
    } else {
      await requestToPromise(store.delete(PHOTOS_KEY));
    }
  } finally {
    db.close();
  }
}

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    if (typeof indexedDB === 'undefined') {
      reject(new Error('IndexedDB unavailable'));
      return;
    }
    const open = indexedDB.open(DB_NAME, 1);
    open.onupgradeneeded = () => {
      if (!open.result.objectStoreNames.contains(STORE)) {
        open.result.createObjectStore(STORE);
      }
    };
    open.onsuccess = () => resolve(open.result);
    open.onerror = () => reject(open.error ?? new Error('IndexedDB open failed'));
  });
}

function requestToPromise<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('IndexedDB request failed'));
  });
}
