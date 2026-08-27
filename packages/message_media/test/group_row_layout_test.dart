import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

void main() {
  group('GroupRowLayout', () {
    test(
      'caption height only on captionIndex row; siblings stay media-only',
      () {
        final grouped = GroupedMessages.calculate(
          members: const [
            GroupedMediaMember(aspectRatio: 1, hasCaption: true),
            GroupedMediaMember(aspectRatio: 1),
          ],
        );
        final mosaic = MosaicLayout.project(
          positions: grouped.positions,
          mosaicWidth: 300,
          maxSizeWidth: grouped.maxSizeWidth.toDouble(),
        );

        final rows = GroupRowLayout.compute(
          mosaic: mosaic,
          messages: grouped,
          captionText: 'album caption',
          captionHeight: 24,
        );

        expect(rows, hasLength(2));
        expect(rows[0].mediaHeight, mosaic.cells[0].rect.height);
        expect(rows[0].totalHeight, mosaic.cells[0].rect.height + 24);
        expect(rows[0].caption, isNotNull);
        expect(rows[0].caption!.text, 'album caption');
        expect(rows[0].caption!.above, isFalse);
        expect(rows[0].caption!.height, 24);

        expect(rows[1].mediaHeight, mosaic.cells[1].rect.height);
        expect(rows[1].totalHeight, mosaic.cells[1].rect.height);
        expect(rows[1].caption, isNull);
      },
    );

    test('captionAbove places slot above media on owning row', () {
      final grouped = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(
            aspectRatio: 1,
            hasCaption: true,
            invertMedia: true,
          ),
          GroupedMediaMember(aspectRatio: 1),
        ],
      );
      expect(grouped.captionAbove, isTrue);

      final mosaic = MosaicLayout.project(
        positions: grouped.positions,
        mosaicWidth: 300,
        maxSizeWidth: grouped.maxSizeWidth.toDouble(),
      );

      final rows = GroupRowLayout.compute(
        mosaic: mosaic,
        messages: grouped,
        captionText: 'above',
        captionHeight: 16,
      );

      expect(rows[0].caption!.above, isTrue);
      expect(rows[0].totalHeight, rows[0].mediaHeight + 16);
      expect(rows[1].caption, isNull);
    });

    test('no caption slot when captionIndex is null', () {
      final grouped = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 1, hasCaption: true),
          GroupedMediaMember(aspectRatio: 1, hasCaption: true),
        ],
      );
      expect(grouped.captionIndex, isNull);

      final mosaic = MosaicLayout.project(
        positions: grouped.positions,
        mosaicWidth: 300,
        maxSizeWidth: grouped.maxSizeWidth.toDouble(),
      );

      final rows = GroupRowLayout.compute(
        mosaic: mosaic,
        messages: grouped,
        captionText: 'ignored',
        captionHeight: 20,
      );

      expect(rows[0].caption, isNull);
      expect(rows[0].totalHeight, rows[0].mediaHeight);
      expect(rows[1].caption, isNull);
      expect(rows[1].totalHeight, rows[1].mediaHeight);
    });

    test('zero captionHeight does not inflate owning row', () {
      final grouped = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 1, hasCaption: true),
          GroupedMediaMember(aspectRatio: 1),
        ],
      );
      final mosaic = MosaicLayout.project(
        positions: grouped.positions,
        mosaicWidth: 300,
        maxSizeWidth: grouped.maxSizeWidth.toDouble(),
      );
      final rows = GroupRowLayout.compute(
        mosaic: mosaic,
        messages: grouped,
        captionText: 'x',
        captionHeight: 0,
      );
      expect(rows[0].caption, isNotNull);
      expect(rows[0].totalHeight, rows[0].mediaHeight);
    });

    test('captionIndex alone reserves a slot when captionText is omitted', () {
      final grouped = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 1, hasCaption: true),
          GroupedMediaMember(aspectRatio: 1),
        ],
      );
      final mosaic = MosaicLayout.project(
        positions: grouped.positions,
        mosaicWidth: 300,
        maxSizeWidth: grouped.maxSizeWidth.toDouble(),
      );
      final rows = GroupRowLayout.compute(
        mosaic: mosaic,
        messages: grouped,
        captionHeight: 18,
      );
      expect(rows[0].caption, isNotNull);
      expect(rows[0].caption!.text, '');
      expect(rows[0].totalHeight, rows[0].mediaHeight + 18);
      expect(rows[1].caption, isNull);
    });
  });

  group('GroupRowCaption', () {
    testWidgets('paints caption below media by default', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: GroupRowCaption(
            caption: GroupCaptionSlot(
              text: 'below me',
              above: false,
              height: 20,
            ),
            child: SizedBox(width: 100, height: 40, key: Key('media')),
          ),
        ),
      );

      final media = tester.getTopLeft(find.byKey(const Key('media')));
      final text = tester.getTopLeft(find.text('below me'));
      expect(text.dy, greaterThan(media.dy));
    });

    testWidgets('paints caption above media when above is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: GroupRowCaption(
            caption: GroupCaptionSlot(
              text: 'above me',
              above: true,
              height: 20,
            ),
            child: SizedBox(width: 100, height: 40, key: Key('media')),
          ),
        ),
      );

      final media = tester.getTopLeft(find.byKey(const Key('media')));
      final text = tester.getTopLeft(find.text('above me'));
      expect(text.dy, lessThan(media.dy));
    });

    testWidgets('omits text when caption is null', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: GroupRowCaption(
            caption: null,
            child: SizedBox(width: 100, height: 40),
          ),
        ),
      );
      expect(find.byType(Text), findsNothing);
    });
  });
}
