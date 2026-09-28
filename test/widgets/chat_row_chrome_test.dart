import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart'
    show ChatMessageParentData;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

/// The row chrome inputs a viewport publishes into [ChatMessageParentData].
typedef _Frame = ({
  double paintTop,
  ChatFloatingHeaderZone header,
  double activity,
});

/// A header whose painted bottom sits [bottom] px below the row's top.
_Frame _headerBottomAt(double bottom) => (
  paintTop: 0,
  header: ChatFloatingHeaderZone(restTop: 0, extent: bottom),
  activity: 1,
);

const _Frame _noHeader = (
  paintTop: 0,
  header: ChatFloatingHeaderZone.none,
  activity: 1,
);

/// Stands in for `RenderChatScrollView`: gives its child the viewport's
/// [ChatMessageParentData] and publishes [frame] into it, the way the
/// viewport does every frame.
class _ViewportRow extends SingleChildRenderObjectWidget {
  const _ViewportRow({required this.frame, required super.child});

  final _Frame frame;

  @override
  _RenderViewportRow createRenderObject(BuildContext context) =>
      _RenderViewportRow(frame);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderViewportRow renderObject,
  ) {
    renderObject.frame = frame;
  }
}

class _RenderViewportRow extends RenderProxyBox {
  _RenderViewportRow(this._frame);

  _Frame _frame;
  set frame(_Frame value) {
    if (value == _frame) return;
    _frame = value;
    if (child?.parentData case final ChatMessageParentData pd) _publish(pd);
    child?.markNeedsPaint();
  }

  void _publish(ChatMessageParentData pd) => pd
    ..paintTop = _frame.paintTop
    ..headerZone = _frame.header
    ..scrollActivity = _frame.activity;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData case ChatMessageParentData()) return;
    child.parentData = ChatMessageParentData();
    _publish(child.parentData! as ChatMessageParentData);
  }
}

/// Mounts [row] top-left at 300 px wide; under a stand-in viewport parent
/// when [frame] is set.
Widget _host(Widget row, {_Frame? frame}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 300,
      child: switch (frame) {
        final frame? => _ViewportRow(frame: frame, child: row),
        null => row,
      },
    ),
  ),
);

Widget _box(String label, double height, {VoidCallback? onTap}) => SizedBox(
  height: height,
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Text(label),
  ),
);

/// Date (24, fades under the header) → marker (40, opaque) → body (60).
Widget _row({
  _Frame? frame,
  VoidCallback? onDateTap,
  VoidCallback? onMarkerTap,
  VoidCallback? onBodyTap,
}) => _host(
  ChatRowChrome(
    chrome: <ChatRowChromeItem>[
      ChatRowChromeItem(
        delegate: const ChatRowChromeDelegate.fadeUnderHeader(),
        child: _box('date', 24, onTap: onDateTap),
      ),
      ChatRowChromeItem(child: _box('marker', 40, onTap: onMarkerTap)),
    ],
    body: _box('body', 60, onTap: onBodyTap),
  ),
  frame: frame,
);

final Finder _rowChrome = find.byWidgetPredicate((w) => w is ChatRowChrome);

RenderChatRowChrome _rowBox(WidgetTester tester) =>
    tester.renderObject<RenderChatRowChrome>(_rowChrome);

double _bodyTop(WidgetTester tester) =>
    (_rowBox(tester).parentData! as ChatMessageParentData).messageBodyTop;

Iterable<OpacityLayer> _opacityLayers(WidgetTester tester) =>
    tester.layers.whereType<OpacityLayer>();

/// Host-defined delegate: records what it is asked and paints at activity.
final class _ActivityChrome implements ChatRowChromeDelegate {
  _ActivityChrome(this.seen);

  final List<ChatRowChromeMetrics> seen;

  @override
  ChatRowChromeEffect resolve(ChatRowChromeMetrics metrics) {
    seen.add(metrics);
    return ChatRowChromeEffect(opacity: metrics.activity, hitTestable: true);
  }
}

