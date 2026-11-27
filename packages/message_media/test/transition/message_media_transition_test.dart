/// The per-message transition clock: frames on the ticker, cells kept
/// across a transition, exiting items kept until their exit ends, reduce
/// motion, the diagnostics events, and a row in a chat list whose height
/// follows the frames.
///
/// **Seam:** `MessageMediaTransition` over a `ContentAssetScope` whose media
/// producer is a `FakeAssetProducer`; the chat list is a `ChatScrollView`
/// over an in-memory `ChatDataSource`.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart' hide RecordingDiagnostics;

MediaItem _item(String id, {ContentSize? size = const ContentSize(1, 1)}) =>
    MediaItem(
      id: MediaItemId(id),
      kind: MediaItemKind.photo,
      descriptor: ContentDescriptor(
        key: ContentKey.document('doc-$id'),
        size: size,
        fileName: 'private-$id.jpg',
      ),
    );

MediaLayout _layoutOf(
  MessageMediaPolicy policy,
  List<MediaItem> items, {
  double width = 360,
}) => policy.layout(
  MediaLayoutInput(
    items: items,
    availableWidth: width,
    displaySize: Size(width, 640),
  ),
);

final class _Message implements IChatMessage {
  _Message(this.id);

  @override
  final int id;

  @override
  String get sender => 'host';

  @override
  DateTime get createdAt => DateTime(2026);

  @override
  DateTime get updatedAt => DateTime(2026);
}

