import 'dart:async';

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/secure_window.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart' as listen;

/// The operations of the `capabilities` diagnostics events the demo host
/// emits for protection.
enum ChatProtectionOp implements DiagnosticOp {
  /// Protection changed and the chat applied it (info): the `scope` (`chat`,
  /// or `message` with its scroll id), the protection `bits` now and what
  /// became of a `selection` holding a protected message (`kept`,
  /// `cleared`, or `none` when no selection held one).
  protectionApplied,

  /// Capture blocking changed (info): `on`, and whether the platform's
  /// secure flag was `applied` on this platform.
  captureBlocked,
}

/// The host side of a chat's **protection**, live: what may leave the chat
/// and what of it a message's own flag adds.
///
/// - [canCopy] is the selection facade's hook (`ChatSelectionController
///   .canCopy`), from `protection.forMessage` with the message's own flag
///   ([messageProtected]); [flagsOf] the same flags for the menus and the
///   selection bar.
/// - A change of the chat's protection tells the facade
///   ([ChatSelectionController.reapplyCanCopy]): the copy chrome and the
///   copy entries rebuild. A selection holding a protected message is
///   cleared under the desktop selection policy and kept elsewhere, where it
///   only loses its entries.
/// - `captureBlocked` sets the platform's secure flag ([setSecure]).
/// - [reportRefused] and [reportDenied] report an attempt through the chat's
///   [feedback], with the `selection` consumer.
///
/// Created and disposed with the chat screen.
final class ChatProtectionHost {
  /// Protection of [chatId]'s [capabilities] over [selection]; [feedback]
  /// reports attempts.
  ChatProtectionHost({
    required this.chatId,
    required this.capabilities,
    required this.feedback,
    required this.selection,
    required this.messageProtected,
    this.setSecure = _setSecureWindow,
  }) : _protection = capabilities.select((c) => c.protection) {
    _last = _protection.value;
    _protection.addListener(_onProtection);
    selection.canCopy = _hook;
    if (_last.captureBlocked) unawaited(_applyCapture(on: true));
  }

  /// The chat's id, on every event.
  final String chatId;

  /// The chat's capabilities.
  final listen.ValueListenable<ChatCapabilities> capabilities;

  /// Where an attempt is reported.
  final CapabilityFeedback feedback;

  /// The chat's selection facade.
  final ChatSelectionController selection;

  /// Whether the message with the given id is protected by its own flag.
  final bool Function(int messageId) messageProtected;

  /// Sets the platform's secure flag; answers whether it was applied here.
  final Future<bool> Function({required bool secure}) setSecure;

  static Future<bool> _setSecureWindow({required bool secure}) =>
      setSecureWindow(secure: secure);

  final listen.ValueListenable<ChatProtection> _protection;

  // One tear-off, so [dispose] knows the facade's hook is still this one.
  late final ChatCanCopy _hook = canCopy;
  late ChatProtection _last;
  var _captureOn = false;
  var _disposed = false;

  static final _leaving =
      ProtectionFlags.copy | ProtectionFlags.forward | ProtectionFlags.save;

  /// What protection denies for the message with [messageId].
  ProtectionFlags flagsOf(int messageId) => _protection.value.forMessage(
    messageProtected: messageProtected(messageId),
  );

  /// What protection denies for any of [messageIds] (a message selection).
  ProtectionFlags flagsOfAll(Iterable<int> messageIds) =>
      messageIds.fold(ProtectionFlags.none, (flags, id) => flags | flagsOf(id));

  /// Whether the message with [messageId] may be copied.
  bool canCopy(int messageId) =>
      !flagsOf(messageId).contains(ProtectionFlags.copy);

  /// The message menu rows protection takes away from a menu over
  /// [messageIds].
  Set<String> deniedMenuActions(Iterable<int> messageIds) =>
      MessageMenuCatalog.protectedActionIds(flagsOfAll(messageIds));

  /// Reports [refused], a copy the facade refused, as a denied copy.
  void reportRefused(ChatCopyRefused refused) =>
      reportDenied(CapabilityAction.copy, refused.messageId);

  /// Reports an attempt of [action] on the message with [messageId] that
  /// protection denies.
  void reportDenied(CapabilityAction action, int messageId) {
    if (_disposed) return;
    feedback.onDenied(
      action,
      _reasonFor(action),
      consumer: CapabilityConsumer.selection,
      correlation: ChatCorrelation(chatId: chatId, scrollId: '$messageId'),
    );
  }

  // The chat's protection reads as the admins' choice; a message protected
  // on its own as content that is not available.
  DenialReason _reasonFor(CapabilityAction action) {
    final chat = _protection.value;
    final byChat = switch (action) {
      CapabilityAction.copy => !chat.copy,
      CapabilityAction.forward => !chat.forward,
      CapabilityAction.save => !chat.save,
      _ => false,
    };
    return byChat
        ? const DenialReason.everyone()
        : const DenialReason.other(protectedMessageTag);
  }

  /// The tag of [DenialReason.other] for content its own message protects.
  static const protectedMessageTag = 'protectedMessage';

  void _onProtection() {
    if (_disposed) return;
    final next = _protection.value;
    final previous = _last;
    _last = next;
    if (next.flags.without(ProtectionFlags.captureBlocked) !=
        previous.flags.without(ProtectionFlags.captureBlocked)) {
      _apply(scope: 'chat');
    }
    if (next.captureBlocked != _captureOn) {
      unawaited(_applyCapture(on: next.captureBlocked));
    }
  }

  // The chat's protection changed. A message's own flag is set when the
  // message arrives and never changes in the demo, so there is no message
  // scope to apply.
  void _apply({required String scope}) {
    selection.reapplyCanCopy();
    final held = {
      ...selection.selectedIds,
      ?selection.textSelectionSubject,
    }.where((id) => !(flagsOf(id) & _leaving).isEmpty);
    final String outcome;
    if (held.isEmpty) {
      outcome = 'none';
    } else if (selection.selectionPolicy case ChatSelectionPolicy$Desktop()) {
      selection
        ..clearTextSelection()
        ..clear();
      outcome = 'cleared';
    } else {
      outcome = 'kept';
    }
    final bits = _protection.value.flags.bits;
    ChatDiagnostics.current.emit(
      ChatEventLevel.info,
      ChatEventCategory.capabilities,
      ChatProtectionOp.protectionApplied,
      correlation: ChatCorrelation(chatId: chatId),
      fields: () => {'scope': scope, 'bits': bits, 'selection': outcome},
    );
  }

  Future<void> _applyCapture({required bool on}) async {
    _captureOn = on;
    final applied = await setSecure(secure: on);
    ChatDiagnostics.current.emit(
      ChatEventLevel.info,
      ChatEventCategory.capabilities,
      ChatProtectionOp.captureBlocked,
      correlation: ChatCorrelation(chatId: chatId),
      fields: () => {'on': on, 'applied': applied},
    );
  }

  /// Stops following the chat; a capture block still on is lifted, since
  /// the flag is the window's and outlives the chat.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _protection.removeListener(_onProtection);
    if (identical(selection.canCopy, _hook)) selection.canCopy = null;
    if (_captureOn) unawaited(_applyCapture(on: false));
  }
}
