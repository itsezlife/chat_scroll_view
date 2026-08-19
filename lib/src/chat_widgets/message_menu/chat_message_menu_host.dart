import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_actions.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_appearance.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_config.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_item.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_placement.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_reactions.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_scrim.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_pre_ime_back.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/overlay_back_button_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen message menu (scrim + reactions + actions).
class ChatMessageMenuHost extends StatefulWidget {
  /// Creates the host.
  const ChatMessageMenuHost({
    required this.config,
    required this.onResult,
    this.backButtonDispatcher,
    super.key,
  });

  /// Presentation snapshot.
  final ChatMessageMenuPresentConfig config;

  /// Called after leave animation with the chosen result (or null).
  final Future<void> Function(ChatMessageMenuResult? result) onResult;

  /// Host [Router] dispatcher captured outside the overlay entry.
  final BackButtonDispatcher? backButtonDispatcher;

  @override
  State<ChatMessageMenuHost> createState() => _ChatMessageMenuHostState();
}

class _ChatMessageMenuHostState extends State<ChatMessageMenuHost>
    with SingleTickerProviderStateMixin {
  final GlobalKey _menuKey = GlobalKey();
  final GlobalKey<ChatMessageMenuAppearanceState> _appearanceKey =
      GlobalKey<ChatMessageMenuAppearanceState>();

  late final AnimationController _scrim;
  late final ChatPreImeBackClaim _backClaim;
  Size _menuSize = const Size(220, 200);
  var _closing = false;

  @override
  void initState() {
    super.initState();
    _scrim = AnimationController(
      vsync: this,
      duration: kChatMessageMenuScrimDuration,
    )..forward();
    _backClaim = ChatPreImeBackClaim.push(_onBackButtonPressed);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    final presence = widget.config.presence;
    if (presence != null && widget.config.isPresent != null) {
      presence.addListener(_onPresence);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureMenu();
      if (widget.config.presence != null && widget.config.isPresent != null) {
        _onPresence();
      }
    });
  }

  @override
  void dispose() {
    widget.config.presence?.removeListener(_onPresence);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _backClaim.pop();
    _scrim.dispose();
    super.dispose();
  }

  void _onPresence() {
    final isPresent = widget.config.isPresent;
    if (isPresent == null) return;
    if (!isPresent()) _close(null);
  }

  void _measureMenu() {
    final box = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final size = box.size;
    if (size == _menuSize) return;
    setState(() => _menuSize = size);
  }

  Future<void> _close(ChatMessageMenuResult? result) async {
    if (_closing) return;
    _closing = true;
    await Future.wait<void>([
      _appearanceKey.currentState?.dismiss() ?? Future<void>.value(),
      _scrim.reverse(),
    ]);
    await widget.onResult(result);
  }

  Future<bool> _onBackButtonPressed() async {
    if (_closing) return true;
    // Do not await leave animation — [WidgetsBinding.handlePopRoute]
    // would deadlock waiting on Tickers that need another frame.
    _close(null).ignore();
    return true;
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (_closing) return true;
    _close(null);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final screenSize = config.screenSize;
    final placement = computeChatMessageMenuPlacement(
      screenSize: screenSize,
      keyboardHeight: config.keyboardHeight,
      messageRect: config.messageRect,
      menuSize: _menuSize,
      tapGlobal: config.tapGlobal,
      safePadding: config.safePadding,
    );

    return OverlayBackButtonListener(
      parentDispatcher: widget.backButtonDispatcher,
      onBackButtonPressed: _onBackButtonPressed,
      child: SizedBox(
        width: screenSize.width,
        height: screenSize.height,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _scrim,
                builder: (context, _) => ChatMessageMenuScrim(
                  progress: _scrim.value,
                  hole: config.messageRect.intersect(Offset.zero & screenSize),
                  onDismiss: () => _close(null),
                ),
              ),
            ),
            Positioned(
              left: placement.menuOrigin.dx,
              top: placement.menuOrigin.dy,
              child: ChatMessageMenuAppearance(
                key: _appearanceKey,
                fitsAbove: placement.fitsAbove,
                child: KeyedSubtree(
                  key: _menuKey,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.min(
                        kChatMessageMenuMinWidth +
                            kChatMessageMenuReactionsStartOverhang +
                            kChatMessageMenuReactionsEndOverhang,
                        screenSize.width - 2 * kChatMessageMenuEdgeInset,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (config.reactions.isNotEmpty) ...<Widget>[
                          Align(
                            alignment: Alignment.centerRight,
                            child: ChatMessageMenuReactions(
                              reactions: config.reactions,
                              onReaction: (emoji) {
                                _close(ChatMessageMenuResult.reaction(emoji));
                              },
                            ),
                          ),
                          const SizedBox(height: kChatMessageMenuReactionsGap),
                        ],
                        Padding(
                          padding: const EdgeInsets.only(
                            left: kChatMessageMenuReactionsStartOverhang,
                            right: kChatMessageMenuReactionsEndOverhang,
                          ),
                          child: ChatMessageMenuActionList(
                            items: config.items,
                            onSelect: (id) {
                              _close(ChatMessageMenuResult.item(id));
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
