# ADR 048: Outgoing messages

A message the user sends is an **outgoing message** until the server
confirms it. A new portable package, `chat_outbox`, turns a planned send or
a text into one mpx publish job, shows the message at once as a row after
the newest server message, and reports its status to the bubble and the
host's time pill. The row's id is a position in the **provisional tail**,
not the message's identity; when an incoming message takes that position,
one engine operation, `rebaseTail`, moves the tail in a single frame with
its row state. The outbox keeps no store: the publish job's journal is the
truth, so a restart, a cancel, a failure and a retry all read from it.

**Status**: Accepted (2026-11-26, maintainer; decided in the
message-media-transfers map, tickets 10, 11, 12 and 18, revised by ticket
24, the first acceptance pass, ticket 25 and the second acceptance pass)  
**Date**: 2026-11-26  
**Relates to**: [ADR 001](001-message-id-scheme.md) (amended: provisional tail positions),
[ADR 020](020-package-topology.md) (amended: `chat_outbox`),
[ADR 039](039-streaming-message-body.md) (host-owned identity of a row),
[ADR 046](046-media-picker.md) (the send plan),
[ADR 047](047-message-media.md) (upload state in cells, appearance policy, send origin),
[ADR 049](049-chat-capabilities.md) (slow mode, limits, server denials),
mpx ADR 0012 (transfers and publish jobs)

Spec: `.scratch/chat-outbox/spec.md`, with research and per-value
provenance in `.scratch/message-media-transfers/research/` (04, 05, 16, 17,
18).

## Context

The chat could draw message media and mpx could run a durable publish job,
but nothing put a sent message in the list, kept it there while it
uploaded, or survived a restart. The engine's scroll ids are sequential per
conversation (ADR 001), so an outgoing row cannot take a temporary negative
id or be renamed when the server answers. Sending at the next id and asking
the server to accept it only if it is still next works until a peer's
message lands on that id first: then the user's bubble is overwritten in
place. Moving the outgoing rows with the data source's public calls costs a
staged-removal dance, pulls a reader who scrolled up down to the tail,
cancels a pinned scroll animation, can be overwritten by a range fetch, and
leaves selection on the wrong message.

## Decided

### Package

| Area | Decision |
| ---- | -------- |
| Home | `chat_outbox`, depending on `mpx_transfer`, `mpx_core`, `attach_model`, `content_model`, `chat_capabilities` and the root `chat_scroll_view` (for `rebaseTail`). The root never depends on it. |
| Does | Accepts a planned send or text and issues its media item ids (client message id plus item index, unless the host issues its own); checks slow mode and limits before creating a job (a refusal reaches `onDenied` and creates no job) and marks slow mode pending while a send is in flight; creates one publish job per planned send; allocates and rebases row ids; exposes status, cancel, retry, delete, the restart query, a lookup by client message id and a one-shot "fresh outgoing" flag; registers the host's `OutgoingMessageSender` as publisher `chat.send`; forwards the send origin. Payloads are bytes through a host codec. The chat does not use the job's hold and commit. |
| Not in | `message_media` (a display-only host must not inherit the transfer plugin), the engine (it gains only `rebaseTail`), `attach_model` (a pure model), hosts (each would re-solve rebase, restart and conflict). |

### Ids