final class _Source extends ChatDataSource {
  _Source(int count) {
    for (var i = 0; i < count; i++) {
      upsertMessage(_Message(i));
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

const _frame = Duration(milliseconds: 16);

void main() {
  late FakeAssetProducer producer;
  late ContentAssetScope scope;

  setUp(() {
    producer = FakeAssetProducer();
    scope = ContentAssetScope.withMedia(producer: producer);
    addTearDown(scope.dispose);
  });

  Widget host(Widget child, {bool disableAnimations = false}) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: ContentAssetProvider(
        scope: scope,
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );

  Widget transition(
    MessageMediaPolicy policy,
    List<MediaItem> items, {
    MediaTransitionTrigger? trigger,
    MessageMediaTransitionBuilder? builder,
    ChatCorrelation correlation = ChatCorrelation.none,
  }) => MessageMediaTransition(
    layout: _layoutOf(policy, items),
    items: items,
    policy: policy,
    trigger: trigger,
    builder: builder,
    correlation: correlation,
  );

  Size sizeOf(WidgetTester tester) =>
      tester.getSize(find.byType(MessageMediaView));

  group('clock', () {
    testWidgets('the first layout shows at rest', (tester) async {
      const policy = MessageMediaPolicy.android();
      final items = [_item('a')];
      await tester.pumpWidget(host(transition(policy, items)));
      expect(sizeOf(tester), _layoutOf(policy, items).size);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a late-dimension change moves the size frame by frame', (
      tester,
    ) async {
      const policy = MessageMediaPolicy.android();
      final before = [_item('a', size: null)];
      final after = [_item('a', size: const ContentSize(400, 800))];
      final from = _layoutOf(policy, before).size;
      final to = _layoutOf(policy, after).size;
      expect(to.height, isNot(from.height));

      await tester.pumpWidget(host(transition(policy, before)));
      await tester.pumpWidget(host(transition(policy, after)));
      expect(sizeOf(tester), from, reason: 'the first frame is the old one');

      final heights = <double>[];
      for (var i = 0; i < 14; i++) {
        await tester.pump(_frame);
        heights.add(sizeOf(tester).height);
      }
      expect(heights.first, isNot(from.height));
      expect(heights.first, isNot(to.height));
      for (final (i, h) in heights.indexed.skip(1)) {
        expect(
          (h - from.height).abs(),
          greaterThanOrEqualTo((heights[i - 1] - from.height).abs() - 1e-6),
        );
      }
      await tester.pumpAndSettle();
      expect(sizeOf(tester), to);
    });

    testWidgets('a cell keeps its element through the transition, sized to '
        'the interpolated rect each frame', (tester) async {
      const policy = MessageMediaPolicy.android();
      final before = [_item('a', size: null)];
      final after = [_item('a', size: const ContentSize(400, 800))];
      await tester.pumpWidget(host(transition(policy, before)));
      final picture = find.descendant(
        of: find.byKey(const ValueKey('picture')),
        matching: find.byType(AssetView),
      );
      final state = tester.state(picture);

      await tester.pumpWidget(host(transition(policy, after)));
      await tester.pump(const Duration(milliseconds: 100));
      final cell = find.byKey(const ValueKey(MediaItemId('a')));
      expect(tester.getSize(cell), sizeOf(tester));
      expect(tester.state(picture), same(state));

      await tester.pumpAndSettle();
      expect(tester.state(picture), same(state));
    });

    testWidgets('a removed item stays painted until its exit ends', (
      tester,
    ) async {
      final recorder = RecordingDiagnostics.install();
      const policy = MessageMediaPolicy.android();
      await tester.pumpWidget(
        host(transition(policy, [_item('a'), _item('b')])),
      );
      await tester.pumpWidget(host(transition(policy, [_item('a')])));
      await tester.pump(const Duration(milliseconds: 60));

      final b = find.byKey(const ValueKey(MediaItemId('b')));
      expect(b, findsOneWidget);
      final opacity = tester.widget<Opacity>(
        find.descendant(of: b, matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, inExclusiveRange(0, 1));
      expect(recorder.whereOp(MediaOp.cellFailed), isEmpty);

      await tester.pump(const Duration(milliseconds: 80));
      expect(b, findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(MediaBoxCell), findsOneWidget);
    });

    testWidgets('the builder gets each frame and the media', (tester) async {
      const policy = MessageMediaPolicy.android();
      final progress = <double>[];
      Widget build(List<MediaItem> items) => transition(
        policy,
        items,
        builder: (context, frame, media) {
          progress.add(frame.progress);
          return media;
        },
      );
      await tester.pumpWidget(host(build([_item('a', size: null)])));
      await tester.pumpWidget(
        host(build([_item('a', size: const ContentSize(400, 800))])),
      );
      await tester.pumpAndSettle();
      expect(progress.first, 1);
      expect(progress[1], 0);
      expect(progress.last, 1);
      expect(progress.where((p) => p > 0 && p < 1), isNotEmpty);
    });

    testWidgets('reduce motion jumps to the end', (tester) async {
      final recorder = RecordingDiagnostics.install();
      const policy = MessageMediaPolicy.android();
      final after = [_item('a', size: const ContentSize(400, 800))];
      await tester.pumpWidget(
        host(
          transition(policy, [_item('a', size: null)]),
          disableAnimations: true,
        ),
      );
      await tester.pumpWidget(
        host(transition(policy, after), disableAnimations: true),
      );
      expect(sizeOf(tester), _layoutOf(policy, after).size);
      expect(tester.hasRunningAnimations, isFalse);
      final event = recorder.whereOp(MediaOp.transitionStarted).single;
      expect(event.fields['reduceMotion'], isTrue);
      expect(event.fields['durationMs'], 0);
    });

    testWidgets('desktop changes the layout at once', (tester) async {
      const policy = MessageMediaPolicy.desktop();
      final after = [_item('a', size: const ContentSize(400, 800))];
      await tester.pumpWidget(
        host(transition(policy, [_item('a', size: null)])),
      );
      await tester.pumpWidget(host(transition(policy, after)));
      expect(sizeOf(tester), _layoutOf(policy, after).size);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('diagnostics', () {
    const correlation = ChatCorrelation(chatId: 'chat-1', scrollId: 'm-1');

    testWidgets('a change reports transitionStarted with its counts', (
      tester,
    ) async {
      final recorder = RecordingDiagnostics.install();
      const policy = MessageMediaPolicy.android();
      await tester.pumpWidget(
        host(
          transition(policy, [
            _item('a'),
            _item('b'),
          ], correlation: correlation),
        ),
      );
      expect(recorder.whereOp(MediaOp.transitionStarted), isEmpty);

      await tester.pumpWidget(
        host(
          transition(policy, [
            _item('a'),
            _item('c'),
          ], correlation: correlation),
        ),
      );
      final event = recorder.whereOp(MediaOp.transitionStarted).single;
      expect(event.level, ChatEventLevel.trace);
      expect(event.category, ChatEventCategory.media);
      expect(event.fields, {
        'trigger': MediaTransitionTrigger.items,
        'entering': 1,
        'exiting': 1,
        'durationMs': 370,
        'reduceMotion': false,
      });
      expect(event.correlation.chatId, 'chat-1');
      expect(event.correlation.scrollId, 'm-1');
      expect(event.toString(), isNot(contains('private-')));
      await tester.pumpAndSettle();
    });

    testWidgets('the trigger: descriptor for the same items, the host\'s '
        'when given', (tester) async {
      final recorder = RecordingDiagnostics.install();
      const policy = MessageMediaPolicy.ios();
      await tester.pumpWidget(
        host(transition(policy, [_item('a', size: null)])),
      );
      await tester.pumpWidget(
        host(
          transition(policy, [_item('a', size: const ContentSize(900, 1600))]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        host(
          transition(policy, [
            _item('a', size: const ContentSize(1600, 900)),
          ], trigger: MediaTransitionTrigger.caption),
        ),
      );
      await tester.pumpAndSettle();

      final events = recorder.whereOp(MediaOp.transitionStarted);
      expect(events.map((e) => e.fields['trigger']), [
        MediaTransitionTrigger.descriptor,
        MediaTransitionTrigger.caption,
      ]);
      expect(events.first.fields['durationMs'], 400);
    });

    testWidgets('a change mid-flight reports transitionInterrupted', (
      tester,
    ) async {
      final recorder = RecordingDiagnostics.install();
      const policy = MessageMediaPolicy.android();
      await tester.pumpWidget(
        host(transition(policy, [_item('a', size: null)])),
      );
      await tester.pumpWidget(
        host(transition(policy, [_item('a', size: const ContentSize(9, 16))])),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final reached = sizeOf(tester);

      await tester.pumpWidget(
        host(transition(policy, [_item('a', size: const ContentSize(16, 9))])),
      );
      expect(sizeOf(tester), reached, reason: 'the next leg starts here');

      final interrupted = recorder
          .whereOp(MediaOp.transitionInterrupted)
          .single;
      expect(interrupted.level, ChatEventLevel.trace);
      expect(interrupted.fields['trigger'], MediaTransitionTrigger.descriptor);
      expect(interrupted.fields['elapsedMs'], inInclusiveRange(84, 100));
      expect(recorder.whereOp(MediaOp.transitionStarted), hasLength(2));
      await tester.pumpAndSettle();
    });
  });

  group('host inputs', () {
    testWidgets('a new revision starts a leg though the layout is equal', (
      tester,
    ) async {
      final recorder = RecordingDiagnostics.install();
      const policy = MessageMediaPolicy.android();
      final items = [_item('a')];
      final layout = _layoutOf(policy, items);
      Widget at(Object revision) => host(
        MessageMediaTransition(
          layout: layout,
          items: items,
          policy: policy,
          revision: revision,
          trigger: MediaTransitionTrigger.caption,
        ),
      );
      await tester.pumpWidget(at(1));
      await tester.pumpWidget(at(1));
      expect(recorder.whereOp(MediaOp.transitionStarted), isEmpty);
      await tester.pumpWidget(at(2));
      expect(
        recorder.whereOp(MediaOp.transitionStarted).single.fields['trigger'],
        MediaTransitionTrigger.caption,
      );
      await tester.pumpAndSettle();
    });

    testWidgets('the chrome context and selection progress reach the view', (
      tester,
    ) async {
      const policy = MessageMediaPolicy.android();
      final items = [_item('a')];
      const progress = AlwaysStoppedAnimation<double>(0.5);
      const context = MediaChromeContext(compact: true);
      await tester.pumpWidget(
        host(
          MessageMediaTransition(
            layout: _layoutOf(policy, items),
            items: items,
            policy: policy,
            chromeContext: context,
            selectionProgress: progress,
          ),
        ),
      );
      final view = tester.widget<MessageMediaView>(
        find.byType(MessageMediaView),
      );
      expect(view.chromeContext, context);
      expect(view.selectionProgress, same(progress));
    });
  });

  group('in a chat list', () {
    testWidgets('a late-dimension change animates the row\'s height and '
        'keeps the tail pinned', (tester) async {
      const policy = MessageMediaPolicy.android();
      const count = 12;
      const lastId = count - 1;
      final source = _Source(count);
      final controller = ChatScrollController()..jumpTo(lastId);
      final items = ValueNotifier([_item('a', size: null)]);
      addTearDown(source.dispose);
      addTearDown(controller.dispose);
      addTearDown(items.dispose);

      await tester.pumpWidget(
        host(
          SizedBox(
            width: 400,
            height: 600,
            child: ChatScrollView(
              dataSource: source,
              controller: controller,
              messageBuilder: (context, id, message, status, runLayout) {
                if (id != lastId) {
                  return SizedBox(height: 80, child: Text('msg-$id'));
                }
                return ValueListenableBuilder(
                  valueListenable: items,
                  builder: (context, items, _) => Align(
                    alignment: Alignment.centerLeft,
                    child: transition(policy, items),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);

      final view = find.byType(MessageMediaView);
      final bandBottom = tester.getBottomLeft(find.byType(ChatScrollView)).dy;
      final from = tester.getSize(view).height;
      double neighbourBottom() =>
          tester.getBottomLeft(find.text('msg-${lastId - 1}')).dy;
      expect(neighbourBottom(), closeTo(bandBottom - from, 0.5));

      items.value = [_item('a', size: const ContentSize(400, 800))];
      await tester.pump();
      final to = _layoutOf(policy, items.value).size.height;
      expect(to, greaterThan(from));

      var sawMid = false;
      for (var i = 0; i < 20; i++) {
        await tester.pump(_frame);
        final height = tester.getSize(view).height;
        if (height > from + 0.5 && height < to - 0.5) sawMid = true;
        // The row grows from the bottom edge: its bottom stays at the
        // band's bottom and the older row moves up by the growth.
        expect(
          tester.getBottomLeft(view).dy,
          closeTo(bandBottom, 0.5),
          reason: 'frame $i',
        );
        expect(
          neighbourBottom(),
          closeTo(bandBottom - height, 0.5),
          reason: 'frame $i',
        );
      }
      expect(sawMid, isTrue);
      await tester.pumpAndSettle();
      expect(tester.getSize(view).height, to);
      expect(controller.isAtTail.value, isTrue);
    });
  });
}
