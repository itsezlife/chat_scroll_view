/// The bubble layout helper: where the media, the caption, the header, the
/// time pill and each file's caption sit; the caption's wrap width; headers
/// truncating at the media's width; the inset; and the caption moving and
/// cross-fading on the media's clock, with its triggers reported.
///
/// **Seam:** `MessageMediaBubbleLayout` over a `ContentAssetScope` whose
/// media producer is a `FakeAssetProducer`; `MediaBubbleGeometry` pure.
library;

import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/testing.dart' hide RecordingDiagnostics;

import '../support/media_scopes.dart';

MediaItem _photo(String id, {ContentSize size = const ContentSize(800, 600)}) =>
    MediaItem(
      id: MediaItemId(id),
      kind: MediaItemKind.photo,
      descriptor: ContentDescriptor(
        key: ContentKey.document(id),
        size: size,
        fileName: 'private-$id.jpg',
      ),
    );

MediaItem _file(String id) => MediaItem(
  id: MediaItemId(id),
  kind: MediaItemKind.file,
  descriptor: ContentDescriptor(
    key: ContentKey.document(id),
    fileName: 'private-$id.pdf',
    byteSize: 2048,
  ),
);

const _padding = EdgeInsets.fromLTRB(10, 6, 10, 8);
const _captionKey = Key('caption');
const _headerKey = Key('header');
const _timeKey = Key('time');

