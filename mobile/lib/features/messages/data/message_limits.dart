/// Client mirror of the server's `app/shared/message_limits.py`.
///
/// The server rejects a longer body on **every** path — REST send, WebSocket send, and edit — so a
/// client that lets one be typed produces a message that can never be delivered. Before this
/// constant existed the composer had no cap at all: a 2001-character message went optimistic, was
/// rejected, and settled as a red bubble whose Retry button could not succeed however many times
/// it was pressed. Capping input is the only place the number can be enforced without lying to
/// the user about what happened.
///
/// Keep in step with `MAX_BODY_CHARS`. The two cannot be shared across the language boundary, so
/// the client's job is to stay at or below the server's value — never above it.
const int kMaxMessageChars = 2000;
