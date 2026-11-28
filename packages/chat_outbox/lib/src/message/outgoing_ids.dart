/// The chat an outgoing message goes to, by the host's id for it.
///
/// A nominal string: the outbox's every lookup takes a chat and a message,
/// both strings on the wire, and the types keep one from standing for the
/// other. The id is part of a publish job's tag (`chat:<chatId>:…`).
extension type const ChatId(String value) implements String {}

/// An outgoing message's identity: issued before its publish job, the job's
/// idempotency key, never reused, and never containing `:` (which separates
/// the parts of the job's tag).
///
/// The row's id in the chat is a position, not this: it moves with the
/// provisional tail, and the host matches the server's echo of the message
/// by this id, never by slot.
extension type const ClientMessageId(String value) implements String {}
