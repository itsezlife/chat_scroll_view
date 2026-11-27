import 'package:chat_capabilities/src/capability/capability.dart';
import 'package:chat_capabilities/src/feedback/capability_action.dart';
import 'package:chat_capabilities/src/flags/media_kind.dart';
import 'package:chat_capabilities/src/group/sendable_media.dart';
import 'package:meta/meta.dart';

/// The sending group of the chat capabilities: what the user may send.
///
/// Every field defaults to allowed. A later field arrives with an allowed
/// default, so a host that never sets it keeps its behaviour.
@immutable
final class SendingCapabilities {
  /// Sending rights; each omitted one is allowed.
  const SendingCapabilities({
    this.text = const Capability.allowed(),
    this.media = const SendableMedia(),
    this.stickers = const Capability.allowed(),
    this.linkPreviews = const Capability.allowed(),
    this.polls = const Capability.allowed(),
    this.inline = const Capability.allowed(),
  });

  /// Plain text messages.
  final Capability text;

  /// The media kinds the user may send, and why the others are denied.
  final SendableMedia media;

  /// Stickers, including the large emoji drawn as a sticker.
  final Capability stickers;

  /// A link preview on a sent message; denied means the message is sent
  /// without one.
  final Capability linkPreviews;

  /// Polls.
  final Capability polls;

  /// Results of inline queries.
  final Capability inline;

  /// Why these rights deny [action], or null when they allow it or
  /// [action] is not a sending right.
  ///
  /// `sendNow` is slow mode's and `copy`, `forward` and `save` are
  /// protection's, so they read null here.
  DenialReason? reasonFor(CapabilityAction action) => switch (action) {
    CapabilityAction.sendText => text.reason,
    CapabilityAction.sendPhoto => media.reasonFor(MediaKind.photo),
    CapabilityAction.sendVideo => media.reasonFor(MediaKind.video),
    CapabilityAction.sendAnimation => media.reasonFor(MediaKind.animation),
    CapabilityAction.sendFile => media.reasonFor(MediaKind.file),
    CapabilityAction.sendAudio => media.reasonFor(MediaKind.audio),
    CapabilityAction.sendVoice => media.reasonFor(MediaKind.voice),
    CapabilityAction.sendRoundVideo => media.reasonFor(MediaKind.roundVideo),
    CapabilityAction.sendSticker => stickers.reason,
    CapabilityAction.sendLinkPreview => linkPreviews.reason,
    CapabilityAction.sendPoll => polls.reason,
    CapabilityAction.sendInline => inline.reason,
    CapabilityAction.sendNow ||
    CapabilityAction.copy ||
    CapabilityAction.forward ||
    CapabilityAction.save => null,
  };

  /// A copy with [change] applied to each plain right: [text], [stickers],
  /// [linkPreviews], [polls] and [inline]. [media] is kept: its kinds are
  /// not plain capabilities.
  ///
  /// A host that lifts or imposes one reason on every right (an unlock, a
  /// ban) changes them in one place, and a right added later is covered
  /// without the host listing it.
  SendingCapabilities map(Capability Function(Capability right) change) =>
      SendingCapabilities(
        text: change(text),
        media: media,
        stickers: change(stickers),
        linkPreviews: change(linkPreviews),
        polls: change(polls),
        inline: change(inline),
      );

  /// A copy with the given rights replaced.
  SendingCapabilities copyWith({
    Capability? text,
    SendableMedia? media,
    Capability? stickers,
    Capability? linkPreviews,
    Capability? polls,
    Capability? inline,
  }) => SendingCapabilities(
    text: text ?? this.text,
    media: media ?? this.media,
    stickers: stickers ?? this.stickers,
    linkPreviews: linkPreviews ?? this.linkPreviews,
    polls: polls ?? this.polls,
    inline: inline ?? this.inline,
  );

  @override
  bool operator ==(Object other) =>
      other is SendingCapabilities &&
      other.text == text &&
      other.media == media &&
      other.stickers == stickers &&
      other.linkPreviews == linkPreviews &&
      other.polls == polls &&
      other.inline == inline;

  @override
  int get hashCode =>
      Object.hash(text, media, stickers, linkPreviews, polls, inline);

  @override
  String toString() =>
      'SendingCapabilities(text: $text, media: $media, stickers: $stickers, '
      'linkPreviews: $linkPreviews, polls: $polls, inline: $inline)';
}