| Area | Decision |
| ---- | -------- |
| Provisional tail | Outgoing rows sit after the newest server message at `tip+1 … tip+k`. Their ids are positions. Sending rows keep creation order among themselves; failed rows sink to the bottom, so a failed message always sits at the bottom of the chat. |
| Identity | The host's `clientMessageId`, as for a streamed reply (ADR 039). The host matches a server echo through the outbox's lookup by it and inserts no twin. |
| Strategies | Behind an `allocate` / `rebase` seam, both shipped: `SequentialServerIds` (accept-if-next, with `rebaseTail` when an incoming message takes `tip+1`) and `LocalIds` (host-local sequential ids, the server id kept in the host's model). Under both, an incoming message lands above the sending rows; a host flag may append it at the end under `LocalIds`. A host may supply its own. |
| Proposed id | Sent only at publish, after the uploads: the next server id, `tip+1`, not the row's position. On publish `rebaseTail` puts the publishing row at `tip+1` and moves failed rows above it to below it. |
| Sender | The host's sender returns `OutgoingSendResult(serverMessageId, serverKeys, payloadAsStored)`, `reuploadItems(ids)` (an expired server reference: the engine re-uploads those items once), a conflict, or a rejection; the outbox always uses the `wholeJob` failure policy (an album fails as a unit) and does not expose `perItem`; `payloadAsStored` feeds the rich-text reconcile ([ADR 034](034-rich-text-wire-and-persistence.md)). |
| Conflict | Handled inside the `chat.send` publisher: on "conflict, next id" it rebases and repeats the send within the same publish call, at most 3 times. Only `published` or a retryable rejection leaves it; nothing is re-uploaded. The engine's publish outcome stays generic. |
| Replay | An idempotent replay answered with another id: the outbox trusts the server and rebases the row to that id. |
| Idempotency | The job's idempotency key is the `clientMessageId`, created before the job (it is part of the tag) and passed in the request's optional key field. |
| Never reused | Applies to server-confirmed ids and to local ids. A provisional position under sequential server ids is a position the next message may take. |

### Engine: `rebaseTail`

One atomic data-source operation, media-agnostic:
`rebaseTail({required List<Object> order, List<IChatMessage> insert = const []})`.
`order` is the new order of the provisional rows' local identities (the
client message id keys), matched to rows through a host-supplied
`identityOf(message)`; `insert` are confirmed messages placed before the
tail.

| Guarantee | Meaning |
| --------- | ------- |
| Atomic | One write, one notification, one layout |
| Staging | No freed or reused id is left in removal staging |
| New order | Takes a new order of the provisional rows plus insertions: a reorder, not only a shift; inserted messages take the positions before them |
| Boundaries | Newest known id extends; the shifted range counts as the unconfirmed tail |
| Own mutation | Neither a self insert nor a removal: no pull to the tail for a reader scrolled up, no cancel of a pinned animation |
| Row state | Selection membership, the highlight and a running change transition follow the moved message; the host needs no global key |
| Text selection, menu | A moved row's text selection is cleared; an open message menu on it closes |
| Fetch | A range fetch never overwrites a provisional slot: rows it returns inside the tail go through `rebaseTail` (server rows before the tail, the tail shifted), never refused |

ADR 001 is amended: provisional tail slots are positions, not identity, and
`rebaseTail` is the only sanctioned move.

### States

| Area | Decision |
| ---- | -------- |
| Status | `preparing → uploading → publishing → sent`, or `failed(reason)`, or `cancelled`: a projection of the publish job plus the rebase step. `cancelled` is the outbox's own status, since the engine removes a cancelled job. Waiting for a publisher and every pause show as `uploading` or `publishing` by stage, so a system interruption keeps the stage it was in. A cancel after the server accepted is too late: the message stays sent. |
| Cells | Read upload state by the item's local key. The asset transfer state gains `sent` (upload finished, publish pending), reported until the alias to the server key applies; `message_media` draws the per-item check on it. |
| Time pill | The host's; reads the status: clock, then one check on sent. The second (read) check is server message status, drawn by the host. |
| Failed | Closed reasons: `network`, `rejected(reason)`, `denied(action)`, `sourceLost`, `tooLarge`, `unknown`. No media control, an error badge by the time, Retry and Delete in the message menu; a tap (a click on desktop) on the badge opens that menu as a `menu` interaction through the selection facade. Retry repeats only what failed. Failed rows keep creation order among themselves. |
| Semantics | Labels "sending", "sent", "not sent"; progress announced at start and end only; a failed message carries a retry action and hint. |
| Text | A text message is a job with no items, through the same outbox. |
| Denial | A server denial is `failed(reason: denied(action))` and reaches the host's `onDenied`. |

### Jobs, restart and ordering

| Area | Decision |
| ---- | -------- |
| No own store | The outbox projects the engine's publish jobs: tag `chat:<chatId>:<clientMessageId>`, payload the host's message model, ordering group the chat id. It watches a chat's jobs by the tag prefix `chat:<chatId>:`. |
| Restart | `pendingFor(chatId)` returns the chat's outgoing messages with status; each gets a fresh tail position; sending ones continue, failed ones wait for the user. |
| Ordering | A failed job does not hold its group. On retry it joins the end of the group and its message moves after the other sending rows. |
| Durability | Uploads are `system` by default; the OS envelope rules are mpx's. |

### Cancel and interruption

