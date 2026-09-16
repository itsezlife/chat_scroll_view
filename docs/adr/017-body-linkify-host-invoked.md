# ADR 017: Body linkify is host-invoked, not viewport paint

**Status**: Accepted  
**Date**: 2026-09-16  
**Relates to**: [ADR 013](013-viewport-owns-markdown-text-selection.md), [ADR 014](014-fenced-code-interaction-and-smooth-contour-highlight.md)

The chat viewport paints and activates **markdown links** already present in
the body (`inline hit` → `linkActivated`). It does **not** decide what counts
as a URL or mention, and it does not rewrite text during layout or rebuild.

**Body linkify** — turning bare `http(s)` / `www` and `@username` tokens into
markdown links — is a **host-invoked** transform. The host runs it at send and
at receive/materialize so optimistic and remote bodies stay consistent.
**Linkify policy** (combinable allowlist bits for token families, plus
fixed exclusion zones on shipped helpers) is caller-owned. Named bits and
convenience combinations may live as an opt-in helper next to the package
API so demos and apps share one implementation, but the scroll/paint path
must not call it.

Mentions are not a second **inline hit** kind: `@alice` rewrites to
`[@alice](mention:alice)`; the host branches on `Uri.scheme` from the existing
link activation channel. Default policy must not rewrite fenced code, inline
code, or existing `[…](…)` spans. **Link preview** (OG / title / favicon /
headless fetch) stays app- or backend-owned and is not viewport chrome.

## Considered options

- **Viewport auto-detects links on parse/build** — rejected: “what is a link”
  is product policy (schemes, false positives); wrong layer for portable paint.
- **Parallel text + entity offsets** — rejected while bodies are markdown;
  second source of truth for ranges vs selection/copy.
- **Separate mention / hashtag hit kinds on the facade** — deferred: same
  press chrome and policy gates as links; host URL schemes suffice for v1.
- **Host-invoked linkify + optional package helper; viewport unchanged** —
  accepted.
