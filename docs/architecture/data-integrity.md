# Data integrity, concurrency and caching

How LC Connect keeps data correct when many requests touch the same rows at once, and how it
caches without showing stale or wrong data. Read this before writing code that changes a count, a
membership, a "one per person" row, or anything a second device or a double tap could race.

## 1. Transactions

- **One session per request.** `get_db` (`app/database.py`) opens an `AsyncSession` that the
  request handler, its dependencies (`get_current_user`) and the services it calls all share.
- **Isolation is Postgres's default, READ COMMITTED.** Each statement sees what was committed
  before it started. Two transactions can both read "no row yet" and both insert. Nothing in
  READ COMMITTED stops that by itself; the patterns below do.
- **Services commit.** A service ends its unit of work with `await db.commit()`. Locks taken with
  `FOR UPDATE` are held until that commit, so keep the work between lock and commit short and free
  of network calls (uploads, pushes, HTTP).
- **`expire_on_commit=False`.** Objects stay readable after commit. A *rollback* still expires
  them, and touching an expired attribute in async code raises `MissingGreenlet`. Hence the next
  rule.
- **Never `db.rollback()` to recover inside a request — use a savepoint.**

  ```python
  try:
      async with db.begin_nested():   # SAVEPOINT
          db.add(row)                  # flushed on exit
  except IntegrityError:
      row = await load_the_winner(db)  # only the savepoint rolled back
  ```

  A full rollback throws away the caller's other changes and expires `current_user`. Examples:
  `persist_message_idempotent`, `connections/router._match_for`, `runtime.emit_notification`.

- **Side effects after commit.** Live frames, pushes and emails go out *after* the commit, so
  nobody is told about data that then rolls back. The cost: a crash between commit and publish
  loses that one notification. If that ever matters (payments, audit), use a transactional
  outbox: write an `outbox` row in the same transaction and have a worker publish it.

## 2. Choosing a concurrency tool

| Situation | Tool | Where it is used |
|---|---|---|
| "At most one row per X" (a reaction per person, a member per group, a check-in per session) | A **unique constraint** plus an **upsert** (`INSERT … ON CONFLICT`) or **savepoint + catch** | `uq_message_reaction_user` + `ON CONFLICT DO UPDATE` (reactions); `uq_attendance_record_session_student` + `ON CONFLICT DO NOTHING` (absent marking); `uq_messages_sender_client` (send idempotency) |
| "At most one *unread* row per X" | A **partial** unique index | `uq_notifications_unread_subject` (`WHERE read_at IS NULL`) |
| A limit that depends on a count (capacity, three pins, four images) | **Lock one stable row** (`SELECT … FOR UPDATE`), then count, then write | Group row for joins and capacity; activity row for joins; the *user* row for the three-pin cap; the post row for its images |
| Read-compare-write on one row (a "never backwards" boundary) | **Lock that row** first | `realtime/service._member_for` (read/delivery ticks) |
| Find-or-create with no natural unique key | **Lock the parent rows in a fixed order**, then find, then create | `ensure_staff_dm_conversation` locks both users by id |
| A state transition that must happen once (closing a session) | **Lock the row**, re-check the state, then act | `attendance/service.close_session` |

Rules of thumb:

- **Lock something that already exists.** Locking the rows you are about to count does not
  serialize against a row someone else is about to *insert*. The three-pin cap locks the user, not
  the pinned rows, for exactly this reason.
- **Take the lock before you read what you will decide on.** `join_group` locks the group *before*
  reading the membership, so a second tap waits and then sees the first.
- **Lock in a consistent order** when you lock more than one row, or two requests can deadlock.
- **Do slow work outside the lock.** Campus post images are processed and uploaded first, then the
  post is locked and the count re-checked. If it is now full, the uploaded file is deleted.
- **Counters are never stored.** Member counts, participant counts and unread counts are
  `COUNT(*)` at read time, so there is no `x += 1` to drift. If a count ever has to be stored for
  speed, update it with a single statement (`UPDATE … SET n = n + 1`), never read-then-write in
  Python.
- **Idempotency keys for retries.** A client resend carries the same `client_message_id`. The
  unique index turns the second insert into "return the first row". It is scoped to the
  conversation, so a reused id in another chat is a 409, not a leak.

### Proving it

Each guarantee has a test that runs the race for real: two sessions from the `sessions` fixture,
started together with `asyncio.gather` (see `tests/db/test_integrity_fixes.py`,
`test_inbox_controls.py`, `test_activities.py`). A fix without a test that fails before it is a
guess.

## 3. Reads at scale

- **No N+1.** List endpoints load related rows in one query (`IN (…)`) and join in Python. The
  thread list, group lists, connection requests and recipient search all do this.
- **One row per group: `LATERAL … LIMIT 1`, not `DISTINCT ON`.** The inbox's latest message per
  chat is an index probe per conversation (`ix_messages_conversation_created_id`). `DISTINCT ON`
  sorted every message of every chat.
