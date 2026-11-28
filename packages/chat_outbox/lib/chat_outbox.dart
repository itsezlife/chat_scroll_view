/// The chat outbox: a message the user sends is an outgoing message, shown
/// at once as a row after the newest server message, until the server
/// confirms it.
///
/// `ChatOutbox` sends a planned send or a text as one publish job, after
/// the chat's slow mode and limits let it through, reads each message's
/// status from its job, answers the host's lookups (the outgoing message by
/// its client message id, whether a row is fresh) and describes what it
/// holds for a debug panel; `OutgoingMessage` and `OutgoingStatus` are what the
/// host's bubble and time pill read; the host supplies an
/// `OutgoingPayloadCodec` for its message model.
library;

export 'src/diagnostics/outbox_debug_snapshot.dart';
export 'src/diagnostics/outbox_op.dart';
export 'src/ids/local_ids.dart';
export 'src/ids/outgoing_id_strategy.dart';
export 'src/ids/sequential_server_ids.dart';
export 'src/message/outgoing_message.dart';
export 'src/message/outgoing_payload_codec.dart';
export 'src/message/outgoing_status.dart';
export 'src/outbox/chat_outbox.dart';
export 'src/send/outgoing_send_item.dart';
export 'src/transfers/outbox_transfers.dart';