Widget _box(Key key, double width, double height) =>
    SizedBox(key: key, width: width, height: height);

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

  ({MediaLayout layout, Widget widget}) bubble(
    MessageMediaPolicy policy,
    List<MediaItem> items,
    MediaBubbleComposition composition, {
    Widget? caption,
    Object? captionRevision,
    Widget? header,
    Widget? time,
    Map<MediaItemId, double> fileCaptionHeights = const {},
    Map<MediaItemId, Widget> fileCaptions = const {},
    ChatCorrelation correlation = ChatCorrelation.none,
  }) {
    final layout = policy.layout(
      composition.inputFor(
        MediaLayoutInput(
          text: MediaScopes.text,
          items: items,
          availableWidth: 360,
          displaySize: const Size(360, 640),
          fileCaptionHeights: fileCaptionHeights,
          chrome: const MediaLayoutChrome(timeWidth: 30),
        ),
      ),
    );
    return (
      layout: layout,
      widget: MessageMediaBubbleLayout(
        layout: layout,
        items: items,
        policy: policy,
        composition: composition,
        caption: caption,
        captionRevision: captionRevision,
        header: header,
        time: time,
        fileCaptions: fileCaptions,
        textPadding: _padding,
        correlation: correlation,
      ),
    );
  }

  Rect rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);
  Rect bubbleRect(WidgetTester tester) =>
      tester.getRect(find.byType(MessageMediaBubbleLayout));
  Rect mediaRect(WidgetTester tester) =>
      tester.getRect(find.byType(MessageMediaView));

  group('placement', () {
    testWidgets('a media bubble: the media at the inset on every side', (
      tester,
    ) async {
      const policy = MessageMediaPolicy.android();
      final b = bubble(policy, [_photo('a')], const MediaBubbleComposition());
      await tester.pumpWidget(MediaScopes.wrap(host(b.widget)));
      final media = mediaRect(tester);
      expect(media.topLeft, const Offset(2, 2));
      expect(media.size, b.layout.size);
      expect(bubbleRect(tester).size, b.layout.size + const Offset(4, 4));
    });

    testWidgets('desktop: flush, no inset', (tester) async {
      const policy = MessageMediaPolicy.desktop();
      final b = bubble(policy, [_photo('a')], const MediaBubbleComposition());
      await tester.pumpWidget(MediaScopes.wrap(host(b.widget)));
      expect(mediaRect(tester).topLeft, Offset.zero);
      expect(bubbleRect(tester).size, b.layout.size);
    });

    testWidgets('caption below: under the media in its padding', (
      tester,
    ) async {
      const policy = MessageMediaPolicy.android();
      final b = bubble(
        policy,
        [_photo('a')],
        const MediaBubbleComposition(hasCaption: true),
        caption: _box(_captionKey, 100, 40),
      );
      await tester.pumpWidget(MediaScopes.wrap(host(b.widget)));
      final media = mediaRect(tester);
      expect(media.topLeft, const Offset(2, 2));
      final caption = rectOf(tester, find.byKey(_captionKey));
      expect(caption.topLeft, Offset(10, media.bottom + 6));
      expect(bubbleRect(tester).height, caption.bottom + 8);
    });

    testWidgets('caption above (invertMedia): over the media; the media at '
        'the bottom inset with the time on it', (tester) async {
      const policy = MessageMediaPolicy.android();
      final b = bubble(
        policy,
        [_photo('a')],
        const MediaBubbleComposition(hasCaption: true, invertMedia: true),
        caption: _box(_captionKey, 100, 40),
        time: const SizedBox(key: _timeKey),
      );
      await tester.pumpWidget(MediaScopes.wrap(host(b.widget)));
      final caption = rectOf(tester, find.byKey(_captionKey));
      expect(caption.topLeft, const Offset(10, 6));
      final media = mediaRect(tester);
      expect(media.top, caption.bottom + 8);
      expect(bubbleRect(tester).height, media.bottom + 2);
      final pill = b.layout.timePill!;
      expect(rectOf(tester, find.byKey(_timeKey)), pill.shift(media.topLeft));
    });

    testWidgets('no time pill under a caption below: the time is not laid '
        'out on the media', (tester) async {
      const policy = MessageMediaPolicy.android();
      final b = bubble(
        policy,
        [_photo('a')],
        const MediaBubbleComposition(hasCaption: true),
        caption: _box(_captionKey, 100, 40),
        time: const SizedBox(key: _timeKey),
      );
      expect(b.layout.timePill, isNull);
      await tester.pumpWidget(MediaScopes.wrap(host(b.widget)));
      expect(find.byKey(_timeKey), findsNothing);
    });

    testWidgets('the caption wraps at the metrics width less its padding', (
      tester,
    ) async {
      for (final policy in const [
        MessageMediaPolicy.android(),
        MessageMediaPolicy.ios(),
      ]) {
        final b = bubble(
          policy,
          [_photo('a', size: const ContentSize(200, 600))],
          const MediaBubbleComposition(hasCaption: true),
          caption: _box(_captionKey, 2000, 20),
        );
        // A fresh bubble per policy: no transition between them.
        await tester.pumpWidget(MediaScopes.wrap(const SizedBox()));
        await tester.pumpWidget(MediaScopes.wrap(host(b.widget)));
        final metrics = b.layout.widthMetrics!;
        expect(
          rectOf(tester, find.byKey(_captionKey)).width,
          metrics.captionMaxWidth - _padding.horizontal,
          reason: policy.family.name,
        );
        // A caption wider than the media widens the bubble.
        expect(
          bubbleRect(tester).width,
          metrics.captionMaxWidth,
          reason: policy.family.name,
        );
      }
    });

    testWidgets('the header is laid out to the media width and never widens '
        'the bubble', (tester) async {
      const policy = MessageMediaPolicy.android();
      final plain = bubble(policy, [
        _photo('a', size: const ContentSize(300, 600)),
      ], const MediaBubbleComposition());
      await tester.pumpWidget(MediaScopes.wrap(host(plain.widget)));
      final width = bubbleRect(tester).width;

      final headed = bubble(
        policy,
        [_photo('a', size: const ContentSize(300, 600))],
        const MediaBubbleComposition(hasHeader: true),
        header: const Text(
          'A very long sender name that cannot fit in the media width at all',
          key: _headerKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
      await tester.pumpWidget(MediaScopes.wrap(host(headed.widget)));
      expect(bubbleRect(tester).width, width);
      final header = rectOf(tester, find.byKey(_headerKey));
      expect(header.left, 10);
      expect(header.right, lessThanOrEqualTo(width - 10));
      expect(header.width, width - _padding.horizontal);
      expect(mediaRect(tester).top, header.bottom + 8);
    });

    testWidgets('an album has one caption; a file stack a caption per file in '
        'its slot', (tester) async {
      const policy = MessageMediaPolicy.android();
      final album = bubble(
        policy,
        [_photo('a'), _photo('b')],
        const MediaBubbleComposition(hasCaption: true),
        caption: _box(_captionKey, 100, 30),
      );
      await tester.pumpWidget(MediaScopes.wrap(host(album.widget)));
      expect(find.byKey(_captionKey), findsOneWidget);
      expect(
        rectOf(tester, find.byKey(_captionKey)).top,
        mediaRect(tester).bottom + 6,
      );

      const a = MediaItemId('a');
      final stack = bubble(
        policy,
        [_file('a'), _file('b')],
        const MediaBubbleComposition(),
        fileCaptionHeights: {a: 30},
        fileCaptions: {
          a: _box(const Key('caption-a'), 120, 30),
          // No slot: not laid out.
          const MediaItemId('b'): _box(const Key('caption-b'), 120, 30),
        },
      );
      await tester.pumpWidget(MediaScopes.wrap(host(stack.widget)));
      final block = stack.layout.blocks.single as MediaBlock$FileStack;
      final slot = block.rowOf(a)!.captionSlot!;
      expect(
        rectOf(tester, find.byKey(const Key('caption-a'))).topLeft,
        mediaRect(tester).topLeft + slot.topLeft,
      );
      expect(find.byKey(const Key('caption-b')), findsNothing);
    });
  });

  group('transitions', () {
    testWidgets('invertMedia slides the caption to its other side on the '
        'clock and reports the trigger', (tester) async {
      final recorder = RecordingDiagnostics.install();
      const policy = MessageMediaPolicy.android();
      const correlation = ChatCorrelation(chatId: 'chat', scrollId: 'm1');
      Widget at({required bool inverted}) => host(
        bubble(
          policy,
          [_photo('a')],
          MediaBubbleComposition(hasCaption: true, invertMedia: inverted),
          caption: _box(_captionKey, 100, 40),
          correlation: correlation,
        ).widget,
      );
      await tester.pumpWidget(MediaScopes.wrap(at(inverted: false)));
      final below = rectOf(tester, find.byKey(_captionKey)).top;
      final height = bubbleRect(tester).height;

      await tester.pumpWidget(MediaScopes.wrap(at(inverted: true)));
      await tester.pump(const Duration(milliseconds: 125));
      final mid = rectOf(tester, find.byKey(_captionKey)).top;
      expect(mid, lessThan(below));
      expect(mid, greaterThan(6));
      expect(bubbleRect(tester).height, moreOrLessEquals(height));

      await tester.pumpAndSettle();
      expect(rectOf(tester, find.byKey(_captionKey)).top, 6);

      final event = recorder.whereOp(MediaOp.transitionStarted).single;
      expect(event.fields['trigger'], MediaTransitionTrigger.invertMedia);
      expect(event.correlation.scrollId, 'm1');
      expect(event.toString(), isNot(contains('private-')));
    });

    testWidgets('a caption edit cross-fades old into new and moves the size', (
      tester,
    ) async {
      final recorder = RecordingDiagnostics.install();
      const policy = MessageMediaPolicy.android();
      Widget at(String text, double height) => host(
        bubble(
          policy,
          [_photo('a')],
          const MediaBubbleComposition(hasCaption: true),
          caption: _box(ValueKey(text), 100, height),
          captionRevision: text,
        ).widget,
      );
      await tester.pumpWidget(MediaScopes.wrap(at('one', 20)));
      final before = bubbleRect(tester).height;
      await tester.pumpWidget(MediaScopes.wrap(at('two', 60)));
      await tester.pump(const Duration(milliseconds: 125));

      expect(find.byKey(const ValueKey('one')), findsOneWidget);
      expect(find.byKey(const ValueKey('two')), findsOneWidget);
      double opacityOf(String text) => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(ValueKey(text)),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      expect(opacityOf('one') + opacityOf('two'), moreOrLessEquals(1));
      expect(opacityOf('two'), inExclusiveRange(0, 1));
      final mid = bubbleRect(tester).height;
      expect(mid, inExclusiveRange(before, before + 40));

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('one')), findsNothing);
      expect(bubbleRect(tester).height, before + 40);
      expect(
        recorder.whereOp(MediaOp.transitionStarted).single.fields['trigger'],
        MediaTransitionTrigger.caption,
      );
    });

    testWidgets('a caption added fades in and grows the bubble', (
      tester,
    ) async {
      const policy = MessageMediaPolicy.android();
      final none = bubble(policy, [
        _photo('a'),
      ], const MediaBubbleComposition());
      await tester.pumpWidget(MediaScopes.wrap(host(none.widget)));
      final before = bubbleRect(tester).height;
      final added = bubble(
        policy,
        [_photo('a')],
        const MediaBubbleComposition(hasCaption: true),
        caption: _box(_captionKey, 100, 40),
      );
      await tester.pumpWidget(MediaScopes.wrap(host(added.widget)));
      await tester.pump(const Duration(milliseconds: 125));
      final mid = bubbleRect(tester).height;
      await tester.pumpAndSettle();
      final after = bubbleRect(tester).height;
      expect(mid, inExclusiveRange(before, after));
      expect(after, added.layout.size.height + 2 + 6 + 40 + 8);
    });

    testWidgets('desktop and reduce motion place the caption at once', (
      tester,
    ) async {
      for (final (policy, reduce) in const [
        (MessageMediaPolicy.desktop(), false),
        (MessageMediaPolicy.android(), true),
      ]) {
        Widget at({required bool inverted}) => host(
          bubble(
            policy,
            [_photo('a')],
            MediaBubbleComposition(hasCaption: true, invertMedia: inverted),
            caption: _box(_captionKey, 100, 40),
          ).widget,
          disableAnimations: reduce,
        );
        await tester.pumpWidget(MediaScopes.wrap(at(inverted: false)));
        await tester.pumpWidget(MediaScopes.wrap(at(inverted: true)));
        expect(
          rectOf(tester, find.byKey(_captionKey)).top,
          6,
          reason: policy.family.name,
        );
        expect(tester.hasRunningAnimations, isFalse);
        await tester.pumpWidget(MediaScopes.wrap(const SizedBox()));
      }
    });
  });

  group('geometry', () {
    MediaBubbleGeometry geometry(MediaBubbleText text, {Size? header}) =>
        MediaBubbleGeometry.compute(
          media: const Size(200, 100),
          mediaInset: 2,
          textPadding: _padding,
          text: text,
          header: header,
        );

    test('a card under the text keeps its own gap from it: the text gives '
        'up its bottom padding above the card', () {
      const caption = Size(120, 40);
      final card = MediaBubbleGeometry.compute(
        media: const Size(200, 100),
        mediaInset: 0,
        textPadding: _padding,
        text: const MediaBubbleText(caption: caption, presence: 1, above: 1),
        mediaHoldsTextGap: true,
      );
      expect(card.media.top, _padding.top + caption.height);
      final boxes = geometry(
        const MediaBubbleText(caption: caption, presence: 1, above: 1),
      );
      expect(boxes.media.top, _padding.top + caption.height + _padding.bottom);
    });

    test('above and below are the same height; between blends them', () {
      const caption = Size(120, 40);
      final below = geometry(
        const MediaBubbleText(caption: caption, presence: 1),
      );
      final above = geometry(
        const MediaBubbleText(caption: caption, presence: 1, above: 1),
      );
      expect(below.size, above.size);
      expect(below.media.top, 2);
      expect(below.caption.top, 102 + 6);
      expect(above.caption.top, 6);
      expect(above.media.top, 6 + 40 + 8);
      final mid = geometry(
        const MediaBubbleText(caption: caption, presence: 1, above: 0.5),
      );
      expect(mid.caption.top, (below.caption.top + above.caption.top) / 2);
      expect(mid.media.size, const Size(200, 100));
    });

    test('a caption absent has no height and no padding', () {
      final none = geometry(const MediaBubbleText(caption: Size(120, 40)));
      expect(none.size, const Size(204, 104));
      expect(none.caption.height, 0);
    });

    test('the caption widens the bubble, the header does not', () {
      expect(
        geometry(
          const MediaBubbleText(caption: Size(300, 20), presence: 1),
        ).size.width,
        320,
      );
      final headed = geometry(
        MediaBubbleText.none,
        header: const Size(400, 18),
      );
      expect(headed.size.width, 204);
      expect(headed.header, const Rect.fromLTWH(10, 6, 400, 18));
      expect(headed.media.top, 6 + 18 + 8);
    });
  });
}
