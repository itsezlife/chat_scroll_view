import 'package:attach_model/attach_model.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// Why a send is refused before its job is made: the action the host's
/// `onDenied` hears of, the reason, the rule that refused it (`sendNow` or
/// a limit's name, what diagnostics carry) and, for slow mode's countdown,
/// the wait left.
@internal
typedef SendRefusal = ({
  CapabilityAction action,
  DenialReason reason,
  String rule,
  Duration? remaining,
});

/// The checks a send passes before the outbox makes its job: slow mode,
/// then the chat's limits.
///
/// Slow mode lets one send unit through per interval, an album counting as
/// one: a send is refused as `sendNow` while the countdown runs or while a
/// message of the chat is still sending. The outbox reads the second from
/// its own jobs too, not only from the `pending` flag the host folds into
/// its capabilities, so a send right after another is refused even before
/// the host's value catches up.
///
/// A limit refuses the action of what breaks it, with
/// `DenialReason.other(<limit>)`: a text over `messageLength` as
/// `sendText`; a caption over `captionLength`, an album over `albumSize`
/// and an item over `fileSize` as the send action of the item concerned
/// (the album's first item for its size).
@internal
abstract final class SendCheck {
  /// The refusal of [send] under [capabilities] at [now], or null when it
  /// may go; [inFlight] is whether the chat has a message still sending.
  static SendRefusal? of(
    PlannedSend send,
    ChatCapabilities capabilities, {
    required DateTime now,
    required bool inFlight,
  }) =>
      _slowMode(capabilities.slowMode, now: now, inFlight: inFlight) ??
      _limits(send, capabilities.limits);

  /// The refusal of a retry under [capabilities] at [now], or null when it
  /// may go: slow mode alone, since a retried message passed the limits
  /// when it was sent, and a retry is one more send unit.
  static SendRefusal? ofRetry(
    ChatCapabilities capabilities, {
    required DateTime now,
    required bool inFlight,
  }) => _slowMode(capabilities.slowMode, now: now, inFlight: inFlight);

  static SendRefusal? _slowMode(
    SlowMode slowMode, {
    required DateTime now,
    required bool inFlight,
  }) {
    if (slowMode case SlowMode$Active(:final nextSendAt, :final pending)) {
      final remaining = slowMode.remainingAt(now);
      if (remaining > Duration.zero) {
        return (
          action: CapabilityAction.sendNow,
          reason: DenialReason.restricted(until: nextSendAt),
          rule: CapabilityAction.sendNow.name,
          remaining: remaining,
        );
      }
      if (pending || inFlight) {
        return (
          action: CapabilityAction.sendNow,
          reason: const DenialReason.sendPending(),
          rule: CapabilityAction.sendNow.name,
          remaining: null,
        );
      }
    }
    return null;
  }

  static SendRefusal? _limits(PlannedSend send, ChatLimits limits) {
    SendRefusal over(String limit, CapabilityAction action) => (
      action: action,
      reason: DenialReason.other(limit),
      rule: limit,
      remaining: null,
    );
    switch (send) {
      case PlannedSend$Text(:final caption):
        if (_codePoints(caption) > limits.messageLength) {
          return over(_messageLength, CapabilityAction.sendText);
        }
      case PlannedSend$Single(:final item, :final form, :final caption):
        if (_codePoints(caption) > limits.captionLength) {
          return over(_captionLength, actionOf(item, form));
        }
        if (_tooLarge(item, limits)) {
          return over(_fileSize, actionOf(item, form));
        }
      case PlannedSend$Group(:final items, :final form):
        if (items.length > limits.albumSize) {
          return over(_albumSize, actionOf(items.first, form));
        }
        for (final (index, item) in items.indexed) {
          if (_codePoints(send.captionOf(index)) > limits.captionLength) {
            return over(_captionLength, actionOf(item, form));
          }
        }
        for (final item in items) {
          if (_tooLarge(item, limits)) {
            return over(_fileSize, actionOf(item, form));
          }
        }
    }
    return null;
  }

  /// The action of sending [item] in [form]: a file or audio send by its
  /// form, a media send by the item's kind.
  static CapabilityAction actionOf(AttachItem item, SendForm form) =>
      switch (form) {
        SendForm.file => CapabilityAction.sendFile,
        SendForm.audio => CapabilityAction.sendAudio,
        SendForm.media => switch (item.kind) {
          AttachKind.photo => CapabilityAction.sendPhoto,
          AttachKind.video => CapabilityAction.sendVideo,
          AttachKind.animation => CapabilityAction.sendAnimation,
          AttachKind.audio => CapabilityAction.sendAudio,
          AttachKind.file => CapabilityAction.sendFile,
        },
      };

  // The limits' names, as `ChatLimits` calls them.
  static const _messageLength = 'messageLength';
  static const _captionLength = 'captionLength';
  static const _fileSize = 'fileSize';
  static const _albumSize = 'albumSize';

  static bool _tooLarge(AttachItem item, ChatLimits limits) =>
      switch ((item.facts.byteSize, limits.fileSize)) {
        (final size?, final limit?) => size > limit,
        _ => false,
      };

  // Lengths count code points, the unit of the chat's length limits.
  static int _codePoints(RichText? text) => text?.plain.runes.length ?? 0;
}
