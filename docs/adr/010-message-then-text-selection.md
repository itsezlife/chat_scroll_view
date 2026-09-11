# ADR 010: Message selection precedes text selection

**Status**: Accepted  
**Date**: 2026-09-11

Chat list text selection follows Telegram Android order: a long-press always enters **message selection** first (even on body text). **Text selection** is allowed only on an already-selected message, and only for that one **text selection subject** (entering text selection collapses the selected set to that id).

On a selected message, long-press on body text **span-yields**; long-press outside body text may still start an **unselect span**. After yield, the host starts text selection programmatically at the global point (word/range + chrome) — the viewport does not hand the pointer to a child recognizer (ADR 003).

Exit is cause-split: dismiss text alone may leave the subject selected; successful copy/quote-style actions may clear message selection; leaving message selection always clears text selection.

## Considered options

- **Text-first long-press (span yield before any membership)** — rejected: contradicts Telegram chat (`checkTextSelection` requires selection background).
- **Hybrid text→messages morph across bubble edges** — rejected: mixes two products; not Telegram chat list behavior.
- **Cross-message character ranges in the chat list** — rejected for chat parity (article-style multi-body stays out of scope).
- **Message-then-text with programmatic entry after yield** — accepted.
