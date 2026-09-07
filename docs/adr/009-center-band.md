# ADR 009: Center Band vs Anchor origin

Leave/reopen reading position is **Center Band** (`ChatCenterBand`: Message
ID + pixels from that message’s top to a fixed 50% paint-band ray), observed
and applied on [ChatScrollController]. **Anchor origin** remains the engine’s
only layout scroll state and is not the host persist/restore record.

**Status**: Accepted  
**Date**: 2026-09-07

## Decided

| Topic | Decision |
| ----- | -------- |
| Product intent | Leave/reopen restores **where the reader was looking**, not the layout Anchor origin |
| Geometry | Exact message intersecting a fixed **center-band ray** at 50% of the paint band (zero thickness; no host fraction/slab in v1) |
| Persist shape | `ChatCenterBand`: `messageId` + `offsetFromMessageTop` (px from message top → ray) |
| Live observe | Deferred `ValueListenable<ChatCenterBand?>` on [ChatScrollController] (same listener safety as `visibleRange`) |
| Apply | Package `jumpToCenterBand(messageId, offsetFromMessageTop)` — one layout operation; hosts MUST NOT compose `jumpTo` + `scrollBy` for this job |
| Naming | **Center Band** / `ChatCenterBand` / `jumpToCenterBand` — physical paint-band role; not “gaze”, not “Open Anchor”, not `*Restore` |
| Engine split | Anchor origin (`anchorMessageId`, `anchorPixelOffset`) stays engine-only layout; Center Band is the host-facing reading snapshot |
| Heuristic | Reject in-app `visibleRange` id midpoints — variable row heights make them wrong |
| Telegram | Inspiration for message + within-row offset / mid-band place; not a RecyclerView port |

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Persist layout Anchor origin as leave/reopen | Wrong product: origin ≠ visual center; tall/mixed heights feel wrong |
| Host-only heuristic from `visibleRange` | Cannot know which row crosses geometric center when heights vary |
| Host-composed `jumpTo` + `scrollBy` restore | Fragile under Warm History / first layout / tall rows; Telegram-style place is one op |
| Configurable center fraction or thick slab in v1 | Extra API + tie-breaks; mid-band ray matches the locked mid-screen intent |
| Rename / redefine Anchor origin to mean Center Band | Lies about today’s engine contract and confuses architecture docs |
| `*Restore` / “gaze” naming | Metaphor, not measured role; conflicts with physical naming house style |
| Expose full visible-row geometry for host-defined center policy | Premature; one package center policy keeps hosts simple |

## Consequences

### Positive

- Hosts can debounce-persist an exact leave point and reopen to the same within-message band.
- Anchor origin docs and Tier-1/Tier-2 math stay unchanged.
- Public surface stays on [ChatScrollController] beside `visibleRange` / `jumpTo`.

### Negative

- Package must compute and push Center Band from laid-out row rects (render work not free).
- `jumpToCenterBand` must settle through the same build/alignment lifecycle as other navigation when the target is not yet measured.

## Related

- Position / navigation constraints: [ADR 002](002-position-model.md)
- Coordinate model: [docs/architecture/01-coordinate-model.md](../architecture/01-coordinate-model.md)
- Navigation APIs: [docs/architecture/10-navigation-and-tail.md](../architecture/10-navigation-and-tail.md)
- Glossary: [CONTEXT.md](../../CONTEXT.md) (*Anchor origin*, *Center-band ray*, *Center Band*, *ChatCenterBand*)
