/// The one place chat and messaging route paths are spelled.
///
/// They used to be written inline at ten call sites across seven features, which is exactly why
/// moving chat out of the navigation shell needed a compatibility shim: no amount of care makes
/// ten string literals rename together. Anything that navigates to a conversation goes through
/// here, so the next move is one edit plus a redirect.
library;

/// The Messages tab — the conversation list (Chats).
const messagesPath = '/messages';

/// The Groups surface, a nested route under Messages rather than a query parameter, so back
/// behaviour is correct and the location is deep-linkable.
const groupsPath = '/messages/groups';

/// The recipient picker. Stays inside the shell: it is list-like, not a conversation.
const newMessagePath = '/messages/new';

/// A direct conversation.
///
/// Top level, outside the shell: a conversation is a full-screen surface and does not want the
/// bottom navigation bar over it (report #2). It also pushes top-level routes of its own — a
/// group sender's avatar opens `/users/:profileId` — and doing that from inside the shell is what
/// locked the navigator (`'!_debugLocked'`), which surfaced to users as the app signing out.
String dmChatPath(String addressingId) => '/chat/$addressingId';

/// A group conversation. Two segments, so it can never be read as a [dmChatPath] id.
String groupChatPath(String conversationId) => '/chat/group/$conversationId';

// ── legacy locations ─────────────────────────────────────────────────────────
//
// Kept as redirects for one release. Push payloads already delivered to devices, and deep links
// users have saved, still point at these — dropping them would strand a real notification tap on
// a 404-equivalent. Remove once no build older than the Chats|Groups release is in the field.

/// Was the DM conversation route, before chat left the shell.
const legacyDmChatPath = '/messages/:matchId';

/// Was the group conversation route, before chat left the shell.
const legacyGroupChatPath = '/messages/group/:conversationId';