- **Every list is bounded.** Paged with `limit`/`offset` or a keyset cursor
  (`(created_at, id) < (…)`). Keyset is preferred where order is by time, because offset pages
  shift when new rows arrive.
- **Search escapes wildcards.** User text goes through `shared/text_search.like_pattern`, so `%`
  and `_` are literal. Message search is a substring match within the user's own chats. If
  message volume grows, add a `pg_trgm` GIN index on `messages.body`; the query does not change.

## 4. Caching

### What is cached today, and how it is invalidated

**Server.** Almost nothing is cached on the server, on purpose. Postgres answers every query from
memory at this size, and a cache that is never stale is one that does not exist.

| Cache | Lifetime | Invalidation |
|---|---|---|
| Policy documents (`@cache`) | process | `clear_cache` when the policy version changes |
| Supabase JWKS | TTL | refetched on expiry or an unknown key |
| `GET /policies` | `Cache-Control: max-age=3600` | versioned documents |
| Rate-limit buckets | rolling | Redis when configured, else per process |

**App (Riverpod).**

| Pattern | Use for | Invalidation |
|---|---|---|
| A provider that is never disposed | the signed-in user's own data (profile, threads, notifications) | `ref.watch(authNotifierProvider.select((a) => a.value?.id))`, so it resets when the *user* changes, not on every auth refresh; mutations write the new state directly |
| `cacheFor(ref, window)` on an `autoDispose` provider | lists you leave and come back to (groups, participants) | dropped `window` after the last listener; explicit `invalidate` after a mutation |
| `.cached()` instead of `.when()` | every screen | keeps the last value on screen while a refresh runs (stale-while-revalidate) |
| `keepFresh` | data that must catch up after the app was in the background | re-fetches on resume and on socket reconnect |
| Realtime frames | inbox, reactions, presence, notifications | applied to the cached state as they arrive, so most screens never refetch |
| Disk: chat tail, drafts | instant first paint of a chat | versioned format; wiped on sign-out |
| Images: `CachedNetworkImage` | avatars, banners | public files have content-versioned URLs (`?v=`), so a new image is a new key |
| Private images (signed URLs) | the Blueprint headshot | `cacheKey` = owner + upload time, in a separate cache wiped on sign-out; the signed URL is only the transport |

### Rules for adding a cache

1. **Name the key from what changes the data.** A headshot's key is its upload time, not its URL.
   A list's key is its filter.
2. **Know every writer.** List each code path that changes the data, and make each one invalidate
   or overwrite the cache entry. If you cannot list them, do not cache.
3. **Bound staleness.** Every cache has a TTL even when it is invalidated explicitly. That is the
   safety net for the writer you forgot.
4. **Show stale data, never wrong data.** Old data during a refresh is fine (`.cached()`).
   Another user's data never is: key per user, and clear on sign-out.
5. **Never cache an authorization decision** longer than a request. Blocks, removals and
   disconnects take effect immediately (and revoke live subscriptions).

### When Redis arrives

Redis is already optional: the event bus, rate limits and attendance QR challenges use it when
`REDIS_URL` is set. Before running more than one API instance, these per-process pieces must
move to it:

- **Presence** (`realtime/presence.py`): socket counts and pending "offline" timers. Use a key per
  user with a TTL refreshed by heartbeats.
- **"Is the user online?" before a push** (`runtime.schedule_offline_push`): read the same key.
- **Attendance QR challenges**: already Redis-backed when configured; the in-memory fallback
  returns 410 for valid codes across instances.

If a server data cache is ever needed (for example the inbox under heavy load), use cache-aside:

1. Read: `GET inbox:{user_id}`. On a miss, query Postgres, then `SET inbox:{user_id} … EX 60`.
2. Write: after the commit, `DEL` every key the write affects. Inbox keys go for every member of
   the conversation.
3. Fan the deletion out with `event_bus.publish_control({'event': 'cache.invalidate', 'keys': [...]})`,
   so any per-process copies drop too.
4. Keep the TTL short, so a missed `DEL` heals itself within a minute.

Delete on write rather than update on write: two writers updating a cache can land out of order,
while a delete followed by a re-read always converges.

## 5. Checklist for a change that writes data

- [ ] What happens if this request runs twice at the same moment (double tap, two devices, retry)?
- [ ] What happens if it runs twice in a row (retry after a timeout)? It should be idempotent.
- [ ] Is there a unique constraint that encodes the invariant, so the database refuses a duplicate
      even if the code is wrong?
- [ ] Is every count read at query time, or updated in a single SQL statement?
- [ ] Are locks taken before the read they protect, in a consistent order, with no network call
      inside?
- [ ] On an `IntegrityError`, does only a savepoint roll back?
- [ ] Which caches hold this data, and does this write invalidate each of them?
- [ ] Is there a test that runs the race on two sessions and fails without the fix?

## 6. Hosting note

The first request after the API has been idle can take many seconds on a plan that sleeps idle
instances. The app hides this (it holds data on screen, delays the offline banner, and retries
sends). The cure is hosting: an always-on instance, or a scheduled health check that keeps it
warm.
