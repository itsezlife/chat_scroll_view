import 'dart:convert';
import 'dart:typed_data';

/// The host's message model [M] to the bytes an outgoing message carries,
/// and back.
///
/// The outbox stores bytes only: they ride in the publish job's journal as
/// its opaque payload, so the outbox needs no model of its own and the
/// host's model survives a restart. The host's sender reads the payload when
/// it publishes, and the outbox decodes it when it reports a chat's pending
/// messages after a restart.
///
/// A `Codec` from `dart:convert`, so the host writes it as any codec of its
/// own: a const encoder and decoder, and `encode(M)` / `decode(bytes)` come
/// with it. The decoder throws a [FormatException] for bytes it cannot read
/// (a payload an older version wrote, say); the outbox reports that message
/// failed rather than dropping it.
///
/// The payload is user content: the outbox never puts it, its bytes or its
/// decoded model into a diagnostics event or a debug snapshot, only its
/// length.
abstract base class OutgoingPayloadCodec<M> extends Codec<M, Uint8List> {
  /// Const, so a host's codec can be.
  const OutgoingPayloadCodec();
}
