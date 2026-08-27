import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

/// TRACE fixtures for `MessageObject.GroupedMessages.calculate` at
/// `maxSizeWidth=800`, `maxSizeHeight=814`, `displayMinSide=360`
/// (`minWidth=266`, `paddingsWidth=88`, `minH=100/814`).
void main() {
  const ph400 = 400 / 814;

  group('GroupedMessages.calculate', () {
    test('count < 2 returns empty (use single-media path)', () {
      expect(GroupedMessages.calculate(members: const []).positions, isEmpty);
      expect(
        GroupedMessages.calculate(
          members: const [GroupedMediaMember(aspectRatio: 1)],
        ).positions,
        isEmpty,
      );
    });

    test('2× square qq — side-by-side TRACE', () {
      // proportions "qq", averageAspectRatio=1 → half width each.
      final result = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 1),
          GroupedMediaMember(aspectRatio: 1),
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
          GroupedMediaMember(aspectRatio: 2),
          GroupedMediaMember(aspectRatio: 2),
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

    test('2× mixed aspects — unequal widths TRACE', () {
      // proportions "wn": secondWidth = max(320, round(...)) = 320.
      final result = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 1.5),
          GroupedMediaMember(aspectRatio: 0.7),
        ],
      );
      final a = result.positions[0];
      final b = result.positions[1];
      expect(a.pw, 480);
      expect(b.pw, 320);
      expect(a.ph, closeTo(320 / 814, 1e-9));
      expect(b.ph, closeTo(320 / 814, 1e-9));
    });

    test('3× first wide — top full + bottom pair TRACE', () {
      final result = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 1.5),
          GroupedMediaMember(aspectRatio: 1),
          GroupedMediaMember(aspectRatio: 1),
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
      // (Java subtracts the normalized firstHeight from maxSizeHeight.)
      expect(b.ph, closeTo(400 / 814, 1e-9));
      expect(c.ph, closeTo(400 / 814, 1e-9));
      expect(result.hasSibling, isFalse);
    });

    test('3× first narrow — siblingHeights TRACE', () {
      final result = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 0.5),
          GroupedMediaMember(aspectRatio: 1),
          GroupedMediaMember(aspectRatio: 1),
        ],
      );
      expect(result.hasSibling, isTrue);
      final a = result.positions[0];
      expect(a.siblingHeights, isNotNull);
      expect(a.siblingHeights, hasLength(2));
      expect(a.ph, 1.0);
      expect(a.hasLeft && a.hasTop && a.hasBottom, isTrue);
    });

    test('awkward aspect > 2 uses attempt solver (forceCalc)', () {
      final result = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 2.5),
          GroupedMediaMember(aspectRatio: 2.5),
          GroupedMediaMember(aspectRatio: 1),
        ],
      );
      expect(result.positions, hasLength(3));
      // TRACE: cropped ratios → [1.7, 1.7, 1.0]; optimal is often 1+2 lines.
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
          GroupedMediaMember(aspectRatio: 1, kind: MediaKind.photo),
          GroupedMediaMember(aspectRatio: 1, kind: MediaKind.photo),
        ],
      );
      final videos = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 1, kind: MediaKind.video),
          GroupedMediaMember(aspectRatio: 1, kind: MediaKind.video),
        ],
      );
      expect(photos.positions[0].pw, videos.positions[0].pw);
      expect(photos.positions[0].ph, videos.positions[0].ph);
      expect(photos.positions[1].pw, videos.positions[1].pw);
    });

    test('outgoing isOut flips edge to right', () {
      final result = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 1),
          GroupedMediaMember(aspectRatio: 1),
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
