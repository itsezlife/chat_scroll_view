/// An outgoing message's media: the upload on each item's status control
/// (ring, then the sent check, then nothing once published), the item's
/// cross and its exit, no control on a failed send, the iOS flight from the
/// send origin, and the diagnostics of each.
///
/// **Seam:** a `MessageMediaTransition` row of a mounted `ChatScrollView`
/// with a `ChatSelectionController` (clock injected), over a
/// `ContentAssetScope` whose media producer is a `FakeAssetProducer` and
/// whose tracked transfers are mpx's `FakeTrackedTransfers`, under a
/// `MessageMediaStateScope`; observed through the fake's calls, the host's
/// callbacks, the status slot's load state, the widget tree and
/// `RecordingDiagnostics`.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart' hide RecordingDiagnostics;

import '../support/media_scopes.dart';

MediaItem _item(String id) => MediaItem(
  id: MediaItemId(id),
  kind: MediaItemKind.photo,
  descriptor: ContentDescriptor(
    key: ContentKey.document('doc-$id'),
    size: const ContentSize(4, 3),
    byteSize: 100,
    fileName: 'private-$id.jpg',
  ),
);

MediaKey _keyOf(String id) => ContentKey.document('doc-$id').mediaKey;

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
  _Source() {
    upsertMessage(_Message(0));
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: 0,
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

const _correlation = ChatCorrelation(
  chatId: 'chat-1',
  scrollId: '0',
  clientMessageId: 'client-1',
);

void main() {
  late FakeAssetProducer producer;
  late FakeTrackedTransfers tracked;
  late ContentAssetScope scope;
  late RecordingDiagnostics diagnostics;
  late ValueNotifier<List<MediaItem>> items;
  late List<MediaItemId> cancelled;
  late List<AssetLoadState> seen;
  late Duration now;

  setUp(() {
    producer = FakeAssetProducer();
    tracked = FakeTrackedTransfers();
    scope = ContentAssetScope.withMedia(producer: producer, tracked: tracked);
    diagnostics = RecordingDiagnostics.install();
    items = ValueNotifier([_item('a'), _item('b')]);
    cancelled = [];
    seen = [];
    now = Duration.zero;
    addTearDown(scope.dispose);
    addTearDown(items.dispose);
  });

  late MessageMediaState state;
  late ChatSelectionController selection;

  Future<void> pump(
    WidgetTester tester, {
    MessageMediaPolicy policy = const MessageMediaPolicy.android(),
    MediaSendState sendState = MediaSendState.sending,
    MediaItemRect? sendOrigin,
    bool reduceMotion = false,
    bool removesCancelled = true,
  }) async {
    state = MessageMediaState(sendOrigin: sendOrigin);
    selection = ChatSelectionController(
      policy: const ChatSelectionPolicy.mobile(),
      chatId: 'chat-1',
      monotonicClock: () => now,
    );
    final controller = ChatScrollController();
    final source = _Source();
    addTearDown(state.dispose);
    addTearDown(selection.dispose);
    addTearDown(controller.dispose);
    addTearDown(source.dispose);
    // Records what the status control is given, and keeps it.
    final recording = policy.copyWith(
      chrome: policy.chrome.copyWith(
        statusControl: (context, data, load, stock) {
          seen.add(load);
          return stock;
        },
      ),
    );
    await tester.pumpWidget(
      MediaScopes.wrap(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(400, 600),
              disableAnimations: reduceMotion,
            ),
            child: ContentAssetProvider(
              scope: scope,
              child: MessageMediaStateScope(
                state: state,
                child: Scaffold(
                  body: SizedBox(
                    width: 400,
                    height: 600,
                    child: ChatScrollView(
                      dataSource: source,
                      controller: controller,
                      selectionController: selection,
                      messageBuilder:
                          (context, id, message, status, runLayout) =>
                              ValueListenableBuilder(
                                valueListenable: items,
                                builder: (context, list, _) => Align(
                                  alignment: Alignment.centerRight,
                                  child: MessageMediaTransition(
                                    layout: recording.layout(
                                      MediaLayoutInput(
                                        text: MediaScopes.text,
                                        items: list,
                                        availableWidth: 300,
                                        displaySize: const Size(400, 640),
                                      ),
                                    ),
                                    items: list,
                                    policy: recording,
                                    selection: selection,
                                    messageId: id,
                                    correlation: _correlation,
                                    sendState: sendState,
                                    onItemCancelled: (id) {
                                      cancelled.add(id);
                                      if (!removesCancelled) return;
                                      items.value = [
                                        for (final item in items.value)
                                          if (item.id != id) item,
                                      ];
                                    },
                                  ),
                                ),
                              ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder cellOf(String id) => find.byKey(ValueKey(MediaItemId(id)));

  Offset statusAt(WidgetTester tester, String id) =>
      tester.getRect(cellOf(id)).center;

  Finder inCell(String id, Type type) =>
      find.descendant(of: cellOf(id), matching: find.byType(type));

  Future<void> drive(
    WidgetTester tester,
    String id,
    AssetTransfer value,
  ) async {
    tracked.drive(_keyOf(id), value);
    await tester.pump();
  }

  group('upload', () {
    testWidgets('a sending item shows the upload ring with its progress', (
      tester,
    ) async {
      await pump(tester);
      seen.clear();

      await drive(tester, 'a', const AssetTransfer.sending(50, 100));

      final load = seen.last;
      expect(load.transfer, const AssetTransfer.sending(50, 100));
      final status = load.status();
      expect(status.upload, isTrue);
      expect(status.icon, MediaStatusIcon.cancel);
      expect(status.progress, closeTo(0.5, 1e-9));
      expect(inCell('a', MediaSentCheck), findsNothing);
    });

    testWidgets('sent shows the check; none after the alias takes it away '
        'and keeps the local picture', (tester) async {
      await pump(tester);
      await drive(tester, 'a', const AssetTransfer.sending(100, 100));
      final picture = tester.element(inCell('a', ContentAssetView).first);

      await drive(tester, 'a', AssetTransfer.sent);
      expect(inCell('a', MediaSentCheck), findsOneWidget);
      expect(inCell('b', MediaSentCheck), findsNothing);

      await drive(tester, 'a', AssetTransfer.none);
      expect(inCell('a', MediaSentCheck), findsNothing);
      expect(
        tester.element(inCell('a', ContentAssetView).first),
        same(picture),
      );
    });

    testWidgets('a host sent check replaces the default', (tester) async {
      const base = MessageMediaPolicy.android();
      await pump(
        tester,
        policy: base.copyWith(
          chrome: base.chrome.copyWith(
            sentCheck: (context, data, load, stock) =>
                SizedBox(key: ValueKey('host-sent-${data.item.id}')),
          ),
        ),
      );

      await drive(tester, 'a', AssetTransfer.sent);

      expect(
        find.byKey(ValueKey('host-sent-${const MediaItemId('a')}')),
        findsOneWidget,
      );
      expect(find.byType(MediaSentCheck), findsNothing);
    });

    testWidgets('a failed send shows no media control and has no status '
        'part', (tester) async {
      await pump(tester, sendState: MediaSendState.failed);

      await drive(tester, 'a', const AssetTransfer.sending(10, 100));
      expect(inCell('a', MediaStatusControl), findsNothing);
      final hit = selection.resolveInlineHit(0, statusAt(tester, 'a'));
      expect(
        (hit! as ChatInlineHit$BodyPart).partId,
        const MediaHitPart(MediaItemId('a'), part: MediaPart.content),
      );

      await drive(tester, 'a', AssetTransfer.sent);
      expect(inCell('a', MediaSentCheck), findsNothing);
    });

    testWidgets('each change of state is reported once, with the item, its '
        'media key and message, and no file name', (tester) async {
      await pump(tester);

      await drive(tester, 'a', const AssetTransfer.sending(10, 100));
      await drive(tester, 'a', const AssetTransfer.sending(60, 100));
      await drive(tester, 'a', AssetTransfer.sent);
      await drive(tester, 'a', AssetTransfer.none);

      final events = diagnostics.whereOp(MediaOp.uploadState).toList();
      expect(
        [for (final event in events) event.fields['state']],
        ['sending', 'sent', 'none'],
      );
      expect(events.first.fields, {
        'state': 'sending',
        'sent': 10,
        'total': 100,
      });
      expect(events.first.level, ChatEventLevel.debug);
      final ids = events.first.correlation;
      expect(ids.mediaItemId, '${const MediaItemId('a')}');
      expect(ids.mediaKey, _keyOf('a').encoded);
      expect(ids.clientMessageId, 'client-1');
      expect(ids.scrollId, '0');
      for (final event in diagnostics.events) {
        expect('$event', isNot(contains('private')));
      }
    });
  });

  group('item cross', () {
    testWidgets('the cancel reaches the owner, the host hears the item, and '
        'it exits under the transition', (tester) async {
      await pump(tester);
      await drive(tester, 'a', const AssetTransfer.sending(10, 100));

      await tester.tapAt(statusAt(tester, 'a'));
      await tester.pump();

      expect(tracked.cancels, [_keyOf('a')]);
      expect(cancelled, const [MediaItemId('a')]);
      final event = diagnostics.whereOp(MediaOp.itemCancelled).single;
      expect(event.level, ChatEventLevel.info);
      expect(event.fields, {'albumBefore': 2, 'albumAfter': 1});
      expect(event.correlation.mediaItemId, '${const MediaItemId('a')}');
      expect(event.correlation.clientMessageId, 'client-1');

      // Android: a 120 ms fade at its last rect, then gone.
      await tester.pump(const Duration(milliseconds: 60));
      expect(cellOf('a'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(cellOf('a'), findsNothing);
      expect(cellOf('b'), findsOneWidget);
    });

    testWidgets('a burst of taps on the cross cancels once', (tester) async {
      // The host takes the item out later (its owner answers async), so
      // every tap of the burst lands on the cross.
      await pump(tester, removesCancelled: false);
      await drive(tester, 'a', const AssetTransfer.sending(10, 100));
      final at = statusAt(tester, 'a');

      for (var i = 0; i < 4; i++) {
        await tester.tapAt(at);
        now += const Duration(milliseconds: 50);
        await tester.pump();
      }

      expect(tracked.cancels, [_keyOf('a')]);
      expect(cancelled, const [MediaItemId('a')]);
      expect(diagnostics.whereOp(MediaOp.activationDropped), isNotEmpty);
    });

    testWidgets('a download cancel on a message not being sent is no cross', (
      tester,
    ) async {
      await pump(tester, sendState: MediaSendState.none);
      await drive(tester, 'a', const AssetTransfer.receiving(10, 100));

      await tester.tapAt(statusAt(tester, 'a'));
      await tester.pump();

      expect(tracked.cancels, [_keyOf('a')]);
      expect(cancelled, isEmpty);
      expect(diagnostics.whereOp(MediaOp.itemCancelled), isEmpty);
    });
  });

  group('flight policy', () {
    test('iOS flies 300 ms on its two curves; Android and desktop do not', () {
      expect(const MessageMediaPolicy.ios().sendFlight.flies, isTrue);
      expect(
        const MessageMediaPolicy.ios().sendFlight,
        const MediaSendFlightPolicy(
          duration: Duration(milliseconds: 300),
          horizontalCurve: Cubic(0.23, 1, 0.32, 1),
          verticalCurve: Cubic(0.199, 0.011, 0.279, 0.910),
        ),
      );
      expect(const MessageMediaPolicy.android().sendFlight.flies, isFalse);
      expect(const MessageMediaPolicy.desktop().sendFlight.flies, isFalse);
    });

    test('each axis moves on its own curve, from the origin to the cell', () {
      const policy = MediaSendFlightPolicy.ios();
      const from = Rect.fromLTWH(0, 0, 10, 10);
      const to = Rect.fromLTWH(100, 200, 50, 50);

      expect(policy.rectAt(from, to, 0), from);
      expect(policy.rectAt(from, to, 1), to);
      final mid = policy.rectAt(from, to, 0.5);
      final x = policy.horizontalCurve.transform(0.5);
      final y = policy.verticalCurve.transform(0.5);
      expect(mid.left, closeTo(100 * x, 1e-9));
      expect(mid.top, closeTo(200 * y, 1e-9));
      expect(mid.right, closeTo(10 + 140 * x, 1e-9));
      expect(mid.bottom, closeTo(10 + 240 * y, 1e-9));
    });
  });

  group('send origin flight', () {
    const origin = Rect.fromLTWH(20, 520, 60, 60);

    Finder flying() => find.byType(FittedBox);

    testWidgets('ios: the cell asks once and flies from the origin rect to '
        'its own', (tester) async {
      final asked = <MediaItemId>[];
      await pump(
        tester,
        policy: const MessageMediaPolicy.ios(),
        sendOrigin: (id) {
          asked.add(id);
          return id == const MediaItemId('a') ? origin : null;
        },
      );

      expect(asked, const [MediaItemId('a'), MediaItemId('b')]);
      // The first frame: at the origin, the cell hidden in place.
      expect(tester.getRect(flying()), origin);
      expect(
        tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: inCell('a', MediaBoxCell).first,
                    // The flight's own, not the viewer's hide.
                    matching: find.byWidgetPredicate(
                      (w) =>
                          w is Opacity &&
                          w.key != const ValueKey('viewer-source'),
                    ),
                  )
                  .first,
            )
            .opacity,
        0,
      );

      await tester.pump(const Duration(milliseconds: 150));
      final mid = tester.getRect(flying());
      final target = tester.getRect(cellOf('a'));
      expect(mid, isNot(origin));
      expect(mid, isNot(target));

      await tester.pump(const Duration(milliseconds: 200));
      expect(flying(), findsNothing);

      // A rebuild asks nothing more.
      items.value = [...items.value];
      await tester.pump();
      expect(asked, hasLength(2));

      final event = diagnostics.whereOp(MediaOp.sendOriginFlight).single;
      expect(event.fields, {
        'platform': MessageMediaPlatform.ios,
        'originPresent': true,
        'outcome': MediaFlightOutcome.flown,
        'reduceMotion': false,
      });
      expect(event.correlation.mediaItemId, '${const MediaItemId('a')}');
      expect(event.correlation.clientMessageId, 'client-1');
    });

    testWidgets('ios under reduce motion: asked, shown in place', (
      tester,
    ) async {
      var asked = 0;
      await pump(
        tester,
        policy: const MessageMediaPolicy.ios(),
        reduceMotion: true,
        sendOrigin: (id) {
          asked++;
          return origin;
        },
      );

      expect(asked, 2);
      expect(flying(), findsNothing);
      final events = diagnostics.whereOp(MediaOp.sendOriginFlight);
      expect(events, hasLength(2));
      expect(events.first.fields['outcome'], MediaFlightOutcome.skipped);
      expect(events.first.fields['reduceMotion'], isTrue);
    });

    for (final policy in const [
      MessageMediaPolicy.android(),
      MessageMediaPolicy.desktop(),
    ]) {
      testWidgets('${policy.family.name}: no flight, the origin is not '
          'asked', (tester) async {
        var asked = 0;
        await pump(
          tester,
          policy: policy,
          sendOrigin: (id) {
            asked++;
            return origin;
          },
        );

        expect(asked, 0);
        expect(flying(), findsNothing);
        expect(diagnostics.whereOp(MediaOp.sendOriginFlight), isEmpty);
      });
    }
  });
}
