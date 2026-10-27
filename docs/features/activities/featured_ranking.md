# Activities — featured (hero) ranking

The Activities list shows one hero card at the top, then compact rows. The hero is **not** "whatever
the API returned first" — it is chosen deterministically by
[`selectFeatured`](../../../mobile/lib/features/activities/data/featured_ranking.dart), a pure
function that takes the list and the current time and returns the pick plus the reason it won.

## Eligibility

Only **upcoming, non-cancelled** activities compete. Past events and anything flagged
`is_cancelled` are dropped before scoring. An empty eligible pool yields no hero (`null`).

## Signals

Each eligible activity gets a base score in `[0, 1]` from three bounded, weighted signals:

| Signal | Weight | Intuition |
| --- | --- | --- |
| **Timing** | 0.45 | Sooner events rank higher, via smooth exponential decay (`exp(-hours / 72)`) — no cliff, trends toward what's actually coming up. |
| **Scarcity** | 0.20 | An event near capacity is urgent and socially proven. A *full* one scores low (0.1) — featuring it is a dead end. Unlimited capacity is neutral (0.3). |
| **Participation** | 0.35 | Head-count relative to the busiest event in the current pool, so a well-attended activity surfaces. |

## Fairness / discovery adjustments

- **Already joined:** `-0.15`. The hero slot favours discovery, so an event the viewer is already in
  is nudged down — never off the list, just behind an equally-ranked one they haven't seen.
- **Full:** `-0.20` (on top of the low scarcity score). Nobody new can act on a packed event, so it
  should not sit at the top advertising a closed door. It can still win if everything else ranks lower.
- **Ties:** exact ties break on `id` (smaller wins), so the pick is reproducible and never flickers
  between equal candidates regardless of input order.

## Honest label

The hero badge states *why* the card is featured rather than a blanket "Featured":

- **Filling up** — near capacity (≥ 70%) but not full.
- **Starting soon** — within 48 hours.
- **Popular** — 10+ participants.
- **Featured** — neutral fallback.

## Testability

`selectFeatured` is pure and takes `now` as a parameter, so ranking and labels are pinned with a
fixed clock in
[`featured_ranking_test.dart`](../../../mobile/test/features/activities/featured_ranking_test.dart).
The model fields it relies on (`is_cancelled`, `created_at`, `participantCount`, `maxParticipants`,
`hasJoined`) come straight from the backend `ActivityRead` payload.
