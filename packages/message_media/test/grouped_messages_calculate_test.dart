import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

/// Fixed layouts of [GroupedMessages.calculate] at `maxSizeWidth=800`,
/// `maxSizeHeight=814`, `displayMinSide=360` (`minWidth=266`,
/// `paddingsWidth=88`, `minH=100/814`).
void main() {
  const ph400 = 400 / 814;

  group('GroupedMessages.calculate', () {
    test('count < 2 returns empty (use single-media path)', () {
      expect(GroupedMessages.calculate(members: const []).positions, isEmpty);
      expect(
        GroupedMessages.calculate(
          members: const [
            GroupedMediaMember(id: MediaItemId('m1'), aspectRatio: 1),
          ],
        ).positions,
        isEmpty,
      );
    });

    test('2× square qq — side by side', () {
      // proportions "qq", averageAspectRatio=1 → half width each.
      final result = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(id: MediaItemId('m2'), aspectRatio: 1),
          GroupedMediaMember(id: MediaItemId('m3'), aspectRatio: 1),
        ],
      );
      expect(result.positions, hasLength(2));
      final a = result.positions[0];
      final b = result.positions[1];
      expect(a.pw, 400);
      expect(b.pw, 400);
      expect(a.ph, closeTo(ph400, 1e-9));
      expect(b.ph, closeTo(ph400, 1e-9));
      expect(
        a.flags,
        GroupedPositionFlags.left |
            GroupedPositionFlags.top |
            GroupedPositionFlags.bottom,
      );
      expect(
        b.flags,
        GroupedPositionFlags.right |
            GroupedPositionFlags.top |
            GroupedPositionFlags.bottom,
      );
      expect(a.edge, isTrue);
      expect(b.edge, isFalse);
      expect(a.spanSize, 400);
      expect(b.spanSize, 600); // + firstSpanAdditionalSize
      expect(a.minX, 0);
      expect(b.minX, 1);
    });

    test('2× wide ww stacked when average aspect is high', () {
      // "ww", average=2 > 1.4*(800/814), |Δar|<0.2 → stacked full width.
      final result = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(id: MediaItemId('m4'), aspectRatio: 2),
          GroupedMediaMember(id: MediaItemId('m5'), aspectRatio: 2),
        ],
      );
      final a = result.positions[0];
      final b = result.positions[1];
      expect(a.pw, 800);
      expect(b.pw, 800);
      expect(a.ph, closeTo(ph400, 1e-9));
      expect(
        a.flags,
        GroupedPositionFlags.left |
            GroupedPositionFlags.right |
            GroupedPositionFlags.top,
      );
      expect(
        b.flags,
        GroupedPositionFlags.left |
            GroupedPositionFlags.right |
            GroupedPositionFlags.bottom,
      );
      expect(a.spanSize, 1000);
      expect(b.spanSize, 1000);
    });

    test('2× mixed aspects — unequal widths', () {
      // proportions "wn": secondWidth = max(320, round(...)) = 320.
      final result = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(id: MediaItemId('m6'), aspectRatio: 1.5),
          GroupedMediaMember(id: MediaItemId('m7'), aspectRatio: 0.7),
        ],
      );
      final a = result.positions[0];
      final b = result.positions[1];
      expect(a.pw, 480);
      expect(b.pw, 320);
      expect(a.ph, closeTo(320 / 814, 1e-9));
      expect(b.ph, closeTo(320 / 814, 1e-9));
    });

    test('3× first wide — top full + bottom pair', () {
      final result = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(id: MediaItemId('m8'), aspectRatio: 1.5),
          GroupedMediaMember(id: MediaItemId('m9'), aspectRatio: 1),
          GroupedMediaMember(id: MediaItemId('m10'), aspectRatio: 1),
        ],
      );
      expect(result.positions, hasLength(3));
      final a = result.positions[0];
      final b = result.positions[1];
      final c = result.positions[2];
      // firstHeight = round(min(800/1.5, 814*0.66))/814 = 533/814
      expect(a.pw, 800);
      expect(a.ph, closeTo(533 / 814, 1e-9));
      expect(
        a.flags,
        GroupedPositionFlags.left |
            GroupedPositionFlags.right |
            GroupedPositionFlags.top,
      );
      expect(b.pw, 400);
      expect(c.pw, 400);
      // secondHeight = min(814 - firstHeight, 400)/814 = 400/814
      // (the normalised firstHeight is subtracted from maxSizeHeight.)
      expect(b.ph, closeTo(400 / 814, 1e-9));
      expect(c.ph, closeTo(400 / 814, 1e-9));
      expect(result.hasSibling, isFalse);
    });

    test('3× first narrow — siblingHeights', () {
      final result = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(id: MediaItemId('m11'), aspectRatio: 0.5),
          GroupedMediaMember(id: MediaItemId('m12'), aspectRatio: 1),
          GroupedMediaMember(id: MediaItemId('m13'), aspectRatio: 1),
        ],
      );
      expect(result.hasSibling, isTrue);
      final a = result.positions[0];
      expect(a.siblingHeights, isNotNull);
      expect(a.siblingHeights, hasLength(2));
      expect(a.ph, 1.0);
      expect(a.hasLeft && a.hasTop && a.hasBottom, isTrue);
    });

    test('awkward aspect > 2 uses the line solver', () {
      final result = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(id: MediaItemId('m14'), aspectRatio: 2.5),
          GroupedMediaMember(id: MediaItemId('m15'), aspectRatio: 2.5),
          GroupedMediaMember(id: MediaItemId('m16'), aspectRatio: 1),
        ],
      );
      expect(result.positions, hasLength(3));
      // Cropped ratios → [1.7, 1.7, 1.0]; optimal is often 1+2 lines.
      // Lock absolute pw sum and that every cell has an edge flag.
      var pwSum = 0;
      for (final p in result.positions) {
        expect(p.pw, greaterThan(0));
        expect(p.ph, greaterThan(0));
        expect(p.flags.isEmpty, isFalse);
        pwSum += p.pw;
      }
      // Each line’s pw values sum to maxSizeWidth (800) after spanLeft fix.
      expect(pwSum % 800, 0);
      expect(pwSum, greaterThanOrEqualTo(800));
    });

    test('grouped photo and video members share mosaic geometry', () {
      final photos = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(
            id: MediaItemId('m17'),
            aspectRatio: 1,
            kind: MediaItemKind.photo,
          ),
          GroupedMediaMember(
            id: MediaItemId('m18'),
            aspectRatio: 1,
            kind: MediaItemKind.photo,
          ),
        ],
      );
      final videos = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(
            id: MediaItemId('m19'),
            aspectRatio: 1,
            kind: MediaItemKind.video,
          ),
          GroupedMediaMember(
            id: MediaItemId('m20'),
            aspectRatio: 1,
            kind: MediaItemKind.video,
          ),
        ],
      );
      expect(photos.positions[0].pw, videos.positions[0].pw);
      expect(photos.positions[0].ph, videos.positions[0].ph);
      expect(photos.positions[1].pw, videos.positions[1].pw);
    });

    test('outgoing isOut flips edge to right', () {
      final result = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(id: MediaItemId('m21'), aspectRatio: 1),
          GroupedMediaMember(id: MediaItemId('m22'), aspectRatio: 1),
        ],
        isOut: true,
      );
      expect(result.positions[0].edge, isFalse);
      expect(result.positions[1].edge, isTrue);
      expect(result.positions[0].spanSize, 600); // minX==0 → +200
      expect(result.positions[1].spanSize, 400);
    });
  });
}
