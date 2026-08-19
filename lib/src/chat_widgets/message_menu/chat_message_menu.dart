import 'dart:async';

import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_config.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_host.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_item.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_slots.dart';
import 'package:flutter/material.dart';

export 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_actions.dart';
export 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_column.dart';
export 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_item.dart';
export 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_reactions.dart';
export 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_slots.dart';
export 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_theme.dart';

/// Opens a message menu session over [messageRect].
///
/// Completes with a [ChatMessageMenuResult] when the user chooses an
/// action or a reaction, or with `null` on dismiss / presence abort.
/// Completes on the tap itself — leave animation does not delay the
/// result. The overlay is removed after the animation.
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
/// Restyle chrome with [ChatMessageMenuThemeData] (or
/// [ChatScrollThemeData.menu]). Replace rows or the floating column
/// with [itemBuilder] / [reactionBuilder] / [menuBuilder] — session,
/// scrim, placement, and back stay package-owned.
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
  ChatMessageMenuItemBuilder? itemBuilder,
  ChatMessageMenuReactionBuilder? reactionBuilder,
  ChatMessageMenuBuilder? menuBuilder,
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
    itemBuilder: itemBuilder,
    reactionBuilder: reactionBuilder,
    menuBuilder: menuBuilder,
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
  final navigator = Navigator.maybeOf(context, rootNavigator: true);
  if (navigator == null) {
    assert(false, 'showChatMessageMenu requires a Navigator');
    return Future<ChatMessageMenuResult?>.value();
  }

  final backDispatcher = Router.maybeOf(context)?.backButtonDispatcher;
  final completer = Completer<ChatMessageMenuResult?>();

  // A dialog route sits on the navigator stack, so system back hits this
  // session before a page [PopScope]. [requestFocus] is false so opening
  // does not steal IME focus. The hole is painted by the host, not a
  // modal barrier. The push future is not the session result — that
  // completes on tap so host work is not blocked by leave animation.
  unawaited(
    navigator
        .push<void>(
          RawDialogRoute<void>(
            requestFocus: false,
            barrierDismissible: false,
            barrierColor: const Color(0x00000000),
            transitionDuration: Duration.zero,
            pageBuilder: (routeContext, _, _) => MediaQuery(
              data: MediaQuery.of(
                routeContext,
              ).removeViewInsets(removeBottom: true),
              child: ChatMessageMenuHost(
                config: config,
                backButtonDispatcher: backDispatcher,
                onResult: (result) {
                  if (!completer.isCompleted) completer.complete(result);
                },
                onClosed: () {
                  if (routeContext.mounted && navigator.canPop()) {
                    navigator.pop();
                  }
                },
              ),
            ),
          ),
        )
        .then((_) {
          if (!completer.isCompleted) completer.complete(null);
        }),
  );
  return completer.future;
}
