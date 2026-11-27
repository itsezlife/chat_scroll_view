# Chat Capabilities

What the user may do in one chat, as the chat packages see it: an outcome
for each action and, when denied, why. The host resolves its backend's
rights into this value; the packages only read it, draw their controls'
denied forms and hand feedback back to the host. Covers the pure-Dart
`chat_capabilities` leaf.

Decisions: [ADR 049](../adr/049-chat-capabilities.md).

## Language

**Chat capabilities**:
One immutable value per chat that says, group by group (sending, write access, slow mode, protection, limits, and later groups), what the user may do there. Carries outcomes and reasons, never a backend's protocol flags. No value means everything is allowed.
_Avoid_: Permissions, rights (for the resolved value), chat flags, banned rights

**Capability**:
One action's outcome in the **chat capabilities**: allowed, or denied with a **denial reason**. Carries no text.
_Avoid_: Permission, flag, enabled bool

**Denial reason**:
Why a **capability** is denied: for everyone in the chat, for this user (until a time or for good), lifted by something the user can do (an opaque host kind), or another host reason; a package adds two of its own, no write access (a replacing input row) and a send held behind a message still sending. The host picks the feedback text from it.
_Avoid_: Error, ban type, restriction message

**Protection**:
The group of the **chat capabilities** that keeps content in the chat: whether copy, forward and save are allowed and whether screen capture is blocked, for the chat, with a message's own flag added on top by the caller, since the chat's value knows no messages. It changes live: menus and the viewer lose their entries at once.
_Avoid_: No-forwards, copy restriction, DRM, secure mode

**Slow mode**:
The group of the **chat capabilities** that allows one send unit per interval (an album is one unit): the interval, when the next send is allowed, and whether a message is still sending. Read by the composer's countdown and the picker's one-send rule.
_Avoid_: Rate limit, cooldown, throttle

**Capability action**:
What the user attempts, named for feedback: sending text, each media kind, stickers, link previews, polls, inline results, sending now (slow mode), copy, forward, save. Stable names. Screen capture is a flag of **Protection**, not an action.
_Avoid_: Chat action (reads as a typing status), permission name

**Capability feedback**:
The host's two hooks, passed beside the **chat capabilities**: the text a package draws in place for a denied control (none means the package's silent form) and the report that the user attempted a denied action, which the host shows as a tooltip, toast or bulletin. Packages never show their own denial text; every attempt is logged, with or without a hook.
_Avoid_: Denial toast, error handler
