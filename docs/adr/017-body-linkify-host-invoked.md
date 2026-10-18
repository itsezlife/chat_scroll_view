# ADR 017: Entity detection is host-invoked, not viewport paint

**Status**: Accepted  
**Date**: 2026-09-16  
**Amended**: 2026-10-18 — body linkify as a markdown-string rewrite is retired and replaced by **entity detection**, a `content_model` transform over `RichText`; mentions are a second **inline hit** kind; `@username` is `Username`, not `Mention` (rows changed below; wire form in [ADR 034](034-rich-text-wire-and-persistence.md), inline hit kinds in [ADR 037](037-spoiler-and-mention-inline-styles.md))  
**Relates to**: [ADR 013](013-viewport-owns-markdown-text-selection.md), [ADR 014](014-fenced-code-interaction-and-smooth-contour-highlight.md), [ADR 034](034-rich-text-wire-and-persistence.md), [ADR 037](037-spoiler-and-mention-inline-styles.md)

The chat viewport paints and activates the links, mentions and hashtags a body
already carries (an **inline hit**, reported as a `ChatInlineHit` variant). It
does **not** decide what counts as a URL, a username or a hashtag, and it does
not rewrite or annotate text during layout, paint or rebuild.

**Entity detection** (`EntityDetection.apply(RichText, DetectionPolicy)` in
`content_model`) is a host-invoked transform: it adds link, `Username` and
`Hashtag` entities to a `RichText` where the text has the shape of one. It is
the single implementation behind the composer's send path, the host's receive
path and any server-side port. The scroll and paint path must not call it.

## Decided

| Area | Decision |
| ---- | -------- |
| Producers | Two, both host-invoked. **Send:** the host runs detection on the composer's `RichText` before `RichTextMarkdown.encode`, so the stored body carries the links every other viewer, notification and search sees. **Receive:** a decoded body with no link-class entity (link, mention, username, hashtag) runs through the same detection once, when the host builds the message model, and the result is cached with the model; a body that has any such entity is trusted and never re-detected. The server may detect and rewrite on ingest and is then the authority ([ADR 034](034-rich-text-wire-and-persistence.md)); nothing requires it. Loading a message for edit strips detected entities back to text, and saving re-detects. |
| Kinds | `link(url)` (a detected email is `link("mailto:...")`), `Username(name)` for a detected `@name` (spelled `[@name](username:name)`, plain text with no id, resolved by the host on tap) and `Hashtag(tag)` (spelled `[#tag](hashtag:tag)`). `Mention(id)` means a user the host resolved, is atomic, and detection never produces it. Not kinds: bot commands, cashtags, phone numbers, bank cards; a host that wants phone links detects `link("tel:...")` under its own policy. |
| Rules | Reference-client rules: a URL is an optional scheme from the policy plus a host that ends in a shipped TLD list (or `xn--`), trailing punctuation trimmed and brackets balanced, rejected right after `@`; a username is `@[A-Za-z0-9_]{1,32}` at the start, after whitespace or after `(`; a hashtag is `#` plus a non-digit plus word characters. Never inside `code`, `codeBlock`, an existing link, mention, username, hashtag or inline content; never splits an atom; spoilers do not block. At most 100 matches, and text over 20 480 characters is skipped. Linear and synchronous. |
| Policy | `DetectionPolicy` is caller-owned: which families count (`urls`, `usernames`, `hashtags`) and which URL schemes (default `http`, `https`). The package ships no universal definition of a URL beyond these rules. |
| Composer | Blind to link-class detection: no live underline, no entity while typing. `@` and `#` open **input queries** ([ADR 026](026-composer-model.md)); a pick inserts a real `Mention(id)` or `Hashtag`. Typed list-marker formatting is structural editing, not detection. |
| Inline hits | Links, mentions (`mention:` and `username:` targets, the hit saying which), hashtags and inline embeds are each their own **inline hit** kind with the same press chrome and policy gates. |
| Link preview | Host- or backend-owned (OG, title, favicon, fetch). A host may run detection with `urls` only on the composer text, debounced, to decide which URL to preview, and shows the result in the composer's header slot. Never viewport chrome. |

## Considered options

- **Viewport auto-detects on parse/build** — rejected: “what is a link” is
  product policy (schemes, false positives); wrong layer for portable paint.
- **Parallel text + entity offsets** — rejected: second source of truth for
  ranges versus selection and copy; entities live in `RichText`.
- **A markdown-string rewrite in the viewport package** (the former body
  linkify: bare `http(s)` / `www` and `@name` tokens rewritten to markdown
  links, `@alice` to `[@alice](mention:alice)`) — retired: it was a regex over
  markdown source, a parallel source of truth over fences and escapes, and it
  made `@name` a `Mention` without an id, so hosts and servers could not tell
  a forged id from a typed name.
- **Receive-time detection only** — rejected: stored bodies would stay raw,
  the opposite of the reference clients, whose stored entities are what other
  viewers receive.
- **One `Mention` kind with a resolved flag** — rejected: atomicity and trust
  differ between a resolved user and a typed name.
- **Host-invoked entity detection in `content_model`; viewport unchanged** —
  accepted.

## Consequences

- Detection is not free: hosts that never run it show bare URLs as text.
- The rewrite helper and its policy type are deleted from the viewport package.
