import 'dart:async';

import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_config.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_host.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_item.dart';
import 'package:flutter/material.dart';

export 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_item.dart';

/// Opens a message menu session over [messageRect].
///
/// Completes with a [ChatMessageMenuResult] when the user chooses an
/// action or a reaction, or with `null` on dismiss / presence abort.
/// Empty [reactions] omits the reaction strip.
///
/// When [keepKeyboardVisible] is true, restores the previous [FocusNode]
/// after the overlay so IME height does not change. Does not request
/// focus if nothing was focused (IME stays hidden).
///
/// When both [presence] and [isPresent] are provided, the session
/// dismisses with `null` once [isPresent] returns false. The presenter
/// never reads the viewport.
///
Future<ChatMessageMenuResult?> showChatMessageMenu({
  required BuildContext context,
  required Rect messageRect,
  required List<ChatMessageMenuItem> items,
  Offset? tapGlobal,
  List<String> reactions = const <String>[],
  bool keepKeyboardVisible = true,
  Listenable? presence,
  bool Function()? isPresent,
}) async {
  final media = MediaQuery.of(context);
  final config = ChatMessageMenuPresentConfig(
    messageRect: messageRect,
    tapGlobal: tapGlobal,
    items: items,
    reactions: reactions,
    keyboardHeight: media.viewInsets.bottom,
    screenSize: media.size,
    safePadding: media.viewPadding,
    presence: presence,
    isPresent: isPresent,
  );

  final previousFocus = FocusManager.instance.primaryFocus;
  final result = await _showChatMessageMenuOverlay(
    context: context,
    config: config,
  );
  if (keepKeyboardVisible) {
    previousFocus?.requestFocus();
  }
  return result;
}

Future<ChatMessageMenuResult?> _showChatMessageMenuOverlay({
  required BuildContext context,
  required ChatMessageMenuPresentConfig config,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    assert(false, 'showChatMessageMenu requires an Overlay');
    return Future<ChatMessageMenuResult?>.value();
  }

  final backDispatcher = Router.maybeOf(context)?.backButtonDispatcher;
  final completer = Completer<ChatMessageMenuResult?>();
  late OverlayEntry entry;

  void complete(ChatMessageMenuResult? result) {
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }

  // Not opaque: the hole must show the captured slot still painted below.
  entry = OverlayEntry(
    builder: (overlayContext) => ChatMessageMenuHost(
      config: config,
      backButtonDispatcher: backDispatcher,
      onResult: (result) async {
        entry.remove();
        complete(result);
      },
    ),
  );

  overlay.insert(entry);
  return completer.future;
}
