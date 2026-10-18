import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_emoji_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_header_panel.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_reactions_row.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The reply a decorated message carries.
const EmojiHeaderData emojiMenuReply = EmojiHeaderData.reply(
  sender: 'Ann',
  text: 'see you',
);

/// The reactions a decorated message carries.
const List<EmojiReaction> emojiMenuReactions = <EmojiReaction>[
  EmojiReaction('\u{1F44D}', 3, chosen: true),
  EmojiReaction('\u{2764}', 1),
];

class _OneMessageSource extends ChatDataSource {
  _OneMessageSource() {
    upsertMessages(<IChatMessage>[
      UserChatMessage(
        id: 1,
        sender: 'User',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        content: 'hi',
      ),
    ]);
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

/// One emoji-only message on a phone-sized dark screen, and the example's
/// message menu opened on it the way the viewport opens it: from the surface
/// the message reports, in the mobile sheet.
///
/// The viewport is not mounted: the request is built here from the surface the
/// message registered with the selection facade, which is what the viewport
/// copies into the request. Dispose it with the test.
final class EmojiMenuRig {
  /// Creates the rig and its services.
  EmojiMenuRig({this.stickerFor, this.reactions, this.excludeActionIds})
    : _assets = AssetCacheScope(producer: FakeAssetProducer()),
      _policy = ValueNotifier(const LargeEmojiPolicy(enabled: true)),
      selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
      ),
      _dataSource = _OneMessageSource() {
    host = stickerFor == null
        ? ChatBodyHost(assets: _assets, policy: _policy)
        : ChatBodyHost(
            assets: _assets,
            policy: _policy,
            stickerFor: stickerFor!,
          );
    _menu = MessageMenu(
      dataSource: _dataSource,
      selection: selection,
      actions: MessageMenuActions(onDelete: (_) {}, onEdit: (_) {}),
      clipboard: FakeRichClipboard(),
      reactions: reactions,
      excludeActionIds: excludeActionIds,
    );
  }

  /// The host's own map from an emoji to its sticker; the animated pack's when
  /// null.
  final ContentKey? Function(ContentKey key)? stickerFor;

  /// The reaction strip of the menu; the catalog's when null.
  final List<String>? reactions;

  /// Rows the menu leaves out; none when null.
  final List<String>? excludeActionIds;

  /// The chat's selection facade the message registers with.
  final ChatSelectionController selection;

  /// The screen's seams to the asset cache and its sticker decisions.
  late final ChatBodyHost host;

  /// The screen's size.
  static const Size screen = Size(360, 640);

  /// The width of the row the message sits in.
  static const double rowWidth = 340;

  final AssetCacheScope _assets;
  final ValueNotifier<LargeEmojiPolicy> _policy;
  final _OneMessageSource _dataSource;
  late final MessageMenu _menu;

  /// The key of the row, for the root key to find a context in.
  final GlobalKey rowKey = GlobalKey();

  /// Shows the message in a row [rowWidth] wide at the top left of the screen,
  /// on [background] (the dark theme's when null).
  Future<void> show(
    WidgetTester tester,
    EmojiOnly emojiOnly, {
    required ChatEmojiPolicy platform,
    required TextDirection direction,
    required bool outgoing,
    required bool decorated,
    Color? background,
  }) async {
    tester.view
      ..physicalSize = screen
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final message = DemoEmojiMessage(
      messageId: 1,
      emojiOnly: emojiOnly,
      selection: selection,
      host: host,
      createdAt: DateTime(2026, 1, 1, 9, 5),
      isOutgoing: outgoing,
      header: decorated ? emojiMenuReply : null,
      reactions: decorated ? emojiMenuReactions : const <EmojiReaction>[],
      policy: platform,
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            backgroundColor: background,
            body: Align(
              alignment: Alignment.topLeft,
              // Room above the message for its reply, as in a list.
              child: Padding(
                padding: const EdgeInsets.only(top: 120),
                child: SizedBox(
                  key: rowKey,
                  width: rowWidth,
                  child: Align(
                    heightFactor: 1,
                    alignment: outgoing
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: message,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // The surface registers after the first frame.
    await tester.pump();
  }

  /// Opens the sheet on the shown message and lets it settle. [tap] is where
  /// the finger was; the surface's centre when null.
  Future<void> open(WidgetTester tester, {Offset? tap}) async {
    final surface = selection.messageSurfaceGlobal(1)!;
    final request = ChatMessageMenuRequest(
      messageId: 1,
      slotGlobal: Rect.fromLTRB(
        0,
        surface.rect.top - 4,
        screen.width,
        surface.rect.bottom + 4,
      ),
      tapGlobal: tap ?? surface.rect.center,
      surfaceGlobal: surface.rect,
      surfaceShape: surface.shape,
      bandGlobal: Offset.zero & screen,
    );
    unawaited(_menu.present(tester.element(find.byKey(rowKey)), request));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  /// Disposes the services.
  void dispose() {
    selection.dispose();
    _dataSource.dispose();
    _policy.dispose();
    _assets.dispose();
  }
}
