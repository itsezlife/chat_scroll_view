/// The default layout step through `MessageMediaPolicy.layout`: blocks,
/// cells keyed by item, fit modes, neighbours and the diagnostics events.
library;

import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

MediaItem _item(
  String id,
  MediaItemKind kind, {
  int? width = 1600,
  int? height = 900,
}) => MediaItem(
  id: MediaItemId(id),
  kind: kind,
  descriptor: ContentDescriptor(
    key: ContentKey.document(id),
    fileName: 'secret-$id.pdf',
    size: switch ((width, height)) {
      (final w?, final h?) => ContentSize(w, h),
      _ => null,
    },
  ),
);

MediaItem _photo(String id, {int? width = 1600, int? height = 900}) =>
    _item(id, MediaItemKind.photo, width: width, height: height);

MediaLayoutInput _input(
  List<MediaItem> items, {
  MediaCaptionPosition captionPosition = MediaCaptionPosition.none,
  MediaLinkPreviewInput? linkPreview,
  bool joinedAbove = false,
  bool joinedBelow = false,
  double availableWidth = 364,
}) => MediaLayoutInput(
  items: items,
  availableWidth: availableWidth,
  displaySize: const Size(364, 800),
  captionPosition: captionPosition,
  linkPreview: linkPreview,
  joinedAbove: joinedAbove,
  joinedBelow: joinedBelow,
  correlation: const ChatCorrelation(chatId: 'chat', scrollId: 'm1'),
);

const _android = MessageMediaPolicy.android();

