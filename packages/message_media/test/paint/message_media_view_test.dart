/// The paint step: cells at their rects through the asset pipeline, keyed
/// by item, built by replaceable builders.
///
/// **Seam:** `MessageMediaView` over a `ContentAssetScope` whose media
/// producer is a `FakeAssetProducer`.
library;

import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';

MediaItem _item(
  String id, {
  MediaItemKind kind = MediaItemKind.photo,
  ContentSize? size = const ContentSize(1, 1),
  String? fileName,
}) => MediaItem(
  id: MediaItemId(id),
  kind: kind,
  descriptor: ContentDescriptor(
    key: ContentKey.document('doc-$id'),
    size: size,
    fileName: fileName,
  ),
);

void main() {
  late FakeAssetProducer producer;
  late ContentAssetScope scope;

  setUp(() {
    producer = FakeAssetProducer();
    scope = ContentAssetScope.withMedia(producer: producer);
    addTearDown(scope.dispose);
  });

  Future<void> pump(WidgetTester tester, Widget view) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ContentAssetProvider(
        scope: scope,
        child: Align(alignment: Alignment.topLeft, child: view),
      ),
    ),
  );

  MessageMediaView viewOf(
    MessageMediaPolicy policy,
    List<MediaItem> items, {
    double width = 375,
    MediaCaptionPosition caption = MediaCaptionPosition.none,
    ChatCorrelation correlation = ChatCorrelation.none,
  }) => MessageMediaView(
    layout: policy.layout(
      MediaLayoutInput(
        items: items,
        availableWidth: width,
        displaySize: Size(width, 640),
        captionPosition: caption,
      ),
    ),
    items: items,
    policy: policy,
    correlation: correlation,
  );

  group('cells', () {
    testWidgets('each cell sits at its rect, the view the layout\'s size', (
      tester,
    ) async {
      const policy = MessageMediaPolicy.android();
      final items = [_item('a'), _item('b')];
      final view = viewOf(policy, items);
      await pump(tester, view);

      expect(tester.getSize(find.byType(MessageMediaView)), view.layout.size);
      for (final cell in view.layout.cells) {
        final box = find.byKey(ValueKey(cell.itemId));
        expect(tester.getTopLeft(box), cell.rect.topLeft);
        expect(tester.getSize(box), cell.rect.size);
      }
    });

    testWidgets('a cell keeps its element and binding across a re-layout '
        'that moves it', (tester) async {
      const policy = MessageMediaPolicy.android();
      final a = _item('a');
      final b = _item('b');
      await pump(tester, viewOf(policy, [a, b]));
      State<StatefulWidget> stateOf(MediaItem item) => tester.state(
        find.descendant(
          of: find.byKey(ValueKey(item.id)),
          matching: find.byType(AssetView),
        ),
      );
      final before = stateOf(a);
      final attempts = producer.attempts.length;
      final rectBefore = tester.getRect(find.byKey(ValueKey(a.id)));

      // The order flips: a moves to b's place.
      await pump(tester, viewOf(policy, [b, a]));

      expect(tester.getRect(find.byKey(ValueKey(a.id))), isNot(rectBefore));
      expect(stateOf(a), same(before));
      expect(producer.attempts.length, attempts);
    });

    testWidgets('a cell keeps its binding when the layout resizes it', (
      tester,
    ) async {
      const policy = MessageMediaPolicy.android();
      final a = _item('a', size: const ContentSize(16, 9));
      await pump(tester, viewOf(policy, [a], width: 375));
      final before = tester.state(find.byType(AssetView));
      final attempts = producer.attempts.length;

      await pump(tester, viewOf(policy, [a], width: 320));

      expect(tester.state(find.byType(AssetView)), same(before));
      expect(producer.attempts.length, attempts);
    });

    testWidgets('boxes and rows draw through the asset pipeline with the '
        'loading stages\' control and badge', (tester) async {
      const policy = MessageMediaPolicy.android();
      final items = [
        _item('p'),
        _item('v', kind: MediaItemKind.video),
        _item('f', kind: MediaItemKind.file, size: null),
      ];
      await pump(tester, viewOf(policy, items));

      ContentAssetView viewIn(String id) => tester.widget(
        find.descendant(
          of: find.byKey(ValueKey(MediaItemId(id))),
          matching: find.byType(ContentAssetView),
        ),
      );
      expect(viewIn('p').content, items[0].descriptor.key);
      expect(viewIn('p').status, const MediaStatusMode.control());
      expect(viewIn('p').badge, isFalse);
      expect(viewIn('v').badge, isTrue);
      expect(find.byType(MediaBoxCell), findsNWidgets(2));
      expect(find.byType(MediaRowCell), findsOneWidget);
      expect(viewIn('f').status, const MediaStatusMode.control());
    });

    testWidgets('a box clips to its resolved radii', (tester) async {
      const policy = MessageMediaPolicy.android();
      final view = viewOf(policy, [_item('a')]);
      await pump(tester, view);
      final clip = tester.widget<ClipRRect>(
        find.descendant(
          of: find.byType(MediaBoxCell),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(clip.borderRadius, BorderRadius.circular(15));
    });
  });

  group('builders', () {
    testWidgets('a box builder override replaces only boxes', (tester) async {
      const marker = Key('host-box');
      const base = MessageMediaPolicy.android();
      final policy = base.copyWith(
        cells: base.cells.copyWith(
          box: (context, data) => const SizedBox.expand(key: marker),
        ),
      );
      final items = [
        _item('p'),
        _item('f', kind: MediaItemKind.file, size: null),
      ];
      await pump(tester, viewOf(policy, items));

      expect(find.byKey(marker), findsOneWidget);
      expect(find.byType(MediaBoxCell), findsNothing);
      expect(find.byType(MediaRowCell), findsOneWidget);
    });

    testWidgets('a row builder override replaces only rows, custom kinds '
        'included', (tester) async {
      final seen = <MediaItemKind>[];
      const base = MessageMediaPolicy.ios();
      final policy = base.copyWith(
        cells: base.cells.copyWith(
          row: (context, data) {
            seen.add(data.item.kind);
            return const SizedBox.expand();
          },
        ),
      );
      final items = [
        _item('p'),
        _item('f', kind: MediaItemKind.file, size: null),
        _item('c', kind: const MediaItemKind.custom('poll'), size: null),
      ];
      await pump(tester, viewOf(policy, items));

      expect(seen, [MediaItemKind.file, const MediaItemKind.custom('poll')]);
      expect(find.byType(MediaBoxCell), findsOneWidget);
      expect(find.byType(MediaRowCell), findsNothing);
    });

    testWidgets('a builder gets the cell, item, block, family and autoplay', (
      tester,
    ) async {
      MediaCellData? data;
      const base = MessageMediaPolicy.desktop();
      final policy = base.copyWith(
        cells: base.cells.copyWith(
          box: (context, d) {
            data = d;
            return const SizedBox.expand();
          },
        ),
      );
      final item = _item('g', kind: MediaItemKind.animation);
      final view = viewOf(policy, [item]);
      await pump(tester, view);

      expect(data!.cell, view.layout.cellOf(item.id));
      expect(data!.item, item);
      expect(data!.block, view.layout.blocks.single);
      expect(data!.family, MessageMediaPlatform.desktop);
      expect(data!.autoplay, isTrue);
    });
  });

  group('fit', () {
    testWidgets('a crop draws one cover picture', (tester) async {
      await pump(
        tester,
        viewOf(const MessageMediaPolicy.android(), [
          _item('a', size: const ContentSize(4, 1)),
        ]),
      );
      final views = tester.widgetList<ContentAssetView>(
        find.byType(ContentAssetView),
      );
      expect(views.single.preset.profile.fit, AssetFit.cover);
    });

    testWidgets('blurFit draws the whole picture over bars of the same '
        'entry, blurred and still', (tester) async {
      const base = MessageMediaPolicy.android();
      final policy = base.copyWith(
        layoutStep: (base.layoutStep as MediaLayoutPolicy).copyWith(
          fit: const MediaFitPolicy.android().copyWith(
            photo: const MediaFit.blurFit(),
          ),
        ),
      );
      // A wide panorama: the minimum height widens the box's aspect.
      await pump(
        tester,
        viewOf(policy, [_item('a', size: const ContentSize(8, 1))]),
      );

      final views = tester
          .widgetList<ContentAssetView>(find.byType(ContentAssetView))
          .toList();
      expect(views, hasLength(2));
      final [bars, picture] = views;
      expect(bars.preset.profile.fit, AssetFit.cover);
      expect(bars.preset.profile.animate, isFalse);
      expect(bars.status, MediaStatusMode.none);
      expect(picture.preset.profile.fit, AssetFit.contain);
      expect(bars.preset.spec, picture.preset.spec);
      expect(
        find.ancestor(
          of: find.byWidget(bars),
          matching: find.byType(ImageFiltered),
        ),
        findsOneWidget,
      );
    });

    test('drawIn per fit', () {
      const box = Size(300, 120);
      const wide = Size(800, 100);
      expect(const MediaFit.crop().drawIn(box, wide), MediaFitDraw.crop);
      expect(
        const MediaFit.blurFit().drawIn(box, wide),
        MediaFitDraw.blurredBars,
      );
      // 300 × 120 against 8:1: the whole picture is 300 × 37.5, bars of
      // 82.5 in all.
      expect(
        const MediaFit.blurFit(overflowCrop: 82.5).drawIn(box, wide),
        MediaFitDraw.crop,
      );
      expect(
        const MediaFit.blurFit(overflowCrop: 82).drawIn(box, wide),
        MediaFitDraw.blurredBars,
      );
      // 2.5 against 8: a crop keeps 31 %.
      expect(
        const MediaFit.cropIfVisible(0.3).drawIn(box, wide),
        MediaFitDraw.crop,
      );
      expect(
        const MediaFit.cropIfVisible(0.75).drawIn(box, wide),
        MediaFitDraw.blurredBars,
      );
      // Nothing to bar: unknown size, the box's own aspect.
      expect(const MediaFit.blurFit().drawIn(box, null), MediaFitDraw.crop);
      expect(
        const MediaFit.blurFit().drawIn(box, const Size(600, 240)),
        MediaFitDraw.crop,
      );
    });
  });

  group('autoplay', () {
    MediaBlock blockOf(List<MediaCell> cells) => MediaBlock.mosaic(
      rect: const Rect.fromLTWH(0, 0, 300, 300),
      cells: cells,
    );
    MediaCell cell(
      MediaItemKind kind, {
      MediaNeighbour left = MediaNeighbour.bubbleEdge,
      MediaNeighbour right = MediaNeighbour.bubbleEdge,
    }) => MediaCell(
      itemId: const MediaItemId('a'),
      kind: kind,
      rect: const Rect.fromLTWH(0, 0, 300, 150),
      neighbours: MediaNeighbours(
        top: MediaNeighbour.bubbleEdge,
        bottom: MediaNeighbour.item,
        left: left,
        right: right,
      ),
    );

    test('Android: video plays alone or across the whole block', () {
      const policy = MediaAutoplayPolicy.android();
      final single = cell(MediaItemKind.video);
      expect(policy.plays(single, blockOf([single])), isTrue);
      final fullWidth = cell(MediaItemKind.video);
      final other = cell(MediaItemKind.photo);
      expect(policy.plays(fullWidth, blockOf([fullWidth, other])), isTrue);
      final half = cell(MediaItemKind.video, right: MediaNeighbour.item);
      expect(policy.plays(half, blockOf([half, other])), isFalse);
    });

    test('animations play on every platform; video per platform; photos '
        'and files never', () {
      final video = cell(MediaItemKind.video, right: MediaNeighbour.item);
      final gif = cell(MediaItemKind.animation, right: MediaNeighbour.item);
      final block = blockOf([video, gif]);
      for (final policy in const [
        MediaAutoplayPolicy.android(),
        MediaAutoplayPolicy.ios(),
        MediaAutoplayPolicy.desktop(),
      ]) {
        expect(policy.plays(gif, block), isTrue);
        expect(policy.plays(cell(MediaItemKind.photo), block), isFalse);
        expect(policy.plays(cell(MediaItemKind.file), block), isFalse);
      }
      expect(const MediaAutoplayPolicy.ios().plays(video, block), isTrue);
      expect(const MediaAutoplayPolicy.desktop().plays(video, block), isFalse);
      expect(MediaAutoplayPolicy.off.plays(gif, block), isFalse);
    });

    testWidgets('a playing cell animates its picture without a play action; '
        'a still video offers play', (tester) async {
      const playing = MessageMediaPolicy.android();
      await pump(
        tester,
        viewOf(playing, [_item('v', kind: MediaItemKind.video)]),
      );
      var view = tester.widget<ContentAssetView>(find.byType(ContentAssetView));
      expect(view.preset.profile.animate, isTrue);
      expect(view.status, const MediaStatusMode.control());

      final still = playing.copyWith(autoplay: MediaAutoplayPolicy.off);
      await pump(
        tester,
        viewOf(still, [_item('v', kind: MediaItemKind.video)]),
      );
      view = tester.widget<ContentAssetView>(find.byType(ContentAssetView));
      expect(view.preset.profile.animate, isFalse);
      expect(view.status, const MediaStatusMode.control(playAction: true));
    });

    test('the per-platform values', () {
      expect(
        const MessageMediaPolicy.android().autoplay,
        const MediaAutoplayPolicy(
          animations: true,
          video: MediaVideoAutoplay.singleOrFullWidth,
        ),
      );
      expect(
        const MessageMediaPolicy.ios().autoplay,
        const MediaAutoplayPolicy(
          animations: true,
          video: MediaVideoAutoplay.always,
        ),
      );
      expect(
        const MessageMediaPolicy.desktop().autoplay,
        const MediaAutoplayPolicy(
          animations: true,
          video: MediaVideoAutoplay.never,
        ),
      );
    });
  });

  group('diagnostics', () {
    const correlation = ChatCorrelation(chatId: 'chat-1', scrollId: 'm-1');

    testWidgets('a builder that throws reports cellFailed and draws nothing', (
      tester,
    ) async {
      final recorder = RecordingDiagnostics.install();
      const base = MessageMediaPolicy.android();
      final policy = base.copyWith(
        cells: base.cells.copyWith(
          box: (context, data) => throw StateError('no'),
        ),
      );
      final item = _item('a', fileName: 'holiday-secret.jpg');
      await pump(tester, viewOf(policy, [item], correlation: correlation));

      expect(tester.takeException(), isA<StateError>());
      final event = recorder.whereOp(MediaOp.cellFailed).single;
      expect(event.level, ChatEventLevel.error);
      expect(event.category, ChatEventCategory.media);
      expect(event.fields, {'builder': 'box', 'errorType': 'StateError'});
      expect(event.correlation.chatId, 'chat-1');
      expect(event.correlation.scrollId, 'm-1');
      expect(event.correlation.mediaItemId, item.id.toString());
      expect(event.correlation.mediaKey, item.descriptor.key.mediaKey.encoded);
      expect(event.toString(), isNot(contains('holiday-secret')));
      expect(find.byType(MediaBoxCell), findsNothing);
    });

    testWidgets('a cell whose item was not given reports cellFailed', (
      tester,
    ) async {
      final recorder = RecordingDiagnostics.install();
      const policy = MessageMediaPolicy.android();
      final item = _item('a');
      await pump(
        tester,
        MessageMediaView(
          layout: policy.layout(
            MediaLayoutInput(items: [item], availableWidth: 375),
          ),
          items: const [],
          policy: policy,
          correlation: correlation,
        ),
      );

      final event = recorder.whereOp(MediaOp.cellFailed).single;
      expect(event.fields, {'builder': 'box', 'errorType': 'missingItem'});
      expect(event.correlation.mediaItemId, item.id.toString());
      expect(event.correlation.mediaKey, isNull);
    });

    testWidgets('cells that build report nothing', (tester) async {
      final recorder = RecordingDiagnostics.install();
      await pump(
        tester,
        viewOf(const MessageMediaPolicy.ios(), [
          _item('a'),
          _item('f', kind: MediaItemKind.file, size: null),
        ]),
      );
      expect(recorder.whereOp(MediaOp.cellFailed), isEmpty);
    });
  });
}
