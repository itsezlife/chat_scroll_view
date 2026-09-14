# ADR 016: Cross-platform message menu request and presentation

**Status**: Accepted  
**Date**: 2026-09-14  
**Supersedes**: [ADR 004](004-host-presents-message-menu.md)

The host still presents the **message menu**; the viewport never owns the
overlay. What changes is the seam and the chrome.

The viewport emits a structured **message menu request** when a policy-owned
entry gesture wins on a present message **slot** (full row): under **selection
policy** `$Mobile`, **idle message tap**; under `$Desktop`, **secondary message
tap** (including while membership is non-empty for **over-selection**). The
packet carries id, slot rect, tap position, and viewport-known **hit context**
the host needs to choose rows:

- **message menu point state** — message-surface Inside vs slot Outside
  (host-reported bubble via `ChatMessageSurfaceBounds`; falls back to text
  body when unset). Registration keeps the mounted [RenderBox]; hit-tests
  resolve live global geometry so scroll without rebuild stays correct.
- **message menu membership** — idle / upon-selected / elsewhere
  (upon-selected is **over-selection**)
- `hasTextSelection` — whether the message is the live non-collapsed
  **text selection** subject (independent of tap-upon)
- live **text selection** range-upon at the tap (painted highlight rects;
  with a text snapshot when needed) — catalogs typically offer Copy Selected
  Text only when upon; neither Copy nor Copy Selected when subject has text
  but the press is not upon the range
- `selectUpToIds` — inclusive chain from nearest selected id to the tap id
  when membership is elsewhere and the combined set fits under
  `selectionCap` (otherwise null so the host omits Select up to)
- optional **inline hit** (link / code) when Inside and
  `resolveInlineHit` wins

Action and reaction catalogs remain host data per present. Album `GroupPart`,
photo/document Save menus, sticker packs, and other media forks stay later
extensions of the same packet, not a second seam.

**Message menu** is one product concept. **Message menu presentation** defaults
from selection policy (`$Mobile` → scrim sheet with undimmed slot; `$Desktop` →
light popup at the pointer with no viewport dim and no message outline lift).
The package ships both presentations behind one session contract (presence
watch, dismiss, optional IME freeze / pre-IME back where applicable); the host
may override presentation for a given present. Opening the menu does not clear
membership or text selection by itself; it must not run concurrently with an
active **span gesture**.

On desktop/web, Flutter’s built-in text context menu remains the default when
the host does **not** handle **secondary message tap**. When the host does
handle that seam (and typically presents a **message menu**), the engine must
not also show Flutter’s text menu on the same gesture — text-range actions then
belong in the message menu (driven by text overlap on the request). Hosts that
omit the secondary callback need no custom menu widget. Mobile **text selection
chrome** (handles / toolbar) stays as today and is not the message menu.

Rejected: splitting desktop into a separate “context menu” product; leaving
desktop popup entirely to the example when the host *does* opt in; keeping a
bare `(id, rect, tap)` seam while asking hosts to reconstruct over-selection
and text overlap; always suppressing Flutter’s text menu even when the host
never wired secondary; viewport-owned menu overlay (same rejection as ADR 004).
