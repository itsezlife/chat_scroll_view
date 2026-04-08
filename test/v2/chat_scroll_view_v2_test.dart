import 'dart:ui' as ui;

import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll_view_common.dart';
import 'package:chatscrollview/src/v2/chat_data_source.dart';
import 'package:chatscrollview/src/v2/chat_message_render.dart';
import 'package:chatscrollview/src/v2/chat_scroll_chunk.dart';
import 'package:chatscrollview/src/v2/chat_scroll_controller.dart';
import 'package:chatscrollview/src/v2/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test data source
// ---------------------------------------------------------------------------

class _TestDataSource extends ChatDataSource {
  _TestDataSource(List<IChatMessage> messages) {
    upsertMessages(messages);
  }

  @override
  Future<List<IChatMessage>> fetch({
    int? from,
    int? to,
    DateTime? after,
  }) async => const [];
}

// ---------------------------------------------------------------------------
// Test message render
// ---------------------------------------------------------------------------

class _TestMessageRender extends ChatMessageRender {
  _TestMessageRender(Object? message) {
    if (message is IChatMessage) _updateText(message);
  }

  static const double _padding = 12.0;
  static const double _bubblePadding = 16.0;

  IChatMessage? _message;
  ui.Paragraph? _paragraph;

  void _updateText(IChatMessage message) {
    _message = message;
    dirty = true;
  }

  @override
  void update(Object? message, ChatMessageStatus status) {
    if (identical(_message, message)) return;
    if (message is! IChatMessage) {
      _message = null;
      _paragraph = null;
      dirty = true;
      return;
    }
    _updateText(message);
  }

