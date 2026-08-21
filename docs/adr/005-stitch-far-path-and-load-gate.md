# ADR 005: Stitch far path with navigation load-gate

Far `animateTo` is a continuity **illusion** (Telegram
`RecyclerAnimationScrollHelper`: capture → teleport → dual-translate), not
scrolling through the gap and not a viewport crossfade. Stitch runs only after
a **navigation load-gate** (target ready via a host **destination window**
fetch — never shimmer-stitch or contiguous gap-fill for readiness). Target and
outgoing strip stay **presence-pinned** for the wait and flight; tall rows use
**full-strip travel**. Day chrome follows destination-visible built rows during
the flight. Immediate vs prefer-built differ only in close-path chance for a
warming row — neither may timeout into force-stitch.

**Status**: Accepted  
**Date**: 2026-08-21