class _LoadedSource extends ChatDataSource {
  _LoadedSource(List<IChatMessage> messages) {
    upsertMessages(messages);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: messages.length - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChatRowChrome', () {
    testWidgets('stacks chrome top to bottom above the body', (tester) async {
      await tester.pumpWidget(_row());

      expect(tester.getTopLeft(find.text('date')).dy, 0);
      expect(tester.getTopLeft(find.text('marker')).dy, 24);
      expect(tester.getTopLeft(find.text('body')).dy, 64);
      expect(_rowBox(tester).size, const Size(300, 124));
    });

    testWidgets('each child sits under its own repaint boundary', (
      tester,
    ) async {
      await tester.pumpWidget(_row());

      for (final label in <String>['date', 'marker', 'body']) {
        final boundary = find.ancestor(
          of: find.text(label),
          matching: find.byType(RepaintBoundary),
        );
        final rowDescendant = find.descendant(
          of: _rowChrome,
          matching: boundary,
        );
        expect(rowDescendant, findsOneWidget, reason: label);
      }
    });

    testWidgets('writes the summed chrome height as the viewport body top', (
      tester,
    ) async {
      await tester.pumpWidget(_row(frame: _noHeader));

      expect(_bodyTop(tester), 64);
    });

    testWidgets('no chrome: the body sits at the top and body top is zero', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ChatRowChrome(
            chrome: const <ChatRowChromeItem>[],
            body: _box('body', 60),
          ),
          frame: _noHeader,
        ),
      );