  @override
  double performLayout(double availableWidth) {
    final message = _message;
    if (message == null) return 0.0;
    final content = switch (message) {
      ChatMessage$User(:final content) => content,
      ChatMessage$System(:final content) => content,
      _ => 'Message #${message.id}',
    };
    final textWidth = availableWidth - _bubblePadding * 2 - _padding * 2;
    final builder =
        ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 15.0, height: 1.4))
          ..pushStyle(ui.TextStyle(color: const Color(0xFF1A1A1A)))
          ..addText(content)
          ..pop();
    _paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: textWidth));
    return _paragraph!.height + _bubblePadding * 2 + _padding;
  }

  @override
  void paintMessage(Canvas canvas, Size size) {
    final paragraph = _paragraph;
    if (paragraph == null) return;
    canvas.drawParagraph(paragraph, Offset(_padding + _bubblePadding, _padding));
  }

  @override
  void dispose() {
    _paragraph = null;
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<IChatMessage> _generateMessages(int count) {
  final now = DateTime(2026, 1, 1);
  return [
    for (var i = 0; i < count; i++)
      ChatMessage$User(
        id: i,
        createdAt: now.add(Duration(minutes: i)),
        updatedAt: now.add(Duration(minutes: i)),
        content: 'Message #$i — The first rule of Fight Club is: '
            'you do not talk about Fight Club.',
      ),
  ];
}

Widget _buildTestWidget({
  required _TestDataSource dataSource,
  required ChatScrollController controller,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          builder: _TestMessageRender.new,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('v2 ChatScrollView', () {
    group('scroll coverage', () {
      testWidgets('all 256 messages remain accessible after scrolling up and back',
          (tester) async {
        const count = 256;
        final messages = _generateMessages(count);
        final dataSource = _TestDataSource(messages);
        final controller = ChatScrollController()
          ..oldestKnownId = 0
          ..newestKnownId = count - 1
          ..reachedOldest = true
          ..reachedNewest = true;
        controller.jumpTo(count - 1);

        await tester.pumpWidget(_buildTestWidget(
          dataSource: dataSource,
          controller: controller,
        ));
        await tester.pump();

        final renderObject = tester.renderObject<RenderChatScrollView>(
          find.byType(ChatScrollView),
        );

        // Verify all 4 chunks exist (256 / 64 = 4).
        expect(renderObject.debugChunkCount, 4);

        // Scroll UP (see older messages) — positive delta moves anchor down,
        // revealing content above.
        for (var i = 0; i < 80; i++) {
          controller.applyScrollDelta(200.0);
          renderObject.markNeedsLayout();
          await tester.pump();
        }

        // Verify we moved toward older chunks.
        expect(renderObject.debugLayoutMinChunk, lessThanOrEqualTo(1));

        // Now scroll back DOWN (see newer messages) — negative delta.
        for (var i = 0; i < 80; i++) {
          controller.applyScrollDelta(-200.0);
          renderObject.markNeedsLayout();
          await tester.pump();
        }

        // Verify all chunks still exist (no eviction — only 4 chunks, max is 16).
        expect(renderObject.debugChunkCount, 4);

        // Verify the newest message render exists and has a height.
        final newestChunk = dataSource.chunks[ChatScrollChunk.chunkOf(255)];
        expect(newestChunk, isNotNull);
        final newestRender = newestChunk!.renders[255 - newestChunk.firstId];
        expect(newestRender, isNotNull);
        expect(newestRender!.height, greaterThan(0));

        // Verify chunk 3 (messages 192-255) is in the layout range.
        expect(renderObject.debugLayoutMaxChunk, 3);
      });

      testWidgets('anchor chunk covers viewport — no extra chunks needed',
          (tester) async {
        // With 64 messages per chunk, each ~60px, a single chunk is ~3840px.
        // Viewport is 600px. One chunk alone covers the viewport.
        const count = 256;
        final messages = _generateMessages(count);
        final dataSource = _TestDataSource(messages);
        final controller = ChatScrollController()
          ..oldestKnownId = 0
          ..newestKnownId = count - 1
          ..reachedOldest = true
          ..reachedNewest = true;

        controller.jumpTo(0);

        await tester.pumpWidget(_buildTestWidget(
          dataSource: dataSource,
          controller: controller,
        ));
        await tester.pump();

        final renderObject = tester.renderObject<RenderChatScrollView>(
          find.byType(ChatScrollView),
        );

        // Chunk 0 alone (3840px) covers viewport (600px) + cacheExtent (250px).
        // Anchor chunk = 0, and it IS the layout range.
        expect(renderObject.debugLayoutMinChunk, 0);
        expect(renderObject.debugLayoutMaxChunk, 0);
      });

      testWidgets('boundary clamping expands layout to cover viewport',
          (tester) async {
        // With few short messages, boundary clamping might need extra chunks.
        final now = DateTime(2026, 1, 1);
        final messages = <IChatMessage>[
          for (var i = 0; i < 256; i++)
            ChatMessage$User(
              id: i,
              createdAt: now.add(Duration(minutes: i)),
              updatedAt: now.add(Duration(minutes: i)),
              content: 'Hi', // very short messages
            ),
        ];
        final dataSource = _TestDataSource(messages);
        final controller = ChatScrollController()
          ..oldestKnownId = 0
          ..newestKnownId = 255
          ..reachedOldest = true
          ..reachedNewest = true;

        // Jump to last message — boundary clamping should pin to bottom
        // and expand upward to fill the viewport.
        controller.jumpTo(255);

        await tester.pumpWidget(_buildTestWidget(
          dataSource: dataSource,
          controller: controller,
        ));
        await tester.pump();

        final renderObject = tester.renderObject<RenderChatScrollView>(
          find.byType(ChatScrollView),
        );

        // After clamping + re-expansion, layout should include the newest chunk.
        expect(renderObject.debugLayoutMaxChunk, 3);
        // Even "Hi" messages at ~40px × 64 = 2560px per chunk — one chunk
        // still covers the 600px viewport. Verify layout ran without crashing
        // and the anchor was clamped to a valid position.
        expect(controller.anchorPixelOffset, greaterThanOrEqualTo(0));
      });
    });

    group('typed listeners', () {
      testWidgets('data listener triggers relayout', (tester) async {
        final messages = _generateMessages(32);
        final dataSource = _TestDataSource(messages);
        final controller = ChatScrollController()
          ..oldestKnownId = 0
          ..newestKnownId = 31
          ..reachedOldest = true
          ..reachedNewest = true;
        controller.jumpTo(31);

        await tester.pumpWidget(_buildTestWidget(
          dataSource: dataSource,
          controller: controller,
        ));
        await tester.pump();

        final renderObject = tester.renderObject<RenderChatScrollView>(
          find.byType(ChatScrollView),
        );

        final framesBefore = renderObject.debugLayoutFrameId;

        // Upsert triggers notifyDataChanged → markNeedsLayout.
        dataSource.upsertMessage(ChatMessage$User(
          id: 5,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          content: 'Updated message',
        ));
        await tester.pump();

        expect(renderObject.debugLayoutFrameId, greaterThan(framesBefore));
      });

      testWidgets('jump listener triggers relayout', (tester) async {
        final messages = _generateMessages(256);
        final dataSource = _TestDataSource(messages);
        final controller = ChatScrollController()
          ..oldestKnownId = 0
          ..newestKnownId = 255
          ..reachedOldest = true
          ..reachedNewest = true;
        controller.jumpTo(255);

        await tester.pumpWidget(_buildTestWidget(
          dataSource: dataSource,
          controller: controller,
        ));
        await tester.pump();

        final ro = tester.renderObject<RenderChatScrollView>(
          find.byType(ChatScrollView),
        );
        final framesBefore = ro.debugLayoutFrameId;

        controller.jumpTo(0);
        await tester.pump();

        expect(ro.debugLayoutFrameId, greaterThan(framesBefore));
        expect(controller.anchorMessageId, 0);
      });
    });

    group('chunk math', () {
      test('chunkOf handles negative IDs correctly', () {
        expect(ChatScrollChunk.chunkOf(64), 1);
        expect(ChatScrollChunk.chunkOf(0), 0);
        expect(ChatScrollChunk.chunkOf(-1), -1);
        expect(ChatScrollChunk.chunkOf(-64), -1);
        expect(ChatScrollChunk.chunkOf(-65), -2);
      });

      test('firstIdOf is inverse of chunkOf for chunk boundaries', () {
        for (var ci = -10; ci <= 10; ci++) {
          final firstId = ChatScrollChunk.firstIdOf(ci);
          expect(ChatScrollChunk.chunkOf(firstId), ci);
        }
      });
    });
  });
}
