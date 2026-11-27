import 'package:chat_capabilities/src/capability/capability.dart';
import 'package:meta/meta.dart';

/// The sending group of the chat capabilities: what the user may send.
///
/// Every field defaults to allowed. A later field (the media kinds first)
/// arrives with an allowed default, so a host that never sets it keeps its
/// behaviour.
@immutable
final class SendingCapabilities {
  /// Sending rights; each omitted one is allowed.
  const SendingCapabilities({
    this.text = const Capability.allowed(),
    this.stickers = const Capability.allowed(),
    this.linkPreviews = const Capability.allowed(),
    this.polls = const Capability.allowed(),
    this.inline = const Capability.allowed(),
  });

  /// Plain text messages.
  final Capability text;

  /// Stickers, including the large emoji drawn as a sticker.
  final Capability stickers;

  /// A link preview on a sent message; denied means the message is sent
  /// without one.
  final Capability linkPreviews;

  /// Polls.
  final Capability polls;

  /// Results of inline queries.
  final Capability inline;

  /// A copy with the given rights replaced.
  SendingCapabilities copyWith({
    Capability? text,
    Capability? stickers,
    Capability? linkPreviews,
    Capability? polls,
    Capability? inline,
  }) => SendingCapabilities(
    text: text ?? this.text,
    stickers: stickers ?? this.stickers,
    linkPreviews: linkPreviews ?? this.linkPreviews,
    polls: polls ?? this.polls,
    inline: inline ?? this.inline,
  );

  @override
  bool operator ==(Object other) =>
      other is SendingCapabilities &&
      other.text == text &&
      other.stickers == stickers &&
      other.linkPreviews == linkPreviews &&
      other.polls == polls &&
      other.inline == inline;

  @override
  int get hashCode => Object.hash(text, stickers, linkPreviews, polls, inline);

  @override
  String toString() =>
      'SendingCapabilities(text: $text, stickers: $stickers, '
      'linkPreviews: $linkPreviews, polls: $polls, inline: $inline)';
}