| Event | Effect |
| ----- | ------ |
| Cancel the message, or the cross on its only item | The job is cancelled; the row becomes Absent |
| The cross on one album item | That item drops; the rest publish (the cross is the owner's call) |
| The last item cancelled, no text | The outbox cancels the job and deletes the message (the job only reports that it has no items) |
| The system ends the envelope | The message stays sending and resumes in the foreground; the setting `deleteOnSystemInterruption` deletes instead |
| Cancel all from the transfer notification | Every outgoing message in the envelope is deleted |

### Appearance and send origin

| Area | Decision |
| ---- | -------- |
| Appearance | Per platform: Android slides the new row up from below at the tail (fade and scale elsewhere), iOS flies the media from the picker (without a send origin it uses the Android slide), desktop shows none. The whole-row animation is the host's, since it owns the row: the outbox's one-shot `isFreshOutgoing(id)` tells it a row is new. `message_media` flies media only and never moves the row. A text-only message appears as media does on its platform, with no flight. |
| Send origin | `attach_sheet` hands `MediaItemId → global thumbnail rect` with the planned send; the outbox keeps the origins and exposes a one-shot `takeSendOrigin(MediaItemId) → Rect?`, which `MessageMediaState(sendOrigin: outbox.takeSendOrigin)` takes as a function type declared in `message_media` (no edge either way; the host wires one line); the cell flies once in an overlay from that rect to its current rect, re-read every frame, so a tail rebase mid-flight does not break it. Without an origin the platform default applies. |

## Why

- Sequential scroll ids are the engine's adjacency and chunk model; reading
  the outgoing ids as positions keeps that model and still lets a peer's
  message take its rightful id.
- One engine operation fixes every defect of the public calls in one place;
  each host doing the same dance with remove, finalise and insert would
  repeat the known failures.
- The publish job already journals items, uploads and the idempotency key;
  a second store in the outbox would be a second truth after a restart.
- Keeping the outbox out of `message_media` keeps the transfer plugin off
  hosts that only display media.
- Keeping an interrupted message sending, rather than deleting it, does not
  lose the user's message because the OS ended a background window; the
  deleting behaviour stays one setting away.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Temporary negative ids | Land in the wrong chunk; adjacency is `id ± 1` |
| Renaming the row to the server id | ADR 001 forbids renumbering a message |
| A reserved high id range for outgoing rows | Breaks sequential adjacency to the newest message |
| Proposing the row's own position, with failed rows left in place | A failed row at the next id makes every later proposal conflict |
| A conflict outcome in the engine's publish answer | The answer stays generic; the conflict is the chat's and is retried inside its publisher |
| Accept-if-next with remove and re-insert on conflict, no engine change | Keeps the in-place overwrite by a peer message, the staged-id skip and the pull to the tail |
| A subclass writing silently | Loses the unconfirmed-tail protection and still lets a fetch overwrite a provisional row |
| An outbox store beside the job journal | Two truths after a restart |
| The outbox in `message_media` | Display-only hosts would inherit the transfer plugin |
| The outbox in each host | Every host re-solves rebase, restart and conflict |
| Deleting a message the system interrupted, by default | Loses the user's message for a reason outside their control; kept as a setting |

## Consequences

- `chat_outbox` joins the root `workspace:` list; ADR 020 gains its row
  and its edges to the root package and `mpx_core` (amendment). It depends
  on `chat_capabilities` (ADR 049).
- mpx's transfer engine gains an optional idempotency key on the publish
  request and a tag-prefix job filter; `mpx_core`'s asset transfer gains
  `sent` (mpx ADR 0012).
- The root package gains `ChatDataSource.rebaseTail`, its mutation and the
  fetch protection of provisional slots; nothing else in the viewport
  changes.
- ADR 001 gains an amendment: provisional tail positions.
- `message_media`'s reserved pieces (ADR 047) are wired: upload state in
  cells, the per-item check, the appearance policy, the send origin in
  `MessageMediaState`.
- Hosts supply `identityOf`, an `OutgoingPayloadCodec<M>` and the sender,
  register `OutgoingMessageSender` at app start, match the server's echo of
  their own messages through the outbox's lookup, draw the time pill and
  the error badge, and animate a fresh outgoing row.
- Unverified reference behaviours (failed messages at the bottom; a re-sent
  message moving to the bottom) are checked in implementation issues.
- Glossary: *Outgoing message*, *Outbox*, *Provisional tail*, *Tail
  rebase*, *Send origin* in the Chat Scroll glossary.
