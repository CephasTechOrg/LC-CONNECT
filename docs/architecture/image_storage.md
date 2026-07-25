# Image & Avatar Storage

How LC Connect stores profile and group pictures: **where** they live, **why there are no
duplicates**, and **how uploads are sanitized**. Backing code: [`app/shared/storage.py`](../../backend/app/shared/storage.py).

---

## 1. Where images live (organized by id)

Images go to **Supabase Storage** in a per-entity folder keyed by id:

| Image | Path |
|---|---|
| Profile picture | `profiles/{user_id}/avatar.jpg` |
| Group picture | `groups/{group_id}/avatar.jpg` |

So every user and every group has its **own folder**, and exactly **one** avatar object inside it.

---

## 2. Replace, never duplicate (no bucket leak)

The path is **deterministic** — always `avatar.jpg` for a given entity. On every upload the code:

1. **removes any prior avatar** at that prefix (covering old `jpg/jpeg/png/webp` extensions), then
2. writes the new image to `…/avatar.jpg`.

Result: updating a profile or group picture **replaces** the old one. Old images never accumulate as
orphans in the bucket — one entity, one file, forever.

---

## 3. Sanitized before storage

Uploaded bytes are never trusted or stored raw. `sanitize_avatar` (same path for profiles and groups):

- **validates the real image bytes** (not the spoofable `Content-Type` header),
- **strips EXIF/GPS** metadata (privacy — photos can carry location),
- **re-encodes to a clean JPEG**.

Only that sanitized output is stored. A byte-size cap (`MAX_PROFILE_IMAGE_MB`) is checked first, before
decoding. Uploading is rate-limited per user (see [`../security/rate_limiting.md`](../security/rate_limiting.md))
and, for groups, restricted to admins/owner.

---

## 4. URLs are public (correct for avatars)

Avatar URLs are **public** (`get_public_url`) with a `?v=<timestamp>` cache-buster so the client
image cache refreshes on update. Public is the right choice for display images — signing would break
CDN/image caching for content that's meant to be shown widely.

**Nuance:** a *private* group's avatar is therefore fetchable by anyone who has the exact URL (the path
contains the group id). This is the same behavior as profile pictures and is acceptable; the group's
*messages and member list* still require membership. Making private-group avatars access-controlled
would require signed URLs (at the cost of caching) and isn't currently done.
