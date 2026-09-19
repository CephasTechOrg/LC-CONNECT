"""Limits shared by the two paths a message can arrive on.

A message reaches the server over REST (`POST /messages/threads/{id}`, `PATCH /messages/{id}`) and
over the WebSocket (`message.send`). Both must agree on how long a body may be, or one path
accepts what the other rejects — and the difference only ever shows up as a message that sends
from one client state and fails from another.

It lives in `shared/` rather than in either feature because a feature must never import another
feature's module: `messages.service` reaching into `realtime.protocol` for this closed an import
cycle (realtime's package imports the messages service back).
"""

#: Longest message body, in characters, for both transports.
MAX_BODY_CHARS = 2000