      expect(tester.getTopLeft(find.text('body')).dy, 0);
      expect(_bodyTop(tester), 0);
    });

    testWidgets('each item paints at its own delegate opacity', (tester) async {
      await tester.pumpWidget(_row(frame: _noHeader));
      expect(_opacityLayers(tester), isEmpty);

      // Header bottom 10 px below the date's top → halfway through the band.
      await tester.pumpWidget(_row(frame: _headerBottomAt(10)));
      final layers = _opacityLayers(tester).toList();
      expect(layers, hasLength(1), reason: 'the opaque marker has no layer');
      expect(layers.single.alpha, 128);
      expect(
        layers.single.offset,
        Offset.zero,
        reason: 'the fading layer is the date at the top of the row',
      );
    });

    testWidgets('an item resolved hidden neither paints nor takes input; '
        'others still do', (tester) async {
      var dateTaps = 0;
      var markerTaps = 0;
      var bodyTaps = 0;
      await tester.pumpWidget(
        _row(
          frame: _headerBottomAt(20),
          onDateTap: () => dateTaps++,
          onMarkerTap: () => markerTaps++,
          onBodyTap: () => bodyTaps++,
        ),
      );
      expect(_rowBox(tester).debugChromeEffect(0).opacity, 0);
      expect(_opacityLayers(tester), isEmpty);

      await tester.tapAt(const Offset(10, 12));
      await tester.tapAt(const Offset(10, 44));
      await tester.tapAt(const Offset(10, 94));

      expect(dateTaps, 0);
      expect(markerTaps, 1);
      expect(bodyTaps, 1);
    });

    testWidgets('a partially visible item takes input', (tester) async {
      var dateTaps = 0;
      await tester.pumpWidget(
        _row(frame: _headerBottomAt(10), onDateTap: () => dateTaps++),
      );

      await tester.tapAt(const Offset(10, 12));

      expect(dateTaps, 1);
    });

    testWidgets('a host delegate sees viewport paint top, extent, header, '
        'and activity', (tester) async {
      final seen = <ChatRowChromeMetrics>[];
      const header = ChatFloatingHeaderZone(restTop: 8, extent: 30);
      await tester.pumpWidget(
        _host(
          ChatRowChrome(
            chrome: <ChatRowChromeItem>[
              ChatRowChromeItem(child: _box('top', 24)),
              ChatRowChromeItem(
                delegate: _ActivityChrome(seen),
                child: _box('custom', 16),
              ),
            ],
            body: _box('body', 60),
          ),
          frame: (paintTop: 100, header: header, activity: 0.25),
        ),
      );

      final metrics = seen.last;
      expect(metrics.top, 124, reason: 'row paint top + item offset');
      expect(metrics.extent, 16);
      expect(metrics.header, header);
      expect(metrics.activity, 0.25);
      expect(_opacityLayers(tester).single.alpha, 64);
    });

    testWidgets('outside a viewport the top is the offset in the row and '
        'there is no header', (tester) async {
      final seen = <ChatRowChromeMetrics>[];
      await tester.pumpWidget(
        _host(
          ChatRowChrome(
            chrome: <ChatRowChromeItem>[
              ChatRowChromeItem(child: _box('top', 24)),
              ChatRowChromeItem(
                delegate: _ActivityChrome(seen),
                child: _box('custom', 16),
              ),
            ],
            body: _box('body', 60),
          ),
        ),
      );

      expect(seen.last.top, 24);
      expect(seen.last.header, ChatFloatingHeaderZone.none);
      expect(seen.last.activity, 1);
    });

    testWidgets('swapping a delegate takes effect without re-inflating', (
      tester,
    ) async {
      Widget build(ChatRowChromeDelegate delegate) => _host(
        ChatRowChrome(
          chrome: <ChatRowChromeItem>[
            ChatRowChromeItem(delegate: delegate, child: _box('chrome', 24)),
          ],
          body: _box('body', 60),
        ),
        frame: _headerBottomAt(10),
      );

      await tester.pumpWidget(build(const ChatRowChromeDelegate.opaque()));
      expect(_opacityLayers(tester), isEmpty);
      final before = tester.renderObject(find.text('chrome'));

      await tester.pumpWidget(
        build(const ChatRowChromeDelegate.fadeUnderHeader()),
      );
      expect(_opacityLayers(tester), hasLength(1));
      expect(tester.renderObject(find.text('chrome')), same(before));
    });
  });

  group('ChatRowChrome in the viewport', () {
    testWidgets('long-press on inline date chrome does not select; on the '
        'body below it does', (tester) async {
      const count = 32;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 600,
                child: ChatScrollView(
                  dataSource: _LoadedSource(<IChatMessage>[
                    for (var i = 0; i < count; i++)
                      UserChatMessage(
                        id: i,
                        sender: 'User',
                        createdAt: DateTime(2026, 1, 1 + i ~/ 4, 9, i % 4),
                        updatedAt: DateTime(2026, 1, 1 + i ~/ 4, 9, i % 4),
                        content: 'content $i',
                      ),
                  ]),
                  controller: controller,
                  selectionController: selection,
                  messageBuilder: (context, id, message, status, runLayout) =>
                      SizedBox(height: 60, child: Text('msg-$id')),
                  dateSeparatorBuilder: (context, bucket, date) => SizedBox(
                    height: 40,
                    child: Text('sep-${date.month}-${date.day}'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // At the tail msg-28 starts day 8 well below the floating header, so
      // 'sep-1-8' is its inline date chrome only.
      expect(find.text('sep-1-8'), findsOneWidget);
      await tester.longPress(find.text('sep-1-8'));
      await tester.pumpAndSettle();
      expect(selection.isSelectionMode, isFalse);

      await tester.longPress(find.text('msg-28'));
      await tester.pumpAndSettle();
      expect(selection.isSelectionMode, isTrue);
      expect(selection.isSelected(28), isTrue);
    });
  });

  group('DatedMessage (deprecated forward)', () {
    testWidgets('lays out as date chrome that fades under the header', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          // ignore: deprecated_member_use_from_same_package
          DatedMessage(separator: _box('date', 24), body: _box('body', 60)),
          frame: _headerBottomAt(10),
        ),
      );

      expect(tester.getTopLeft(find.text('body')).dy, 24);
      expect(_bodyTop(tester), 24);
      expect(_opacityLayers(tester).single.alpha, 128);
    });
  });
}
