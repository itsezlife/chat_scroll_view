import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

/// Cells are addressed by the media item they draw, never by list index or
/// by message.
void main() {
  const a = MediaItemId('a');
  const b = MediaItemId('b');
  const c = MediaItemId('c');

  GroupedMessages layout(List<GroupedMediaMember> members) =>
      GroupedMessages.calculate(members: members);

  group('GroupedMessages', () {
    test('each position carries its member id, in member order', () {
      final result = layout(const [
        GroupedMediaMember(id: a, aspectRatio: 1.5),
        GroupedMediaMember(id: b, aspectRatio: 1),
        GroupedMediaMember(id: c, aspectRatio: 1),
      ]);
      expect(result.positions.map((p) => p.itemId), [a, b, c]);
      expect(result.positionOf(b), same(result.positions[1]));
      expect(result.positionOf(const MediaItemId('missing')), isNull);
    });

    test('host and link preview ids address distinct cells', () {
      const preview = MediaItemId.linkPreviewOf(
        'a',
        slot: LinkPreviewMediaSlot.photo,
      );
      final result = layout(const [
        GroupedMediaMember(id: a, aspectRatio: 1),
        GroupedMediaMember(id: preview, aspectRatio: 1),
      ]);
      expect(result.positionOf(a)?.minX, 0);
      expect(result.positionOf(preview)?.minX, 1);
    });

    test('the caption owner is the first captioned item', () {
      final result = layout(const [
        GroupedMediaMember(id: a, aspectRatio: 1),
        GroupedMediaMember(id: b, aspectRatio: 1, hasCaption: true),
      ]);
      expect(result.hasCaption, isTrue);
      expect(result.captionItemId, b);
    });

    test('a second caption leaves no caption owner', () {
      final result = layout(const [
        GroupedMediaMember(id: a, aspectRatio: 1, hasCaption: true),
        GroupedMediaMember(id: b, aspectRatio: 1, hasCaption: true),
      ]);
      expect(result.hasCaption, isTrue);
      expect(result.captionItemId, isNull);
    });

    test('duplicate ids are rejected', () {
      expect(
        () => layout(const [
          GroupedMediaMember(id: a, aspectRatio: 1),
          GroupedMediaMember(id: a, aspectRatio: 1),
        ]),
        throwsAssertionError,
      );
    });

    test('reordering members moves cells with their ids', () {
      final forward = layout(const [
        GroupedMediaMember(id: a, aspectRatio: 1.5),
        GroupedMediaMember(id: b, aspectRatio: 0.7),
      ]);
      final reversed = layout(const [
        GroupedMediaMember(id: b, aspectRatio: 0.7),
        GroupedMediaMember(id: a, aspectRatio: 1.5),
      ]);
      expect(forward.positionOf(a)?.minX, 0);
      expect(reversed.positionOf(a)?.minX, 1);
    });
  });

  group('MosaicLayout', () {
    test('cellOf finds each cell by its media item', () {
      final grouped = layout(const [
        GroupedMediaMember(id: a, aspectRatio: 0.5),
        GroupedMediaMember(id: b, aspectRatio: 1),
        GroupedMediaMember(id: c, aspectRatio: 1),
      ]);
      final mosaic = MosaicLayout.project(
        positions: grouped.positions,
        mosaicWidth: 300,
      );
      for (final (index, id) in [a, b, c].indexed) {
        final cell = mosaic.cellOf(id);
        expect(cell, same(mosaic.cells[index]));
        expect(cell?.itemId, id);
        expect(cell?.position, same(grouped.positionOf(id)));
      }
      expect(mosaic.cellOf(const MediaItemId('missing')), isNull);
    });

    test('an empty projection has no cells to find', () {
      final mosaic = MosaicLayout.project(
        positions: const [],
        mosaicWidth: 300,
      );
      expect(mosaic.cells, isEmpty);
      expect(mosaic.cellOf(a), isNull);
    });
  });
}
