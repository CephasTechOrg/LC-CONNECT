# Architecture

How the system is built — the technical design docs.

| Doc | What it's for |
|-----|---------------|
| [`architecture.md`](./architecture.md) | System components, API areas, and data flows |
| [`database.md`](./database.md) | PostgreSQL schema — tables, relationships, indexes |
| [`realtime-messaging.md`](./realtime-messaging.md) | Real-time messaging end-to-end (WebSocket gateway, fan-out, dedup) |
| [`image_storage.md`](./image_storage.md) | Avatar/image storage — folders, replace-not-duplicate, sanitization |
| [`folder_structure.md`](./folder_structure.md) | Backend + mobile folder layout (feature-first) |

See also: [`../features/`](../features/) for feature deep-dives, [`../security/`](../security/) for the
security model.
