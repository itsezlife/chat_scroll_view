// ignore_for_file: implementation_imports
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/grouped_messages_map_sync.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/media_fixture_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/media_fixture_messages.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

void main() {
  group('media fixture catalog', () {
    test('includes singles and one N≥2 album with distinct Message IDs', () {
      final messages = buildMediaFixtureMessages();
      final singles = messages
          .where((m) => m.hasMedia && m.groupId == null)
          .toList();
      final album = messages
          .where((m) => m.groupId == kMediaFixtureAlbumGroupId)
          .toList();

      expect(singles.length, greaterThanOrEqualTo(2));
      expect(singles.any((m) => m.mediaKind == MediaKind.photo), isTrue);
      expect(singles.any((m) => m.mediaKind == MediaKind.video), isTrue);
      expect(album.length, greaterThanOrEqualTo(2));
      expect(album.map((m) => m.id).toSet().length, album.length);
    });
  });

  group('GroupedMessagesMapSync', () {
    test('puts album members and removes stale ids', () {
      final map = GroupedMessagesMap();
      final sync = GroupedMessagesMapSync(map);
      final messages = buildMediaFixtureMessages();

      sync.sync(messages);
      expect(sync.syncedIds, {3, 4, 6, 7});
      expect(map.group(kMediaFixtureAlbumGroupId), isNotNull);
      expect(map.groupIdFor(3), kMediaFixtureAlbumGroupId);
      expect(map.groupIdFor(4), kMediaFixtureAlbumGroupId);
      expect(map.group(kMediaFixtureSideBySideGroupId), isNotNull);
      expect(map.groupIdFor(1), isNull);

      sync.sync(messages.where((m) => m.id != 4));
      expect(sync.syncedIds, {3, 6, 7});
      expect(map.group(kMediaFixtureAlbumGroupId), isNull);
      expect(map.groupIdFor(4), isNull);

      map.dispose();
    });
  });

  group('media fixture chat host seam', () {
    testWidgets('renders one MessageMediaPlaceholder per media Message ID', (
      tester,
    ) async {
      final dataSource = MediaFixtureChatDataSource();
      final map = GroupedMessagesMap();
      final sync = GroupedMessagesMapSync(map)
        ..sync(buildMediaFixtureMessages());
      final controller = ChatScrollController()..jumpTo(0);
      final mediaIds = buildMediaFixtureMessages()
          .where((m) => m.hasMedia)
          .map((m) => m.id)
          .toList();

      addTearDown(() {
        controller.dispose();
        dataSource.dispose();
        map.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: ChatScrollView(
                dataSource: dataSource,
                controller: controller,
                messageBuilder: (context, id, message, status, runLayout) {
                  if (message == null) {
                    return SizedBox(height: 40, child: Text('shimmer-$id'));
                  }
                  return DemoMessageBubble(
                    key: ValueKey('media-row-$id'),
                    message: message,
                    runLayout: runLayout,
                    groupedMessages: map,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(mediaIds, hasLength(6));
      expect(sync.syncedIds, {3, 4, 6, 7});

      for (final id in mediaIds) {
        controller.jumpTo(id);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(ValueKey('media-row-$id')),
            matching: find.byType(MessageMediaPlaceholder),
          ),
          findsOneWidget,
          reason: 'Message ID $id should paint a media placeholder',
        );
      }
    });

    testWidgets('selecting a group member selects only that Message ID', (
      tester,
    ) async {
      final dataSource = MediaFixtureChatDataSource();
      final map = GroupedMessagesMap();
      GroupedMessagesMapSync(map).sync(buildMediaFixtureMessages());
      final controller = ChatScrollController()..jumpTo(3);
      final selection = ChatSelectionController();

      addTearDown(() {
        controller.dispose();
        selection.dispose();
        dataSource.dispose();
        map.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: ChatScrollView(
                dataSource: dataSource,
                controller: controller,
                selectionController: selection,
                messageBuilder: (context, id, message, status, runLayout) {
                  if (message == null) {
                    return SizedBox(height: 40, child: Text('shimmer-$id'));
                  }
                  return DemoMessageBubble(
                    key: ValueKey('msg-$id'),
                    message: message,
                    runLayout: runLayout,
                    groupedMessages: map,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const ValueKey('msg-3')));
      await tester.pumpAndSettle();

      expect(selection.isSelectionMode, isTrue);
      expect(selection.isSelected(3), isTrue);
      expect(selection.isSelected(4), isFalse);
      expect(selection.count, 1);
    });

    testWidgets('side-by-side album cells are half mosaic width', (
      tester,
    ) async {
      final dataSource = MediaFixtureChatDataSource();
      final map = GroupedMessagesMap();
      GroupedMessagesMapSync(map).sync(buildMediaFixtureMessages());
      final controller = ChatScrollController()..jumpTo(6);

      addTearDown(() {
        controller.dispose();
        dataSource.dispose();
        map.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: ChatScrollView(
                dataSource: dataSource,
                controller: controller,
                messageBuilder: (context, id, message, status, runLayout) {
                  if (message == null) {
                    return const SizedBox(height: 40);
                  }
                  return DemoMessageBubble(
                    key: ValueKey('media-row-$id'),
                    message: message,
                    runLayout: runLayout,
                    groupedMessages: map,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final placeholder = tester.widget<MessageMediaPlaceholder>(
        find.descendant(
          of: find.byKey(const ValueKey('media-row-6')),
          matching: find.byType(MessageMediaPlaceholder),
        ),
      );
      final cell = placeholder.cell;
      expect(cell, isNotNull);
      // Side-by-side squares: cell width is about half the mosaic (gap inside).
      expect(cell!.rect.width, lessThan(200));
      expect(cell.rect.width, greaterThan(100));
    });
  });
}
