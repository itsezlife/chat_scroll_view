/// The chrome over the cells: replaceable slots, the spoiler's cover and
/// reveal per platform over fake time, the revealed fact kept by the chat's
/// state, reduce motion, the options affordance's fade, and the slots'
/// diagnostics.
///
/// **Seam:** `MessageMediaView` under a `MessageMediaStateScope`, over a
/// `ContentAssetScope` whose media producer is a `FakeAssetProducer`.
library;

import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart' hide RecordingDiagnostics;

import '../support/media_scopes.dart';

MediaItem _item(
  String id, {
  MediaItemKind kind = MediaItemKind.photo,
  bool spoiler = false,
  String? fileName,
}) => MediaItem(
  id: MediaItemId(id),
  kind: kind,
  spoiler: spoiler,
  descriptor: ContentDescriptor(
    key: ContentKey.document('doc-$id'),
    size: const ContentSize(4, 3),
    fileName: fileName,
  ),
);

void main() {
  late ContentAssetScope scope;
  late MessageMediaState state;

  setUp(() {
    scope = ContentAssetScope.withMedia(producer: FakeAssetProducer());
    addTearDown(scope.dispose);
    state = MessageMediaState();
    addTearDown(state.dispose);
  });

  const correlation = ChatCorrelation(chatId: 'chat-1', scrollId: 'm-1');

  Future<void> pump(
    WidgetTester tester,
    MessageMediaPolicy policy,
    List<MediaItem> items, {
    double width = 375,
    bool reduceMotion = false,
    bool withScope = true,
    Animation<double>? selection,
  }) {
    final view = MessageMediaView(
      layout: policy.layout(
        MediaLayoutInput(
          text: MediaScopes.text,
          items: items,
          availableWidth: width,
          displaySize: Size(width, 640),
        ),
      ),
      items: items,
      policy: policy,
      correlation: correlation,
      selectionProgress: selection,
    );
    return tester.pumpWidget(
      MediaScopes.wrap(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ContentAssetProvider(
              scope: scope,
              child: Align(
                alignment: Alignment.topLeft,
                child: withScope
                    ? MessageMediaStateScope(state: state, child: view)
                    : view,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Size cellSize(WidgetTester tester, MediaItem item) =>
      tester.getSize(find.byKey(ValueKey(item.id)));

  Animation<double> controlsOf(WidgetTester tester, MediaItem item) => tester
      .widget<MediaControlsScope>(
        find.descendant(
          of: find.byKey(ValueKey(item.id)),
          matching: find.byType(MediaControlsScope),
        ),
      )
      .controls;

  group('slots', () {
    testWidgets('an options override replaces only the affordance', (
      tester,
    ) async {
      const base = MessageMediaPolicy.android();
      final policy = base.copyWith(
        chrome: base.chrome.copyWith(
          optionsAffordance: (context, data) =>
              const SizedBox(key: ValueKey('host-options')),
        ),
      );
      await pump(tester, policy, [_item('v', kind: MediaItemKind.video)]);

      expect(find.byKey(const ValueKey('host-options')), findsOneWidget);
      expect(find.byType(MediaOptionsDots), findsNothing);
      expect(find.byType(MediaBadge), findsOneWidget);
      expect(find.byType(MediaStatusControl), findsWidgets);
    });

    testWidgets('a status control override wraps the stock control and '
        'keeps the badge and the affordance', (tester) async {
      const base = MessageMediaPolicy.android();
      final seen = <MediaItemId>[];
      final policy = base.copyWith(
        chrome: base.chrome.copyWith(
          statusControl: (context, data, loadState, stock) {
            seen.add(data.item.id);
            return KeyedSubtree(
              key: const ValueKey('host-status'),
              child: stock,
            );
          },
        ),
      );
      final video = _item('v', kind: MediaItemKind.video);
      await pump(tester, policy, [video]);

      expect(find.byKey(const ValueKey('host-status')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('host-status')),
          matching: find.byType(MediaStatusControl),
        ),
        findsOneWidget,
      );
      expect(seen, contains(video.id));
      expect(find.byType(MediaBadge), findsOneWidget);
      expect(find.byType(MediaOptionsDots), findsOneWidget);
    });

    testWidgets('an info badge override replaces only the badge', (
      tester,
    ) async {
      const base = MessageMediaPolicy.ios();
      final policy = base.copyWith(
        chrome: base.chrome.copyWith(
          infoBadge: (context, data, loadState, stock) =>
              const SizedBox(key: ValueKey('host-badge')),
        ),
      );
      await pump(tester, policy, [_item('v', kind: MediaItemKind.video)]);

      expect(find.byKey(const ValueKey('host-badge')), findsOneWidget);
      expect(find.byType(MediaBadge), findsNothing);
      expect(find.byType(MediaStatusControl), findsWidgets);
    });

    testWidgets('a spoiler override replaces only the cover', (tester) async {
      const base = MessageMediaPolicy.desktop();
      final policy = base.copyWith(
        chrome: base.chrome.copyWith(
          spoiler: (context, data) =>
              const SizedBox(key: ValueKey('host-spoiler')),
        ),
      );
      final item = _item('p', spoiler: true);
      await pump(tester, policy, [item]);

      expect(find.byKey(const ValueKey('host-spoiler')), findsOneWidget);
      expect(find.byType(MediaSpoilerCover), findsNothing);
      expect(find.byType(MediaBoxCell), findsOneWidget);
    });

    testWidgets('the options dots sit at the placement\'s icon rect, on '
        'Android only', (tester) async {
      const policy = MessageMediaPolicy.android();
      final video = _item('v', kind: MediaItemKind.video);
      await pump(tester, policy, [video]);
      final layout = policy.layout(
        MediaLayoutInput(
          text: MediaScopes.text,
          items: [video],
          availableWidth: 375,
          displaySize: const Size(375, 640),
        ),
      );
      final cell = layout.cellOf(video.id)!;
      final affordance = policy.chrome.options.affordanceOf(
        cell,
        layout.blocks.single,
      )!;
      expect(
        tester.getRect(find.byType(MediaOptionsDots)),
        affordance.iconRect,
      );

      await pump(tester, const MessageMediaPolicy.ios(), [video]);
      expect(find.byType(MediaOptionsDots), findsNothing);
    });

    testWidgets('the affordance fades out as the selection checkbox comes '
        'in', (tester) async {
      final selection = AnimationController(vsync: const TestVSync());
      addTearDown(selection.dispose);
      await pump(tester, const MessageMediaPolicy.android(), [
        _item('v', kind: MediaItemKind.video),
      ], selection: selection);
      Opacity fade() => tester.widget(
        find
            .ancestor(
              of: find.byType(MediaOptionsDots),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(fade().opacity, 1);
      selection.value = 0.25;
      await tester.pump();
      expect(fade().opacity, 0.75);
    });
  });

  group('spoiler', () {
    testWidgets('a hidden spoiler covers the cell, hides the status control '
        'and the affordance', (tester) async {
      final item = _item('v', kind: MediaItemKind.video, spoiler: true);
      await pump(tester, const MessageMediaPolicy.android(), [item]);

      expect(find.byType(MediaSpoilerCover), findsOneWidget);
      expect(
        tester.getRect(find.byType(MediaSpoilerCover)),
        tester.getRect(find.byKey(ValueKey(item.id))),
      );
      expect(controlsOf(tester, item).value, 0);
      expect(find.byType(MediaOptionsDots), findsNothing);
      final ignore = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(MediaStatusControl).first,
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignore.ignoring, isTrue);
    });

    testWidgets('Android: a circle from the touch point over clamp(r · 0.3, '
        '250, 550) ms; controls fade in with it', (tester) async {
      final recorder = RecordingDiagnostics.install();
      final item = _item('p', spoiler: true, fileName: 'secret-file.jpg');
      await pump(tester, const MessageMediaPolicy.android(), [item]);
      final size = cellSize(tester, item);
      const origin = Offset(10, 10);
      final total = const MediaSpoilerReveal.circle().totalOf(size, origin);

      state.revealSpoiler(item.id, at: origin);
      await tester.pump();
      expect(find.byType(MediaSpoilerCover), findsOneWidget);

      await tester.pump(total ~/ 2);
      final mid = controlsOf(tester, item).value;
      expect(mid, inExclusiveRange(0, 1));
      final clip = tester.widget<ClipPath>(
        find.descendant(
          of: find.byType(MediaSpoilerCover),
          matching: find.byType(ClipPath),
        ),
      );
      final path = clip.clipper!.getClip(size);
      expect(path.contains(origin), isFalse, reason: 'the hole is open');

      await tester.pump(total - total ~/ 2 - const Duration(milliseconds: 1));
      expect(find.byType(MediaSpoilerCover), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2));
      expect(find.byType(MediaSpoilerCover), findsNothing);
      expect(controlsOf(tester, item).value, 1);

      final event = recorder.whereOp(MediaOp.spoilerRevealed).single;
      expect(event.level, ChatEventLevel.debug);
      expect(event.fields, {
        'platform': MessageMediaPlatform.android,
        'form': 'circle',
        'reduceMotion': false,
      });
      expect(event.correlation.scrollId, 'm-1');
      expect(event.correlation.mediaItemId, item.id.toString());
      expect(
        recorder.events.map((event) => event.toString()).join(),
        isNot(contains('secret-file')),
      );
    });

    testWidgets('iOS: the spot opens after its delay', (tester) async {
      final item = _item('p', spoiler: true);
      await pump(tester, const MessageMediaPolicy.ios(), [item]);
      final size = cellSize(tester, item);
      final origin = size.center(Offset.zero);
      final total = const MediaSpoilerReveal.spot().totalOf(size, origin);

      state.revealSpoiler(item.id);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(controlsOf(tester, item).value, 0, reason: 'still waiting');

      await tester.pump(total - const Duration(milliseconds: 91));
      expect(find.byType(MediaSpoilerCover), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2));
      expect(find.byType(MediaSpoilerCover), findsNothing);
    });

    testWidgets('desktop: the cover cross-fades over 200 ms', (tester) async {
      final item = _item('p', spoiler: true);
      await pump(tester, const MessageMediaPolicy.desktop(), [item]);

      state.revealSpoiler(item.id);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final fade = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(MediaSpoilerCover),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(fade.opacity, closeTo(0.5, 0.01));

      await tester.pump(const Duration(milliseconds: 101));
      expect(find.byType(MediaSpoilerCover), findsNothing);
    });

    testWidgets('the revealed state is kept across a re-layout and a new '
        'view, by the chat\'s state', (tester) async {
      final recorder = RecordingDiagnostics.install();
      const policy = MessageMediaPolicy.android();
      final item = _item('p', spoiler: true);
      await pump(tester, policy, [item]);
      state.revealSpoiler(item.id);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(MediaSpoilerCover), findsNothing);

      // Re-laid out narrower: still revealed.
      await pump(tester, policy, [item], width: 300);
      expect(find.byType(MediaSpoilerCover), findsNothing);

      // A view built anew over the same state: revealed at once.
      await tester.pumpWidget(MediaScopes.wrap(const SizedBox()));
      await pump(tester, policy, [item]);
      expect(find.byType(MediaSpoilerCover), findsNothing);
      expect(controlsOf(tester, item).value, 1);

      // Another item of the chat is still hidden.
      await pump(tester, policy, [item, _item('q', spoiler: true)]);
      expect(find.byType(MediaSpoilerCover), findsOneWidget);
      expect(recorder.whereOp(MediaOp.spoilerRevealed), hasLength(1));
    });

    testWidgets('reduce motion jumps to revealed', (tester) async {
      final recorder = RecordingDiagnostics.install();
      final item = _item('p', spoiler: true);
      await pump(tester, const MessageMediaPolicy.android(), [
        item,
      ], reduceMotion: true);

      state.revealSpoiler(item.id, at: Offset.zero);
      await tester.pump();
      expect(find.byType(MediaSpoilerCover), findsNothing);
      expect(controlsOf(tester, item).value, 1);
      expect(
        recorder.whereOp(MediaOp.spoilerRevealed).single.fields['reduceMotion'],
        isTrue,
      );
    });

    testWidgets('without a scope the view keeps a state of its own', (
      tester,
    ) async {
      final recorder = RecordingDiagnostics.install();
      final item = _item('p', spoiler: true);
      await pump(tester, const MessageMediaPolicy.android(), [
        item,
      ], withScope: false);
      expect(find.byType(MediaSpoilerCover), findsOneWidget);
      expect(recorder.whereOp(MediaStateOp.stateScopeMissing), hasLength(1));
    });

    testWidgets('a file row draws no spoiler cover', (tester) async {
      await pump(tester, const MessageMediaPolicy.android(), [
        _item('f', kind: MediaItemKind.file, spoiler: true),
      ]);
      expect(find.byType(MediaSpoilerCover), findsNothing);
    });
  });

  group('diagnostics', () {
    testWidgets('a spoiler slot that throws reports cellFailed and covers '
        'the cell opaquely', (tester) async {
      final recorder = RecordingDiagnostics.install();
      const base = MessageMediaPolicy.android();
      final policy = base.copyWith(
        chrome: base.chrome.copyWith(
          spoiler: (context, data) => throw StateError('no'),
        ),
      );
      final item = _item('p', spoiler: true, fileName: 'secret-file.jpg');
      await pump(tester, policy, [item]);

      expect(tester.takeException(), isA<StateError>());
      final event = recorder.whereOp(MediaOp.cellFailed).single;
      expect(event.fields, {
        'builder': MediaBuilder.spoiler,
        'errorType': 'StateError',
      });
      expect(event.correlation.chatId, 'chat-1');
      expect(event.correlation.mediaItemId, item.id.toString());
      expect(event.correlation.mediaKey, item.descriptor.key.mediaKey.encoded);
      expect(event.toString(), isNot(contains('secret-file')));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox && widget.color == const Color(0xFF000000),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an options slot that throws reports cellFailed and draws '
        'no affordance', (tester) async {
      final recorder = RecordingDiagnostics.install();
      const base = MessageMediaPolicy.android();
      final policy = base.copyWith(
        chrome: base.chrome.copyWith(
          optionsAffordance: (context, data) => throw StateError('no'),
        ),
      );
      await pump(tester, policy, [_item('v', kind: MediaItemKind.video)]);

      expect(tester.takeException(), isA<StateError>());
      expect(
        recorder.whereOp(MediaOp.cellFailed).single.fields['builder'],
        MediaBuilder.options,
      );
      expect(find.byType(MediaOptionsDots), findsNothing);
    });

    testWidgets('a status slot that throws reports cellFailed and shows the '
        'stock control', (tester) async {
      final recorder = RecordingDiagnostics.install();
      const base = MessageMediaPolicy.android();
      final policy = base.copyWith(
        chrome: base.chrome.copyWith(
          statusControl: (context, data, loadState, stock) =>
              throw StateError('no'),
        ),
      );
      await pump(tester, policy, [_item('v', kind: MediaItemKind.video)]);

      expect(tester.takeException(), isA<StateError>());
      expect(
        recorder.whereOp(MediaOp.cellFailed).first.fields['builder'],
        MediaBuilder.statusControl,
      );
      expect(find.byType(MediaStatusControl), findsWidgets);
    });
  });
}