void main() {
  group('blocks', () {
    test('no items and no preview give the empty layout', () {
      final layout = _android.layout(_input(const []));
      expect(layout.blocks, isEmpty);
      expect(layout.size, Size.zero);
      expect(layout, MediaLayout.empty);
    });

    test('a mixed list gives consecutive blocks in item order, each item in '
        'exactly one cell', () {
      final items = [
        _photo('p1'),
        _item('v1', MediaItemKind.video),
        _item('f1', MediaItemKind.file),
        _item('f2', MediaItemKind.file),
        _photo('p2'),
        _item('s1', const MediaItemKind.custom('sticker')),
      ];
      final layout = _android.layout(_input(items));
      expect(layout.blocks.map((block) => block.runtimeType), [
        MediaBlock$Mosaic,
        MediaBlock$FileStack,
        MediaBlock$Mosaic,
        MediaBlock$FileStack,
      ]);
      expect(layout.blocks.map((block) => block.cells.length), [2, 2, 1, 1]);
      final ids = layout.cells.map((cell) => cell.itemId).toList();
      expect(ids, items.map((item) => item.id));
      for (final item in items) {
        expect(layout.cellOf(item.id)?.kind, item.kind);
      }
      // Blocks stack top to bottom without overlap.
      for (var i = 1; i < layout.blocks.length; i++) {
        expect(layout.blocks[i].rect.top, layout.blocks[i - 1].rect.bottom);
      }
      expect(layout.size.height, layout.blocks.last.rect.bottom);
    });

    test('a single box is a mosaic block of one cell at the box size', () {
      final layout = _android.layout(_input([_photo('p')]));
      final block = layout.blocks.single;
      expect(block, isA<MediaBlock$Mosaic>());
      expect(block.rect, const Rect.fromLTWH(0, 0, 300, 168));
      expect(layout.cellOf(const MediaItemId('p'))?.rect, block.rect);
      expect(layout.size, const Size(300, 168));
    });

    test('an album uses the mosaic slot at the block width, rows bounded by '
        'half of max(list width, screen height)', () {
      final layout = _android.layout(
        _input([
          _photo('a', width: 1, height: 1),
          _photo('b', width: 1, height: 1),
        ]),
      );
      final block = layout.blocks.single;
      // 0.8 × 364.
      expect(block.rect.width, closeTo(291.2, 1e-9));
      final expected = const GroupedMosaicAlgorithm().arrange(
        items: [
          _photo('a', width: 1, height: 1),
          _photo('b', width: 1, height: 1),
        ],
        width: 291.2,
        input: _input(const []),
      );
      expect(block.rect.size, expected.size);
      expect(
        layout.cellOf(const MediaItemId('a'))?.rect,
        expected.placements.first.rect,
      );
      expect(const GroupedMosaicAlgorithm().maxHeightFactor, 0.5);
      expect(
        const GroupedMosaicAlgorithm().maxHeightFor(_input(const [])),
        400,
      );
    });

    test('a file stack lays one row per item at the block width', () {
      final layout = _android.layout(
        _input([
          _item('f1', MediaItemKind.file),
          _item('f2', MediaItemKind.file),
        ]),
      );
      final block = layout.blocks.single as MediaBlock$FileStack;
      expect(block.rect, const Rect.fromLTWH(0, 0, 364 * 0.8, 112));
      expect(block.cells.map((cell) => cell.rect.top), [0, 56]);
      expect(block.cells.every((cell) => cell.fit == null), isTrue);
    });

    test('the link preview card is the last block, a placeholder of the block '
        'width and no height', () {
      final page = LinkPreview(url: Uri.parse('https://example.org/a'));
      final options = LinkPreviewOptions(
        url: Uri.parse('https://example.org/a'),
      );
      final layout = _android.layout(
        _input([
          _photo('p'),
        ], linkPreview: MediaLinkPreviewInput(page: page, options: options)),
      );
      final card = layout.blocks.last;
      expect(card, isA<MediaBlock$LinkPreview>());
      card as MediaBlock$LinkPreview;
      expect(card.page, page);
      expect(card.options, options);
      expect(card.rect, const Rect.fromLTWH(0, 168, 364 * 0.8, 0));
      // The box above the card meets an item, not the bubble's edge.
      expect(
        layout.cellOf(const MediaItemId('p'))?.neighbours.bottom,
        MediaNeighbour.item,
      );
    });

    test('a layout is a value: the same input gives an equal layout', () {
      final items = [_photo('a'), _photo('b'), _item('f', MediaItemKind.file)];
      final first = _android.layout(_input(items));
      final second = _android.layout(_input(items));
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(_android.layout(_input(items, availableWidth: 400))));
    });
  });

  group('neighbours', () {
    test(
      'a lone box in a media-only bubble touches the bubble on every side',
      () {
        final layout = _android.layout(_input([_photo('p')]));
        expect(
          layout.cellOf(const MediaItemId('p'))?.neighbours,
          MediaNeighbours.bubble,
        );
      },
    );

    test('a caption below touches the bottom, above the top', () {
      final below = _android.layout(
        _input([_photo('p')], captionPosition: MediaCaptionPosition.below),
      );
      expect(
        below.cellOf(const MediaItemId('p'))?.neighbours,
        const MediaNeighbours(
          top: MediaNeighbour.bubbleEdge,
          bottom: MediaNeighbour.text,
          left: MediaNeighbour.bubbleEdge,
          right: MediaNeighbour.bubbleEdge,
        ),
      );
      final above = _android.layout(
        _input([_photo('p')], captionPosition: MediaCaptionPosition.above),
      );
      expect(
        above.cellOf(const MediaItemId('p'))?.neighbours.top,
        MediaNeighbour.text,
      );
      expect(
        above.cellOf(const MediaItemId('p'))?.neighbours.bottom,
        MediaNeighbour.bubbleEdge,
      );
    });

    test('a bubble joined above or below gives an adjacent bubble there', () {
      final layout = _android.layout(
        _input([_photo('p')], joinedAbove: true, joinedBelow: true),
      );
      final neighbours = layout.cellOf(const MediaItemId('p'))!.neighbours;
      expect(neighbours.top, MediaNeighbour.adjacentBubble);
      expect(neighbours.bottom, MediaNeighbour.adjacentBubble);
      // Text wins over the joined bubble on the side it sits.
      final captioned = _android.layout(
        _input(
          [_photo('p')],
          joinedBelow: true,
          captionPosition: MediaCaptionPosition.below,
        ),
      );
      expect(
        captioned.cellOf(const MediaItemId('p'))?.neighbours.bottom,
        MediaNeighbour.text,
      );
    });

    test("a mosaic's inner sides touch an item, its outer sides the block's "
        'neighbours', () {
      final layout = _android.layout(
        _input([
          _photo('a', width: 1, height: 1),
          _photo('b', width: 1, height: 1),
        ], captionPosition: MediaCaptionPosition.below),
      );
      expect(
        layout.cellOf(const MediaItemId('a'))?.neighbours,
        const MediaNeighbours(
          top: MediaNeighbour.bubbleEdge,
          bottom: MediaNeighbour.text,
          left: MediaNeighbour.bubbleEdge,
          right: MediaNeighbour.item,
        ),
      );
      expect(
        layout.cellOf(const MediaItemId('b'))?.neighbours.left,
        MediaNeighbour.item,
      );
    });

    test('blocks meet each other as items, file rows meet the rows next to '
        'them', () {
      final layout = _android.layout(
        _input([
          _photo('p'),
          _item('f1', MediaItemKind.file),
          _item('f2', MediaItemKind.file),
        ]),
      );
      expect(
        layout.cellOf(const MediaItemId('p'))?.neighbours.bottom,
        MediaNeighbour.item,
      );
      final f1 = layout.cellOf(const MediaItemId('f1'))!.neighbours;
      expect(f1.top, MediaNeighbour.item);
      expect(f1.bottom, MediaNeighbour.item);
      final f2 = layout.cellOf(const MediaItemId('f2'))!.neighbours;
      expect(f2.bottom, MediaNeighbour.bubbleEdge);
      expect(f2.left, MediaNeighbour.bubbleEdge);
    });
  });

  group('fit', () {
    MediaFit? fitOf(MessageMediaPolicy policy, MediaItemKind kind) => policy
        .layout(_input([_item('x', kind)]))
        .cellOf(const MediaItemId('x'))
        ?.fit;

    test('Android crops every box', () {
      for (final kind in const [
        MediaItemKind.photo,
        MediaItemKind.video,
        MediaItemKind.animation,
      ]) {
        expect(fitOf(_android, kind), const MediaFit.crop());
      }
    });

    test('iOS fits a photo over a blur cropping up to 4, crops video and '
        'animation', () {
      const ios = MessageMediaPolicy.ios();
      expect(
        fitOf(ios, MediaItemKind.photo),
        const MediaFit.blurFit(overflowCrop: 4),
      );
      expect(fitOf(ios, MediaItemKind.video), const MediaFit.crop());
      expect(fitOf(ios, MediaItemKind.animation), const MediaFit.crop());
    });

    test('desktop crops while 3/4 of a photo, 1/2 of a video or animation '
        'stays visible', () {
      const desktop = MessageMediaPolicy.desktop();
      expect(
        fitOf(desktop, MediaItemKind.photo),
        const MediaFit.cropIfVisible(0.75),
      );
      expect(
        fitOf(desktop, MediaItemKind.video),
        const MediaFit.cropIfVisible(0.5),
      );
      expect(
        fitOf(desktop, MediaItemKind.animation),
        const MediaFit.cropIfVisible(0.5),
      );
    });

    test('a file row has no fit', () {
      expect(fitOf(_android, MediaItemKind.file), isNull);
    });
  });

  group('parts', () {
    test('each platform pins its file row height', () {
      expect(const MediaLayoutPolicy.android().fileRowHeight, 56);
      expect(const MediaLayoutPolicy.ios().fileRowHeight, 65);
      expect(const MediaLayoutPolicy.desktop().fileRowHeight, 60);
    });

    test('each platform has its mosaic', () {
      for (final (policy, algorithm) in const [
        (MediaLayoutPolicy.android(), GroupedMosaicAlgorithm()),
        (MediaLayoutPolicy.ios(), IosMosaicAlgorithm()),
      ]) {
        expect(policy.mosaicAlgorithm, algorithm);
      }
    });

    test('the desktop mosaic is its own', () {
      expect(
        const MediaLayoutPolicy.desktop().mosaicAlgorithm,
        const DesktopMosaicAlgorithm(),
      );
    });

    test('copyWith replaces one part and keeps the others', () {
      const base = MediaLayoutPolicy.android();
      final changed = base.copyWith(fit: const MediaFitPolicy.ios());
      expect(changed.fit, const MediaFitPolicy.ios());
      expect(changed.box, base.box);
      expect(changed.mosaicAlgorithm, base.mosaicAlgorithm);
      expect(
        const MediaFitPolicy.android()
            .copyWith(photo: const MediaFit.cropIfVisible(0.5))
            .photo,
        const MediaFit.cropIfVisible(0.5),
      );
    });

    test('a host mosaic algorithm in the slot lays the album out', () {
      final policy = _android.copyWith(
        layoutStep: const MediaLayoutPolicy.android().copyWith(
          mosaicAlgorithm: const _StackedMosaic(),
        ),
      );
      final layout = policy.layout(_input([_photo('a'), _photo('b')]));
      expect(layout.cellOf(const MediaItemId('b'))?.rect.top, 50);
      expect(layout.blocks.single.rect.height, 100);
    });
  });

  group('diagnostics', () {
    test('a custom kind reports unknownKind as a warning with its tag and '
        'item, drawn as a file row', () {
      final recorder = RecordingDiagnostics.install();
      _android.layout(
        _input([_item('s1', const MediaItemKind.custom('sticker'))]),
      );
      expect(recorder.whereOp(MediaOp.unknownKind), [
        isChatEvent(
          level: ChatEventLevel.warning,
          category: ChatEventCategory.media,
          correlation: const ChatCorrelation(
            chatId: 'chat',
            scrollId: 'm1',
            mediaItemId: 'item:s1',
          ),
          fields: {'kind': 'sticker', 'drawnAs': 'fileRow'},
        ),
      ]);
    });

    test('a fallback rule reports layoutFallback with the resulting size', () {
      final recorder = RecordingDiagnostics.install();
      _android.layout(_input([_photo('p', width: null, height: null)]));
      expect(recorder.whereOp(MediaOp.layoutFallback), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.media,
          correlation: const ChatCorrelation(
            chatId: 'chat',
            scrollId: 'm1',
            mediaItemId: 'item:p',
          ),
          fields: {
            'rule': MediaLayoutFallbackRule.noDimensions,
            'width': 150.0,
            'height': 150.0,
          },
        ),
      ]);
    });

    test('an album item without dimensions reports layoutFallback', () {
      final recorder = RecordingDiagnostics.install();
      _android.layout(
        _input([_photo('a'), _photo('b', width: null, height: null)]),
      );
      expect(recorder.whereOp(MediaOp.layoutFallback), [
        isChatEvent(
          correlation: const ChatCorrelation(
            chatId: 'chat',
            scrollId: 'm1',
            mediaItemId: 'item:b',
          ),
          fields: containsPair('rule', MediaLayoutFallbackRule.noDimensions),
        ),
      ]);
    });

    test('a box without a fallback reports none', () {
      final recorder = RecordingDiagnostics.install();
      _android.layout(_input([_photo('p')]));
      expect(recorder.whereOp(MediaOp.layoutFallback), isEmpty);
      expect(recorder.whereOp(MediaOp.unknownKind), isEmpty);
    });

    test('every layout reports layoutComputed at trace', () {
      final recorder = RecordingDiagnostics.install();
      _android.layout(
        _input([_photo('a'), _photo('b'), _item('f', MediaItemKind.file)]),
      );
      final event = recorder.whereOp(MediaOp.layoutComputed).single;
      expect(
        event,
        isChatEvent(
          level: ChatEventLevel.trace,
          category: ChatEventCategory.media,
          correlation: const ChatCorrelation(chatId: 'chat', scrollId: 'm1'),
        ),
      );
      expect(event.fields, {
        'platform': MessageMediaPlatform.android,
        'items': 3,
        'blocks': 'mosaic,fileStack',
        'availableWidth': 364.0,
        'mosaicAlgorithm': 'grouped',
        'durationUs': isA<int>(),
      });
    });

    test('a host layout step is named hostStep', () {
      final recorder = RecordingDiagnostics.install();
      _android
          .copyWith(layoutStep: const _EmptyStep())
          .layout(_input([_photo('p')]));
      expect(
        recorder.whereOp(MediaOp.layoutComputed).single.fields,
        containsPair('mosaicAlgorithm', 'hostStep'),
      );
    });

    test('no event carries user content', () {
      final recorder = RecordingDiagnostics.install();
      _android.layout(
        _input(
          [
            _photo('p', width: null, height: null),
            _item('s', const MediaItemKind.custom('sticker')),
          ],
          linkPreview: MediaLinkPreviewInput(
            page: LinkPreview(
              url: Uri.parse('https://example.org/private/path?q=1'),
              title: 'A private title',
            ),
          ),
        ),
      );
      expect(recorder.events, isNotEmpty);
      for (final event in recorder.events) {
        for (final value in event.fields.values) {
          final text = '$value';
          expect(text, isNot(contains('secret')));
          expect(text, isNot(contains('private')));
          expect(text, isNot(contains('example.org')));
        }
      }
    });
  });
}

/// Stacks every box 50 high, to show a host algorithm in the slot.
final class _StackedMosaic implements MosaicAlgorithm {
  const _StackedMosaic();

  @override
  String get name => 'stacked';

  @override
  MosaicArrangement arrange({
    required List<MediaItem> items,
    required double width,
    required MediaLayoutInput input,
  }) => MosaicArrangement(
    size: Size(width, 50.0 * items.length),
    placements: [
      for (final (index, item) in items.indexed)
        MosaicPlacement(
          itemId: item.id,
          rect: Rect.fromLTWH(0, 50.0 * index, width, 50),
          edges: GroupedPositionFlags.left | GroupedPositionFlags.right,
        ),
    ],
  );
}

/// A host layout step that lays nothing out.
final class _EmptyStep implements MediaLayoutStep {
  const _EmptyStep();

  @override
  MediaLayout layout(MediaLayoutInput input) => MediaLayout.empty;
}
