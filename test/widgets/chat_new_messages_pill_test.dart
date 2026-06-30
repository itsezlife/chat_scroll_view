import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_scroll/chat_selection_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:chatscrollview/src/chat_widgets/demo/chat_composer.dart';
import 'package:chatscrollview/src/chat_widgets/demo/date_separator.dart';
import 'package:chatscrollview/src/chat_widgets/demo/demo_message.dart';
import 'package:chatscrollview/src/chat_widgets/demo/measure_size.dart';
import 'package:chatscrollview/src/chat_widgets/demo/new_messages_pill.dart';
import 'package:chatscrollview/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

IChatMessage _longMsg(int i) => UserChatMessage(
  id: i,
  sender: 'Hixie',
  createdAt: DateTime(2026, 1, i),
  updatedAt: DateTime(2026, 1, i),
  content: ('Paragraph line.\n' * 30).trim(),
);

/// Data source whose initial state is `isInitialLoading` (no boundaries, no
/// chunks). The test controls when ids actually appear by calling
/// [pushFirstArrival] / [pushMore].
class _LateArrivingSource extends ChatDataSource {
  bool _arrived = false;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];

  /// Simulate the first batch of ids landing — closes initial-loading by
  /// seeding both boundaries and upserting messages.
  void pushFirstArrival({required int count}) {
    if (_arrived) {
      throw StateError('pushFirstArrival can only be called once');
    }
    _arrived = true;
    for (var i = 0; i < count; i++) {
      upsertMessage(_msg(i));
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  /// Append a single new message past the previous newestKnownId, mimicking
  /// a real-time arrival.
  void appendOne() {
    final next = (newestKnownId ?? -1) + 1;
    upsertMessage(_msg(next));
    seedBoundaries(newestKnownId: next);
  }
}

class _PreloadedLikeSource extends ChatDataSource {
  _PreloadedLikeSource(int count) {
    for (var i = 0; i < count; i++) {
      upsertMessage(_msg(i));
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
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

class _DemoLongUnreadSource extends ChatDataSource {
  _DemoLongUnreadSource(int count, {required this.longFrom}) {
    for (var i = 0; i < count; i++) {
      upsertMessage(i >= longFrom ? _longMsg(i) : _msg(i));
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  final int longFrom;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

class _TallMessagePreloadedSource extends ChatDataSource {
  _TallMessagePreloadedSource(int count) {
    for (var i = 0; i < count; i++) {
      upsertMessage(_msg(i));
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
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

const _viewportWidth = 400.0;
const _viewportHeight = 600.0;

Future<void> _pumpSettleFrames(
  WidgetTester tester, {
  int frameCount = 12,
}) async {
  for (var i = 0; i < frameCount; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Widget _scaffoldWithTallPill({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  required int lastRead,
  double messageHeight = 350,
  double cacheExtent = 1000,
  ValueNotifier<int?>? lastSeenNewestId,
  bool reverse = true,
  ValueNotifier<double>? bottomPadding,
  Duration highlightDuration = const Duration(milliseconds: 600),
}) {
  final lastSeen = lastSeenNewestId ?? ValueNotifier<int?>(lastRead);
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: _viewportWidth,
          height: _viewportHeight,
          child: Stack(
            children: <Widget>[
              ChatScrollView(
                reverse: reverse,
                dataSource: dataSource,
                controller: controller,
                cacheExtent: cacheExtent,
                bottomPadding: bottomPadding,
                highlightDuration: highlightDuration,
                messageBuilder: (context, id, message, status) => SizedBox(
                  height: messageHeight,
                  child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
                ),
                loadingBuilder: (ctx) => const Center(child: Text('loading')),
              ),
              NewMessagesPill(
                controller: controller,
                dataSource: dataSource,
                lastSeenNewestId: lastSeen,
                bottomInset: bottomPadding,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _mountNearTailTall({
  required WidgetTester tester,
  required int count,
  required int lastRead,
  required ChatScrollController controller,
  required ChatDataSource ds,
  ValueNotifier<int?>? lastSeen,
  double messageHeight = 350,
}) async {
  addTearDown(controller.dispose);
  addTearDown(ds.dispose);
  if (lastSeen != null) {
    addTearDown(lastSeen.dispose);
  }

  controller.jumpTo(lastRead, alignment: 0.8);
  await tester.pumpWidget(
    _scaffoldWithTallPill(
      dataSource: ds,
      controller: controller,
      lastRead: lastRead,
      messageHeight: messageHeight,
      lastSeenNewestId: lastSeen,
      bottomPadding: ValueNotifier<double>(96),
    ),
  );
  await tester.pump();
}

/// Demo-like stack: viewport + [MeasureSize] [ChatComposer] feeding [bottomInset].
Widget _scaffoldWithPill({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  double cacheExtent = 1000,
  ValueNotifier<int?>? lastSeenNewestId,
  ValueNotifier<double>? bottomInset,
  double messageHeight = 60,
  bool reverse = true,
  ChatMessageBuilder? messageBuilder,
  bool useDemoMessages = false,
}) => _DemoPillScaffold(
  dataSource: dataSource,
  controller: controller,
  cacheExtent: cacheExtent,
  lastSeenNewestId: lastSeenNewestId,
  bottomInset: bottomInset,
  messageHeight: messageHeight,
  reverse: reverse,
  messageBuilder: messageBuilder,
  useDemoMessages: useDemoMessages,
);

/// Mirrors [WidgetChatScreen]'s viewport + measured composer stack.
class _DemoPillScaffold extends StatefulWidget {
  const _DemoPillScaffold({
    required this.dataSource,
    required this.controller,
    this.cacheExtent = 1000,
    this.lastSeenNewestId,
    this.bottomInset,
    this.messageHeight = 60,
    this.reverse = true,
    this.messageBuilder,
    this.useDemoMessages = false,
  });

  final ChatDataSource dataSource;
  final ChatScrollController controller;
  final double cacheExtent;
  final ValueNotifier<int?>? lastSeenNewestId;
  final ValueNotifier<double>? bottomInset;
  final double messageHeight;
  final bool reverse;
  final ChatMessageBuilder? messageBuilder;
  final bool useDemoMessages;

  @override
  State<_DemoPillScaffold> createState() => _DemoPillScaffoldState();
}

class _DemoPillScaffoldState extends State<_DemoPillScaffold> {
  late final ChatSelectionController _selection = ChatSelectionController();
  ValueNotifier<double>? _ownedBottomInset;

  ValueNotifier<double> get _bottomInset =>
      widget.bottomInset ?? _ownedBottomInset!;

  @override
  void initState() {
    super.initState();
    if (widget.bottomInset == null) {
      _ownedBottomInset = ValueNotifier<double>(96);
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    _ownedBottomInset?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget buildMessage(
      BuildContext context,
      int id,
      IChatMessage? message,
      ChatMessageStatus status,
    ) {
      if (widget.messageBuilder != null) {
        return widget.messageBuilder!(context, id, message, status);
      }
      return SizedBox(
        height: widget.messageHeight,
        child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
      );
    }

    Widget buildDemoMessage(
      BuildContext context,
      int id,
      IChatMessage? message,
      ChatMessageStatus status,
    ) {
      if (status.isAbsent) return const SizedBox.shrink();
      if (message == null) return const DemoShimmerBubble();
      final prev = widget.dataSource.getMessage(id - 1);
      return DemoMessageBubble(
        message: message,
        isFirstInRun: prev?.sender != message.sender,
      );
    }

    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: Stack(
            children: <Widget>[
              ChatScrollView(
                reverse: widget.reverse,
                dataSource: widget.dataSource,
                controller: widget.controller,
                cacheExtent: widget.cacheExtent,
                bottomPadding: _bottomInset,
                dateSeparatorBuilder: widget.useDemoMessages
                    ? (context, bucket, date) => DateSeparator(date: date)
                    : null,
                messageBuilder: widget.useDemoMessages
                    ? buildDemoMessage
                    : buildMessage,
                loadingBuilder: (ctx) => const Center(child: Text('loading')),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MeasureSize(
                  onChange: (size) => _bottomInset.value = size.height,
                  child: ChatComposer(
                    selection: _selection,
                    dataSource: widget.dataSource,
                    onSend: (_) async {},
                  ),
                ),
              ),
              NewMessagesPill(
                controller: widget.controller,
                dataSource: widget.dataSource,
                lastSeenNewestId: widget.lastSeenNewestId,
                bottomInset: _bottomInset,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _pumpDemoPillOpen(
  WidgetTester tester, {
  required Widget widget,
}) async {
  await tester.pumpWidget(widget);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
}

double _pillOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(NewMessagesPill),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

/// The pill widget is always present in the tree — only its opacity flips.
/// Read the rendered count from its `Text` to assert visibility intent.
String _pillText(WidgetTester tester) {
  final txt = tester.widget<Text>(
    find.descendant(
      of: find.byType(NewMessagesPill),
      matching: find.byType(Text),
    ),
  );
  return txt.data ?? '';
}

String _expectedPillLabel(int count) =>
    count == 1 ? '1 new message' : '$count new messages';

void main() {
  group('NewMessagesPill', () {
    testWidgets(
      'empty-source mount → first off-tail arrival surfaces the pill',
      (tester) async {
        // Regression: the pill seeded `_lastSeenNewestId` from
        // `dataSource.newestKnownId` in initState. With an initially-empty
        // source that value is `null`, and `_unseenCount` short-circuits to
        // 0 on a null baseline, so the pill stayed at "0 new messages"
        // (invisible) forever after the first message arrived off-tail.
        final ds = _LateArrivingSource();
        // Anchor mid-history before messages exist — when the batch lands
        // off-tail, the null-baseline promotion path must surface the pill.
        final controller = ChatScrollController()..jumpTo(0);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffoldWithPill(
            dataSource: ds,
            controller: controller,
            cacheExtent: 80,
          ),
        );
        await tester.pump();
        expect(
          _pillText(tester),
          '0 new messages',
          reason: 'pill is invisibly zero before any arrival',
        );

        // First batch lands. Anchor at id 50 → newest = 9, anchor is past
        // the end of the conversation → controller pins to newest? In
        // practice the renormalisation rebases the anchor to a visible
        // child, but `isAtTail` is recomputed each layout — and a follow-
        // tail clamp without a `_wasAtTailLastLayout=true` snapshot leaves
        // the user "off tail" until they scroll. Drive enough frames for
        // both the deferred setter and the pill's post-frame trampoline.
        ds.pushFirstArrival(count: 20);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));

        // The count for a bulk first-arrival is intentionally lossy (we
        // chose newest-1 as the seed, so the just-arrived id counts as
        // exactly 1). What matters is that the count is non-zero — the
        // pill is no longer silently hidden.
        expect(
          _pillText(tester),
          isNot('0 new messages'),
          reason:
              'After first off-tail arrival the pill must surface with '
              'a non-zero count.',
        );
      },
    );

    testWidgets('lastSeenNewestId sets unread baseline on open', (
      tester,
    ) async {
      final ds = _LateArrivingSource()..pushFirstArrival(count: 151);
      final controller = ChatScrollController()..jumpTo(50);
      final lastSeen = ValueNotifier<int?>(50);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(lastSeen.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 600,
                child: Stack(
                  children: <Widget>[
                    ChatScrollView(
                      dataSource: ds,
                      controller: controller,
                      messageBuilder: (context, id, message, status) =>
                          SizedBox(
                            height: 60,
                            child: Text(
                              message == null ? 'shimmer-$id' : 'msg-$id',
                            ),
                          ),
                    ),
                    NewMessagesPill(
                      controller: controller,
                      dataSource: ds,
                      lastSeenNewestId: lastSeen,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // 100 unread with only a viewport prefix visible — off-screen ratio
      // exceeds 0.75, so open sync defers read marking until scroll.
      expect(lastSeen.value, 50);
      expect(_pillText(tester), _expectedPillLabel(ds.newestKnownId! - 50));
    });

    testWidgets(
      'near-tail open with short messages reduces count from visible range',
      (tester) async {
        const count = 30;
        const lastRead = count - 16;
        const newest = count - 1;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        final bottomInset = ValueNotifier<double>(96);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);
        addTearDown(bottomInset.dispose);

        await _pumpDemoPillOpen(
          tester,
          widget: _scaffoldWithPill(
            dataSource: ds,
            controller: controller,
            lastSeenNewestId: lastSeen,
            bottomInset: bottomInset,
            messageHeight: 20,
          ),
        );

        final range = controller.visibleRange.value;
        expect(range, isNotNull);
        expect(range!.lastId, greaterThan(lastRead));
        expect(controller.anchorMessageId, lastRead);
        expect(range.lastRow.id - lastRead, greaterThan(2));

        final baseline = lastSeen.value!;
        expect(baseline, greaterThan(lastRead));
        final countAfterOpen = newest - baseline;
        expect(countAfterOpen, lessThan(newest - lastRead));
        expect(_pillText(tester), _expectedPillLabel(countAfterOpen));
      },
    );

    testWidgets('near-tail open with all unread visible never shows the pill', (
      tester,
    ) async {
      const count = 20;
      const lastRead = count - 4;
      const newest = count - 1;
      final ds = _PreloadedLikeSource(count);
      final controller = ChatScrollController()
        ..jumpTo(lastRead, alignment: 0.8);
      final lastSeen = ValueNotifier<int?>(lastRead);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(lastSeen.dispose);

      await tester.pumpWidget(
        _scaffoldWithPill(
          dataSource: ds,
          controller: controller,
          lastSeenNewestId: lastSeen,
          messageHeight: 20,
        ),
      );
      await tester.pump();

      expect(_pillOpacity(tester), 0.0);

      await tester.pump(const Duration(milliseconds: 16));

      expect(_pillText(tester), '0 new messages');
      expect(lastSeen.value, newest);
      expect(_pillOpacity(tester), 0.0);
    });

    testWidgets(
      'near-tail open with tall unread after small last-read shows full count',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 600,
                  child: Stack(
                    children: <Widget>[
                      ChatScrollView(
                        dataSource: ds,
                        controller: controller,
                        messageBuilder: (context, id, message, status) {
                          final height = id >= lastRead + 1 ? 800.0 : 60.0;
                          return SizedBox(
                            height: height,
                            child: Text(
                              message == null ? 'shimmer-$id' : 'msg-$id',
                            ),
                          );
                        },
                      ),
                      NewMessagesPill(
                        controller: controller,
                        dataSource: ds,
                        lastSeenNewestId: lastSeen,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        final range = controller.visibleRange.value;
        expect(range, isNotNull);
        expect(range!.anchorNextRow?.id, lastRead + 1);
        expect(
          visibleRowFillsBand(range.lastRow.height, range.paintBandHeight),
          isTrue,
        );
        expect(range.lastRow.id, lessThanOrEqualTo(range.lastId));
        expect(lastSeen.value, lastRead);
        expect(_pillText(tester), '2 new messages');
        expect(_pillOpacity(tester), greaterThan(0.0));
      },
    );

    testWidgets(
      'initial open does not mark tall sliver unread below threshold',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 600,
                  child: Stack(
                    children: <Widget>[
                      ChatScrollView(
                        reverse: true,
                        dataSource: ds,
                        controller: controller,
                        messageBuilder: (context, id, message, status) {
                          final height = id >= lastRead + 1 ? 1200.0 : 60.0;
                          return SizedBox(
                            height: height,
                            child: Text(
                              message == null ? 'shimmer-$id' : 'msg-$id',
                            ),
                          );
                        },
                      ),
                      NewMessagesPill(
                        controller: controller,
                        dataSource: ds,
                        lastSeenNewestId: lastSeen,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));

        final range = controller.visibleRange.value;
        expect(range, isNotNull);
        if (range!.lastRow.visibleFraction < 0.75) {
          expect(lastSeen.value, lastRead);
          expect(_pillText(tester), '2 new messages');
        }
      },
    );

    testWidgets('initial open uses lastRow.id not expanded lastId', (
      tester,
    ) async {
      const count = 10;
      const lastRead = count - 3;
      final ds = _PreloadedLikeSource(count);
      final controller = ChatScrollController()
        ..jumpTo(lastRead, alignment: 0.8);
      final lastSeen = ValueNotifier<int?>(lastRead);
      final bottomInset = ValueNotifier<double>(96);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(lastSeen.dispose);
      addTearDown(bottomInset.dispose);

      await _pumpDemoPillOpen(
        tester,
        widget: _scaffoldWithPill(
          dataSource: ds,
          controller: controller,
          lastSeenNewestId: lastSeen,
          bottomInset: bottomInset,
        ),
      );

      final range = controller.visibleRange.value;
      expect(range, isNotNull);
      expect(range!.lastRow.id, isNonNegative);
      expect(range.lastRow.id, lessThanOrEqualTo(range.lastId));
      expect(range.anchorNextRow?.id, lastRead + 1);
      expect(lastSeen.value, count - 1);
    });

    testWidgets(
      'initial open with two short unread visible below anchor clears pill',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        const newest = count - 1;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        final bottomInset = ValueNotifier<double>(96);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);
        addTearDown(bottomInset.dispose);

        await _pumpDemoPillOpen(
          tester,
          widget: _scaffoldWithPill(
            dataSource: ds,
            controller: controller,
            lastSeenNewestId: lastSeen,
            bottomInset: bottomInset,
          ),
        );

        final range = controller.visibleRange.value;
        expect(range, isNotNull);
        expect(range!.anchorNextRow?.id, lastRead + 1);
        expect(range.anchorNextRow!.visibleFraction, greaterThanOrEqualTo(0.75));
        expect(range.lastRow.id, newest);
        expect(lastSeen.value, newest);
        expect(_pillText(tester), '0 new messages');
        expect(_pillOpacity(tester), 0.0);
      },
    );

    testWidgets(
      'initial open does not mark medium partial unread below anchor',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        final bottomInset = ValueNotifier<double>(96);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);
        addTearDown(bottomInset.dispose);

        await _pumpDemoPillOpen(
          tester,
          widget: _scaffoldWithPill(
            dataSource: ds,
            controller: controller,
            lastSeenNewestId: lastSeen,
            bottomInset: bottomInset,
            messageBuilder: (context, id, message, status) {
              final height = id >= lastRead + 1 ? 400.0 : 60.0;
              return SizedBox(
                height: height,
                child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
              );
            },
          ),
        );

        expect(lastSeen.value, lastRead);
        expect(_pillText(tester), '2 new messages');
      },
    );

    testWidgets(
      'initial open does not batch-mark two large unread below anchor',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        final bottomInset = ValueNotifier<double>(96);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);
        addTearDown(bottomInset.dispose);

        await _pumpDemoPillOpen(
          tester,
          widget: _scaffoldWithPill(
            dataSource: ds,
            controller: controller,
            lastSeenNewestId: lastSeen,
            bottomInset: bottomInset,
            messageBuilder: (context, id, message, status) {
              final height = id >= lastRead + 1 ? 900.0 : 60.0;
              return SizedBox(
                height: height,
                child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
              );
            },
          ),
        );

        expect(lastSeen.value, lastRead);
        expect(_pillText(tester), '2 new messages');
        expect(_pillOpacity(tester), greaterThan(0.0));
      },
    );

    testWidgets(
      'initial open with demo long bubbles does not batch-mark unread',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final ds = _DemoLongUnreadSource(count, longFrom: lastRead + 1);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        final bottomInset = ValueNotifier<double>(96);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);
        addTearDown(bottomInset.dispose);

        await _pumpDemoPillOpen(
          tester,
          widget: _scaffoldWithPill(
            dataSource: ds,
            controller: controller,
            lastSeenNewestId: lastSeen,
            bottomInset: bottomInset,
            useDemoMessages: true,
          ),
        );

        final range = controller.visibleRange.value;
        expect(range, isNotNull);
        expect(range!.anyRowFillsBand, isTrue);
        expect(lastSeen.value, lastRead);
        expect(_pillText(tester), '2 new messages');
      },
    );

    testWidgets(
      'initial open does not batch-mark short then tall unread when both visible',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        final bottomInset = ValueNotifier<double>(96);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);
        addTearDown(bottomInset.dispose);

        await _pumpDemoPillOpen(
          tester,
          widget: _scaffoldWithPill(
            dataSource: ds,
            controller: controller,
            lastSeenNewestId: lastSeen,
            bottomInset: bottomInset,
            messageBuilder: (context, id, message, status) {
              final height = switch (id) {
                final n when n == lastRead + 1 => 80.0,
                final n when n >= lastRead + 2 => 520.0,
                _ => 60.0,
              };
              return SizedBox(
                height: height,
                child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
              );
            },
          ),
        );

        final range = controller.visibleRange.value;
        expect(range, isNotNull);
        expect(range!.lastRow.id - lastRead, greaterThanOrEqualTo(2));
        expect(range.anyRowFillsBand, isTrue);
        expect(lastSeen.value, lessThan(count - 1));
        expect(
          lastSeen.value,
          inInclusiveRange(lastRead, lastRead + 1),
          reason: 'may mark the short first unread, never the tall tail',
        );
        expect(_pillText(tester), '1 new message');
      },
    );

    testWidgets(
      'stable isAtTail on near-tail open does not mark all unread seen',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        const newest = count - 1;
        // Medium unread rows: both intersect the band but the tail fraction
        // stays well below the read threshold. Before the isAtTail fix, opening
        // here still jumped baseline to newest whenever the tail row pinned to
        // the bottom inset — matching the "two messages always read" report.
        const mediumUnreadHeight = 180.0;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        final bottomInset = ValueNotifier<double>(96);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);
        addTearDown(bottomInset.dispose);

        await _pumpDemoPillOpen(
          tester,
          widget: _scaffoldWithPill(
            dataSource: ds,
            controller: controller,
            lastSeenNewestId: lastSeen,
            bottomInset: bottomInset,
            messageBuilder: (context, id, message, status) {
              late final double height;
              if (id >= lastRead + 1) {
                height = mediumUnreadHeight;
              } else if (id >= lastRead - 5) {
                height = 20.0;
              } else {
                height = 60.0;
              }
              return SizedBox(
                height: height,
                child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
              );
            },
          ),
        );

        final range = controller.visibleRange.value;
        expect(range, isNotNull);
        expect(range!.lastRow.id, newest);
        expect(range.lastRow.visibleFraction, lessThan(0.75));
        expect(
          lastSeen.value,
          isNot(newest),
          reason:
              'tail pinned to the bottom inset must not snapshot newest as '
              'seen when the tail fraction is below threshold',
        );
        expect(_pillText(tester), isNot('0 new messages'));
      },
    );

    testWidgets(
      'initial open with large last-read and twenty medium unread does not over-mark',
      (tester) async {
        const unreadCount = 20;
        const count = 50;
        const lastRead = count - unreadCount - 1;
        const newest = count - 1;
        // Last-read anchor row: ~2.5× viewport. Unread rows: medium — taller
        // than the short-row cap but below band-fill height.
        const lastReadHeight = _viewportHeight * 2.5;
        const mediumUnreadHeight = _viewportHeight * 0.55;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        final bottomInset = ValueNotifier<double>(96);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);
        addTearDown(bottomInset.dispose);

        await _pumpDemoPillOpen(
          tester,
          widget: _scaffoldWithPill(
            dataSource: ds,
            controller: controller,
            lastSeenNewestId: lastSeen,
            bottomInset: bottomInset,
            messageBuilder: (context, id, message, status) {
              late final double height;
              if (id == lastRead) {
                height = lastReadHeight;
              } else if (id > lastRead && id <= newest) {
                height = mediumUnreadHeight;
              } else {
                height = 60.0;
              }
              return SizedBox(
                height: height,
                child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
              );
            },
          ),
        );

        final range = controller.visibleRange.value;
        expect(range, isNotNull);
        expect(controller.anchorMessageId, lastRead);
        expect(range!.anyRowFillsBand, isTrue);

        final baseline = lastSeen.value!;
        final markedOnOpen = baseline - lastRead;
        expect(
          markedOnOpen,
          lessThan(unreadCount),
          reason:
              'open sync must not prefix-mark all $unreadCount medium unread '
              'when the last-read anchor fills the band',
        );
        expect(baseline, lessThan(newest));
        expect(_pillText(tester), _expectedPillLabel(newest - baseline));
        expect(_pillOpacity(tester), greaterThan(0.0));
      },
    );

    testWidgets(
      'initial open with twenty unread does not mark short visible prefix',
      (tester) async {
        // Mirrors production logs: lastRead=9990, newest=10010, only ids
        // 9991–9992 visible as short rows with high fractions while 18 unread
        // remain off-screen — open sync must not advance the baseline.
        const unreadCount = 20;
        const count = 50;
        const lastRead = count - unreadCount - 1;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        final bottomInset = ValueNotifier<double>(96);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);
        addTearDown(bottomInset.dispose);

        await _pumpDemoPillOpen(
          tester,
          widget: _scaffoldWithPill(
            dataSource: ds,
            controller: controller,
            lastSeenNewestId: lastSeen,
            bottomInset: bottomInset,
            messageBuilder: (context, id, message, status) {
              late final double height;
              if (id > lastRead) {
                height = 60.0;
              } else if (id >= lastRead - 8) {
                height = 60.0;
              } else {
                height = 60.0;
              }
              return SizedBox(
                height: height,
                child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
              );
            },
          ),
        );

        final range = controller.visibleRange.value;
        expect(range, isNotNull);
        expect(controller.anchorMessageId, lastRead);
        expect(range!.lastRow.id - lastRead, lessThan(unreadCount));

        expect(lastSeen.value, lastRead);
        expect(_pillText(tester), _expectedPillLabel(unreadCount));
      },
    );

    testWidgets(
      'initial open with five unread marks visible short prefix on screen',
      (tester) async {
        // Mirrors production: lastRead=10005, newest=10010, five unread, only
        // 10006–10007 visible as short rows — those two should count on open.
        const unreadCount = 5;
        const count = 30;
        const lastRead = count - unreadCount - 1;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        final bottomInset = ValueNotifier<double>(96);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);
        addTearDown(bottomInset.dispose);

        await _pumpDemoPillOpen(
          tester,
          widget: _scaffoldWithPill(
            dataSource: ds,
            controller: controller,
            lastSeenNewestId: lastSeen,
            bottomInset: bottomInset,
            messageHeight: 60,
          ),
        );

        final range = controller.visibleRange.value;
        expect(range, isNotNull);
        expect(controller.anchorMessageId, lastRead);

        final baseline = lastSeen.value!;
        expect(baseline, greaterThan(lastRead));
        expect(
          count - 1 - baseline,
          lessThan(unreadCount),
          reason: 'visible short unread on open should reduce the pill count',
        );
      },
    );

    testWidgets(
      'initial open with six unread marks visible short prefix on screen',
      (tester) async {
        // Six unread with ~67% off-screen ratio — below the 0.75 defer
        // threshold, so visible prefix should still count on open (unlike the
        // count-based backlog rule that treated 6 like a large backlog).
        const unreadCount = 6;
        const count = 30;
        const lastRead = count - unreadCount - 1;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        final bottomInset = ValueNotifier<double>(96);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);
        addTearDown(bottomInset.dispose);

        await _pumpDemoPillOpen(
          tester,
          widget: _scaffoldWithPill(
            dataSource: ds,
            controller: controller,
            lastSeenNewestId: lastSeen,
            bottomInset: bottomInset,
            messageHeight: 60,
          ),
        );

        expect(lastSeen.value, greaterThan(lastRead));
        expect(count - 1 - lastSeen.value!, lessThan(unreadCount));
      },
    );

    testWidgets(
      'initial open with eight unread does not mark short visible prefix',
      (tester) async {
        // Mirrors production: 8 unread, only two visible (ratio 6/8 = 0.75).
        // At the defer threshold open sync must not prefix-mark.
        const unreadCount = 8;
        const count = 30;
        const lastRead = count - unreadCount - 1;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        final bottomInset = ValueNotifier<double>(96);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);
        addTearDown(bottomInset.dispose);

        await _pumpDemoPillOpen(
          tester,
          widget: _scaffoldWithPill(
            dataSource: ds,
            controller: controller,
            lastSeenNewestId: lastSeen,
            bottomInset: bottomInset,
            messageHeight: 60,
          ),
        );

        expect(lastSeen.value, lastRead);
        expect(_pillText(tester), _expectedPillLabel(unreadCount));
      },
    );

    testWidgets(
      'scrolling reduces count for tall band-fill unread after open',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 600,
                  child: Stack(
                    children: <Widget>[
                      ChatScrollView(
                        dataSource: ds,
                        controller: controller,
                        messageBuilder: (context, id, message, status) {
                          final height = id >= lastRead + 1 ? 800.0 : 60.0;
                          return SizedBox(
                            height: height,
                            child: Text(
                              message == null ? 'shimmer-$id' : 'msg-$id',
                            ),
                          );
                        },
                      ),
                      NewMessagesPill(
                        controller: controller,
                        dataSource: ds,
                        lastSeenNewestId: lastSeen,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(_pillText(tester), '2 new messages');
        expect(lastSeen.value, lastRead);

        await tester.fling(
          find.byType(ChatScrollView),
          const Offset(0, -1200),
          2500,
        );
        await tester.pumpAndSettle();

        expect(_pillText(tester), isNot('2 new messages'));
        expect(lastSeen.value, greaterThan(lastRead));
      },
    );

    testWidgets(
      'gradual scroll updates count as tall unread leave the viewport',
      (tester) async {
        const count = 60;
        const lastRead = 9;
        const unread = count - 1 - lastRead;
        final ds = _PreloadedLikeSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 600,
                  child: Stack(
                    children: <Widget>[
                      ChatScrollView(
                        dataSource: ds,
                        controller: controller,
                        messageBuilder: (context, id, message, status) =>
                            SizedBox(
                              height: 800,
                              child: Text(
                                message == null ? 'shimmer-$id' : 'msg-$id',
                              ),
                            ),
                      ),
                      NewMessagesPill(
                        controller: controller,
                        dataSource: ds,
                        lastSeenNewestId: lastSeen,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(_pillText(tester), _expectedPillLabel(unread));
        expect(lastSeen.value, lastRead);

        final scrollView = find.byType(ChatScrollView);
        await tester.fling(scrollView, const Offset(0, -2500), 800);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(lastSeen.value, greaterThan(lastRead));
        expect(_pillText(tester), isNot(_expectedPillLabel(unread)));
      },
    );

    testWidgets('slow repeated drags reduce tall unread count progressively', (
      tester,
    ) async {
      const count = 20;
      const lastRead = 9;
      final ds = _PreloadedLikeSource(count);
      final controller = ChatScrollController()
        ..jumpTo(lastRead, alignment: 0.8);
      final lastSeen = ValueNotifier<int?>(lastRead);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(lastSeen.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 600,
                child: Stack(
                  children: <Widget>[
                    ChatScrollView(
                      reverse: true,
                      dataSource: ds,
                      controller: controller,
                      messageBuilder: (context, id, message, status) =>
                          SizedBox(
                            height: 350,
                            child: Text(
                              message == null ? 'shimmer-$id' : 'msg-$id',
                            ),
                          ),
                    ),
                    NewMessagesPill(
                      controller: controller,
                      dataSource: ds,
                      lastSeenNewestId: lastSeen,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      const initialCount = count - 1 - lastRead;
      expect(_pillText(tester), _expectedPillLabel(initialCount));

      final scrollView = find.byType(ChatScrollView);
      for (var step = 0; step < 8; step++) {
        await tester.drag(scrollView, const Offset(0, -180));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(lastSeen.value, greaterThan(lastRead));
      expect(_pillText(tester), isNot(_expectedPillLabel(initialCount)));
    });

    testWidgets(
      'initial open suppresses pill until viewport read sync completes',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final ds = _TallMessagePreloadedSource(count);
        final controller = ChatScrollController()
          ..jumpTo(lastRead, alignment: 0.8);
        final lastSeen = ValueNotifier<int?>(lastRead);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(lastSeen.dispose);

        await tester.pumpWidget(
          _scaffoldWithTallPill(
            dataSource: ds,
            controller: controller,
            lastRead: lastRead,
            lastSeenNewestId: lastSeen,
            bottomPadding: ValueNotifier<double>(96),
          ),
        );

        await tester.pump();
        expect(_pillOpacity(tester), 0.0);

        await tester.pump(const Duration(milliseconds: 16));

        expect(_pillOpacity(tester), greaterThan(0.0));
        expect(_pillText(tester), '2 new messages');
      },
    );

    testWidgets('scrolling toward newer reduces unread count progressively', (
      tester,
    ) async {
      const count = 20;
      const lastRead = 9;
      final ds = _TallMessagePreloadedSource(count);
      final controller = ChatScrollController()
        ..jumpTo(lastRead, alignment: 0.8);
      final lastSeen = ValueNotifier<int?>(lastRead);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(lastSeen.dispose);

      await tester.pumpWidget(
        _scaffoldWithTallPill(
          dataSource: ds,
          controller: controller,
          lastRead: lastRead,
          lastSeenNewestId: lastSeen,
          bottomPadding: ValueNotifier<double>(96),
        ),
      );
      await tester.pump();

      final initialBaseline = lastSeen.value!;
      final initialCount = count - 1 - initialBaseline;
      expect(_pillText(tester), _expectedPillLabel(initialCount));

      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, -1200),
        2500,
      );
      await tester.pumpAndSettle();

      final afterScroll = _pillText(tester);
      expect(afterScroll, isNot(_expectedPillLabel(initialCount)));
      expect(afterScroll, isNot('0 new messages'));
      expect(lastSeen.value, greaterThan(initialBaseline));
    });

    testWidgets(
      'mount at tail → subsequent at-tail arrival keeps the pill at zero',
      (tester) async {
        // Sanity: when the user mounts already at tail and one new message
        // arrives, the layout auto-follows and `isAtTail` stays true
        // across the boundary fire — `_onBoundaryChanged` re-baselines so
        // the pill stays at zero (a *later* scroll-away does NOT count
        // those already-seen messages).
        final ds = _LateArrivingSource()..pushFirstArrival(count: 10);
        // Anchor at the newest known id — follow-tail pins us there.
        final controller = ChatScrollController()..jumpTo(9);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffoldWithPill(dataSource: ds, controller: controller),
        );
        await tester.pumpAndSettle();

        ds.appendOne();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));

        // If the user was at tail, follow-tail pinned the new message,
        // boundary listener re-baselined `_lastSeenNewestId`, count stays
        // at zero. We don't *require* atTail here (the controller is
        // free to consider the user as off-tail in this scaffold) — we
        // require that the rebaseline path keeps the count from
        // overflowing past 1. Either invisible-zero or visible-one are
        // acceptable; visible-two would be the regression.
        final text = _pillText(tester);
        final isZeroOrOne = text == '0 new messages' || text == '1 new message';
        expect(
          isZeroOrOne,
          isTrue,
          reason:
              'After one new arrival the count must not exceed 1; '
              'got "$text".',
        );
      },
    );

    testWidgets('near-tail open with tall messages keeps pill count stable', (
      tester,
    ) async {
      const count = 10;
      const lastRead = count - 3;
      final ds = _TallMessagePreloadedSource(count);
      final controller = ChatScrollController();
      final lastSeen = ValueNotifier<int?>(lastRead);

      await _mountNearTailTall(
        tester: tester,
        count: count,
        lastRead: lastRead,
        controller: controller,
        ds: ds,
        lastSeen: lastSeen,
      );

      expect(_pillText(tester), '2 new messages');

      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          _pillText(tester),
          '2 new messages',
          reason: 'frame $i: pill must not drop count during layout settling',
        );
      }
    });

    testWidgets('near-tail open pill stays visible for 500ms without scroll', (
      tester,
    ) async {
      const count = 10;
      const lastRead = count - 3;
      final ds = _TallMessagePreloadedSource(count);
      final controller = ChatScrollController();
      final lastSeen = ValueNotifier<int?>(lastRead);

      await _mountNearTailTall(
        tester: tester,
        count: count,
        lastRead: lastRead,
        controller: controller,
        ds: ds,
        lastSeen: lastSeen,
      );

      await tester.pump(const Duration(milliseconds: 500));

      expect(_pillText(tester), isNot('0 new messages'));
      expect(_pillText(tester), '2 new messages');
    });

    testWidgets('baseline unchanged when raw isAtTail flickers near tail', (
      tester,
    ) async {
      const count = 10;
      const lastRead = count - 3;
      const newest = count - 1;
      final ds = _TallMessagePreloadedSource(count);
      final controller = ChatScrollController();
      final lastSeen = ValueNotifier<int?>(lastRead);

      await _mountNearTailTall(
        tester: tester,
        count: count,
        lastRead: lastRead,
        controller: controller,
        ds: ds,
        lastSeen: lastSeen,
      );

      await _pumpSettleFrames(tester);

      expect(lastSeen.value, lastRead);
      expect(lastSeen.value, isNot(newest));
    });

    testWidgets('count recovers after brief raw isAtTail true', (tester) async {
      const count = 10;
      const lastRead = count - 3;
      final ds = _TallMessagePreloadedSource(count);
      final controller = ChatScrollController();
      final lastSeen = ValueNotifier<int?>(lastRead);

      await _mountNearTailTall(
        tester: tester,
        count: count,
        lastRead: lastRead,
        controller: controller,
        ds: ds,
        lastSeen: lastSeen,
      );

      await _pumpSettleFrames(tester, frameCount: 6);

      // Even if raw isAtTail flickered mid-sequence, stable at-tail must
      // not have latched and the label must show the full unread gap.
      expect(_pillText(tester), '2 new messages');
      expect(lastSeen.value, lastRead);
    });

    testWidgets(
      'tap pill from near-tail jumps to newest and advances baseline',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        const newest = count - 1;
        final ds = _TallMessagePreloadedSource(count);
        final controller = ChatScrollController();
        final lastSeen = ValueNotifier<int?>(lastRead);

        await _mountNearTailTall(
          tester: tester,
          count: count,
          lastRead: lastRead,
          controller: controller,
          ds: ds,
          lastSeen: lastSeen,
        );
        await tester.pump();

        expect(_pillText(tester), '2 new messages');

        await tester.tap(
          find.descendant(
            of: find.byType(NewMessagesPill),
            matching: find.byType(InkWell),
          ),
        );
        await tester.pump();
        expect(_pillText(tester), isNot('0 new messages'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(_pillText(tester), isNot('0 new messages'));
        }
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();

        expect(lastSeen.value, newest);
        expect(_pillText(tester), '0 new messages');
      },
    );

    testWidgets('tap pill animateTo newest without highlight', (tester) async {
      const count = 10;
      const lastRead = count - 3;
      const newest = count - 1;
      final ds = _TallMessagePreloadedSource(count);
      final controller = ChatScrollController();
      final lastSeen = ValueNotifier<int?>(lastRead);

      await _mountNearTailTall(
        tester: tester,
        count: count,
        lastRead: lastRead,
        controller: controller,
        ds: ds,
        lastSeen: lastSeen,
      );
      await tester.pump();

      await tester.tap(
        find.descendant(
          of: find.byType(NewMessagesPill),
          matching: find.byType(InkWell),
        ),
      );
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 200));

      expect(lastSeen.value, newest);
      expect(
        tester
            .renderObject<RenderChatScrollView>(find.byType(ChatScrollView))
            .debugHighlightTargetId,
        isNull,
      );
    });

    testWidgets('scroll to genuine tail dismisses pill and advances baseline', (
      tester,
    ) async {
      const count = 10;
      const lastRead = count - 3;
      const newest = count - 1;
      final ds = _TallMessagePreloadedSource(count);
      final controller = ChatScrollController();
      final lastSeen = ValueNotifier<int?>(lastRead);

      await _mountNearTailTall(
        tester: tester,
        count: count,
        lastRead: lastRead,
        controller: controller,
        ds: ds,
        lastSeen: lastSeen,
      );
      await tester.pump();

      await tester.drag(find.byType(ChatScrollView), const Offset(0, -800));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _pumpSettleFrames(tester, frameCount: 6);

      expect(lastSeen.value, newest);
      expect(_pillText(tester), '0 new messages');
    });

    testWidgets('one unread tall message stays visible until tail', (
      tester,
    ) async {
      const count = 10;
      const lastRead = count - 2;
      final ds = _TallMessagePreloadedSource(count);
      final controller = ChatScrollController();
      final lastSeen = ValueNotifier<int?>(lastRead);

      await _mountNearTailTall(
        tester: tester,
        count: count,
        lastRead: lastRead,
        controller: controller,
        ds: ds,
        lastSeen: lastSeen,
      );

      await _pumpSettleFrames(tester);
      expect(_pillText(tester), '1 new message');
    });

    testWidgets('three unread tall messages count stable', (tester) async {
      const count = 10;
      const lastRead = count - 4;
      final ds = _TallMessagePreloadedSource(count);
      final controller = ChatScrollController();
      final lastSeen = ValueNotifier<int?>(lastRead);

      await _mountNearTailTall(
        tester: tester,
        count: count,
        lastRead: lastRead,
        controller: controller,
        ds: ds,
        lastSeen: lastSeen,
      );

      await _pumpSettleFrames(tester);
      expect(_pillText(tester), '3 new messages');
    });

    testWidgets(
      'progressive scroll with tall messages reduces count without spurious zero',
      (tester) async {
        const count = 20;
        const lastRead = 9;
        final ds = _TallMessagePreloadedSource(count);
        final controller = ChatScrollController();
        final lastSeen = ValueNotifier<int?>(lastRead);

        await _mountNearTailTall(
          tester: tester,
          count: count,
          lastRead: lastRead,
          controller: controller,
          ds: ds,
          lastSeen: lastSeen,
          messageHeight: 200,
        );
        await tester.pump();

        expect(_pillText(tester), '10 new messages');

        await tester.fling(
          find.byType(ChatScrollView),
          const Offset(0, -1200),
          2500,
        );
        await tester.pumpAndSettle();

        final afterScroll = _pillText(tester);
        expect(afterScroll, isNot('10 new messages'));
        expect(afterScroll, isNot('0 new messages'));
        expect(lastSeen.value, greaterThan(lastRead));
      },
    );

    testWidgets('sliver lastId does not advance baseline below threshold', (
      tester,
    ) async {
      const count = 10;
      const lastRead = count - 4;
      final ds = _TallMessagePreloadedSource(count);
      final controller = ChatScrollController();
      final lastSeen = ValueNotifier<int?>(lastRead);

      await _mountNearTailTall(
        tester: tester,
        count: count,
        lastRead: lastRead,
        controller: controller,
        ds: ds,
        lastSeen: lastSeen,
        messageHeight: 350,
      );
      await tester.pump();

      expect(_pillText(tester), '3 new messages');
      expect(lastSeen.value, lastRead);

      // Small nudge — may bump lastId with only a sliver visible.
      controller.scrollBy(-40);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final range = controller.visibleRange.value;
      if (range != null &&
          range.lastId > lastRead &&
          range.lastRow.visibleFraction < 0.5) {
        expect(lastSeen.value, lastRead);
      }
    });

    testWidgets('crossing visibility threshold advances baseline', (
      tester,
    ) async {
      const count = 10;
      const lastRead = count - 4;
      final ds = _TallMessagePreloadedSource(count);
      final controller = ChatScrollController();
      final lastSeen = ValueNotifier<int?>(lastRead);

      await _mountNearTailTall(
        tester: tester,
        count: count,
        lastRead: lastRead,
        controller: controller,
        ds: ds,
        lastSeen: lastSeen,
        messageHeight: 350,
      );
      await tester.pump();

      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, -1200),
        2500,
      );
      await tester.pumpAndSettle();

      expect(lastSeen.value, greaterThan(lastRead));
    });

    testWidgets('fraction above threshold does not duplicate baseline writes', (
      tester,
    ) async {
      const count = 10;
      const lastRead = count - 4;
      final ds = _TallMessagePreloadedSource(count);
      final controller = ChatScrollController();
      final lastSeen = ValueNotifier<int?>(lastRead);
      var baselineWrites = 0;
      lastSeen.addListener(() => baselineWrites++);

      await _mountNearTailTall(
        tester: tester,
        count: count,
        lastRead: lastRead,
        controller: controller,
        ds: ds,
        lastSeen: lastSeen,
        messageHeight: 350,
      );
      await tester.pump();

      await tester.drag(find.byType(ChatScrollView), const Offset(0, -700));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final afterDrag = lastSeen.value;
      final writesAfterDrag = baselineWrites;

      await _pumpSettleFrames(tester, frameCount: 8);

      expect(lastSeen.value, afterDrag);
      expect(baselineWrites, writesAfterDrag);
    });

    testWidgets(
      'near-tail tall messages count stable across frames with fractions',
      (tester) async {
        const count = 10;
        const lastRead = count - 3;
        final ds = _TallMessagePreloadedSource(count);
        final controller = ChatScrollController();
        final lastSeen = ValueNotifier<int?>(lastRead);

        await _mountNearTailTall(
          tester: tester,
          count: count,
          lastRead: lastRead,
          controller: controller,
          ds: ds,
          lastSeen: lastSeen,
        );

        await _pumpSettleFrames(tester);
        expect(_pillText(tester), '2 new messages');
        expect(lastSeen.value, lastRead);
      },
    );

    testWidgets(
      'progressive scroll reduces count only after threshold per message',
      (tester) async {
        const count = 12;
        const lastRead = count - 4;
        final ds = _TallMessagePreloadedSource(count);
        final controller = ChatScrollController();
        final lastSeen = ValueNotifier<int?>(lastRead);

        await _mountNearTailTall(
          tester: tester,
          count: count,
          lastRead: lastRead,
          controller: controller,
          ds: ds,
          lastSeen: lastSeen,
          messageHeight: 350,
        );
        await tester.pump();

        expect(_pillText(tester), '3 new messages');

        await tester.drag(find.byType(ChatScrollView), const Offset(0, -350));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final mid = _pillText(tester);
        expect(mid, isNot('0 new messages'));
        expect(lastSeen.value, greaterThanOrEqualTo(lastRead));
      },
    );

    testWidgets('message taller than viewport advances at max band fill', (
      tester,
    ) async {
      const count = 5;
      const lastRead = 1;
      final ds = _TallMessagePreloadedSource(count);
      final controller = ChatScrollController();
      final lastSeen = ValueNotifier<int?>(lastRead);

      await _mountNearTailTall(
        tester: tester,
        count: count,
        lastRead: lastRead,
        controller: controller,
        ds: ds,
        lastSeen: lastSeen,
        messageHeight: 800,
      );
      await tester.pump();

      await tester.drag(find.byType(ChatScrollView), const Offset(0, -900));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _pumpSettleFrames(tester, frameCount: 4);

      expect(lastSeen.value, greaterThan(lastRead));
    });
  });
}
