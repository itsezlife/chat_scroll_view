/// The reason code a publish job journals when the chat's publisher refuses
/// a message, and the failure the message reads back from it.
///
/// The engine keeps a publish-stage failure as an opaque string code, in
/// its journal, so the code is what a restart reads too. Format:
///
/// | Failure | Code |
/// | --- | --- |
/// | `rejected(reason)` | `reason`, the host sender's code as given (never starting with `chat.`) |
/// | `tooLarge` | `tooLarge` |
/// | `denied(action)` | `chat.denied:<action>`, the `CapabilityAction`'s name |
/// | the conflict loop ran out | `chat.conflict`, read as `rejected(chat.conflict)` |
///
/// Codes starting with `chat.` are the outbox's own; a sender cannot give
/// one (`OutgoingSendAnswer.rejected`).
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

  @override
  Converter<OutgoingFailure, String> get encoder => const _Encoder();

  @override
  Converter<String, OutgoingFailure> get decoder => const _Decoder();
}

abstract final class _Key {
  static const prefix = 'chat.';
  static const denied = '${prefix}denied:';
  static const tooLarge = 'tooLarge';
}

final class _Encoder extends Converter<OutgoingFailure, String> {
  const _Encoder();

  @override
  String convert(OutgoingFailure input) => switch (input) {
    OutgoingFailure$Rejected(:final reason) => reason,
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

  /// Throws a [FormatException] naming the action for a denial whose action
  /// this build does not know.
  @override
  OutgoingFailure convert(String input) {
    if (input == _Key.tooLarge) return const OutgoingFailure.tooLarge();
    if (!input.startsWith(_Key.denied)) return OutgoingFailure.rejected(input);
    final name = input.substring(_Key.denied.length);
    for (final action in CapabilityAction.values) {
      if (action.name == name) return OutgoingFailure.denied(action);
    }
    throw FormatException('A denial names an unknown "action".', input);
  }
}
