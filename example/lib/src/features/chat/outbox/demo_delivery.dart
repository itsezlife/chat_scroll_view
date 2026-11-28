import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;

/// What the time pill of the user's own message shows.
///
/// The outbox says how far a message on its way got; once the server has
/// it, only the server knows whether a peer read it, so [read] is the
/// server's message status and never the outbox's.
enum DemoDelivery {
  /// Preparing, uploading or publishing: a clock.
  sending,

  /// The server has it: one check.
  sent,

  /// A peer read it: two checks.
  read,

  /// It failed: the error badge beside the time, which opens Retry and
  /// Delete.
  notSent;

  /// The spoken status: "sending", "sent" (read is still sent) or "not
  /// sent".
  String get label => switch (this) {
    sending => DemoOutgoingStrings.sending,
    sent || read => DemoOutgoingStrings.sent,
    notSent => DemoOutgoingStrings.notSent,
  };
}

/// The error badge of a failed message as a part of its bubble: a tap on
/// it (a click on desktop) is a `menu` body part, so the viewport opens the
/// message menu as it does for any message, with this part on the request.
///
/// [pointerKind] is the kind of the press that found the part, for the
/// `badgeMenuOpened` event.
@immutable
final class DemoErrorBadgePart {
  /// The badge of the message [messageId], found by a press of
  /// [pointerKind].
  const DemoErrorBadgePart(this.messageId, {required this.pointerKind});

  /// The message whose badge it is.
  final int messageId;

  /// The kind of the press that found it.
  final PointerDeviceKind pointerKind;

  @override
  bool operator ==(Object other) =>
      other is DemoErrorBadgePart &&
      other.messageId == messageId &&
      other.pointerKind == pointerKind;

  @override
  int get hashCode => Object.hash(messageId, pointerKind);
}

/// The operation of the `outbox` diagnostics events the demo's outgoing
/// bubbles emit.
enum DemoOutgoingOp implements DiagnosticOp {
  /// The error badge of a failed message opened its menu (debug): `pointer`
  /// is the press's kind (`touch`, `mouse`, …), with the chat, the client
  /// message id and the row's scroll id.
  badgeMenuOpened,
}
