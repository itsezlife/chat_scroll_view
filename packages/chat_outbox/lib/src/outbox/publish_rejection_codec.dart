/// The reason code a publish job journals when the chat's publisher refuses
/// a message, and the failure the message reads back from it.
///
/// The engine keeps a publish-stage failure as an opaque string code, in
/// its journal, so the code is what a restart reads too. The engine's own
/// reasons (`network`, `cancelled`, `publisherError`, …) share that space,
/// so every code of the chat's publisher carries the `chat.` prefix: a
/// server's rejection code reads back as that rejection whatever it spells,
/// never as an engine reason of the same name.
///
/// | Failure | Code |
/// | --- | --- |
/// | `rejected(reason)` | `chat.rejected:<reason>`, the host sender's code as given |
/// | `denied(action)` | `chat.denied:<action>`, the `CapabilityAction`'s name |
/// | the conflict loop ran out | `chat.conflict`, read as `rejected(chat.conflict)` |
/// | `tooLarge` | `tooLarge`, the code a preparer or publisher gives for content over the server's size |
library;

import 'dart:convert';

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_outbox/src/message/outgoing_status.dart';
import 'package:meta/meta.dart';

/// An outgoing message's publish failure to its journaled reason code and
/// back; see the library docs for the format.
@internal
final class PublishRejectionCodec extends Codec<OutgoingFailure, String> {
  /// The codec.
  const PublishRejectionCodec();

  /// The code of a message whose conflict loop ran out.
  static const String conflictCode = '${_Key.prefix}conflict';

  /// Whether [code] is one of the chat publisher's, which [decoder] reads.
  static bool owns(String code) =>
      code.startsWith(_Key.prefix) || code == _Key.tooLarge;

  @override
  Converter<OutgoingFailure, String> get encoder => const _Encoder();

  @override
  Converter<String, OutgoingFailure> get decoder => const _Decoder();
}

abstract final class _Key {
  static const prefix = 'chat.';
  static const rejected = '${prefix}rejected:';
  static const denied = '${prefix}denied:';
  static const tooLarge = 'tooLarge';
}

final class _Encoder extends Converter<OutgoingFailure, String> {
  const _Encoder();

  @override
  String convert(OutgoingFailure input) => switch (input) {
    OutgoingFailure$Rejected(:final reason) => '${_Key.rejected}$reason',
    OutgoingFailure$Denied(:final action) => '${_Key.denied}${action.name}',
    OutgoingFailure$TooLarge() => _Key.tooLarge,
    OutgoingFailure$Network() ||
    OutgoingFailure$SourceLost() ||
    OutgoingFailure$Unknown() => throw ArgumentError.value(
      input,
      'input',
      'Not a publisher\'s failure',
    ),
  };
}

final class _Decoder extends Converter<String, OutgoingFailure> {
  const _Decoder();

  /// Throws a [FormatException] for a code that is not the chat
  /// publisher's, or a denial whose action this build does not know.
  @override
  OutgoingFailure convert(String input) {
    if (input == _Key.tooLarge) return const OutgoingFailure.tooLarge();
    if (input == PublishRejectionCodec.conflictCode) {
      return const OutgoingFailure.rejected(PublishRejectionCodec.conflictCode);
    }
    if (input.startsWith(_Key.rejected)) {
      return OutgoingFailure.rejected(input.substring(_Key.rejected.length));
    }
    if (input.startsWith(_Key.denied)) {
      final name = input.substring(_Key.denied.length);
      for (final action in CapabilityAction.values) {
        if (action.name == name) return OutgoingFailure.denied(action);
      }
      throw FormatException('A denial names an unknown "action".', input);
    }
    throw FormatException('Not a code of the chat publisher.', input);
  }
}
