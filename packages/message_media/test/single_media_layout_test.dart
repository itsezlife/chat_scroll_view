import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

void main() {
  group('computeSingleMediaSize', () {
    const maxWidth = 300.0;

    test('landscape 16:9 fills max width under height clamp', () {
      final size = computeSingleMediaSize(
        aspectRatio: 16 / 9,
        maxWidth: maxWidth,
      );
      // TRACE: ChatMessageCell.getMessageSize — scale to photoWidth, h stays
      // under photoHeight = maxWidth + 100.
      expect(size, const Size(300, 168));
    });

    test('portrait 9:16 hits photoHeight then shrinks width', () {
      final size = computeSingleMediaSize(
        aspectRatio: 9 / 16,
        maxWidth: maxWidth,
      );
      // TRACE: h > photoHeight (400) → clamp h, rescale w.
      expect(size, const Size(225, 400));
    });

    test('very wide aspect raises height to minHeight without shrinking w', () {
      final size = computeSingleMediaSize(aspectRatio: 10, maxWidth: maxWidth);
      // TRACE: h < dp(120) → h = 120; imageW/hScale >= photoWidth → keep w.
      expect(size, const Size(300, 120));
    });

    test('photo and video share the same box for identical aspect', () {
      final photo = computeSingleMediaSize(
        aspectRatio: 4 / 3,
        maxWidth: maxWidth,
        kind: MediaKind.photo,
      );
      final video = computeSingleMediaSize(
        aspectRatio: 4 / 3,
        maxWidth: maxWidth,
        kind: MediaKind.video,
      );
      expect(photo, video);
    });
  });
}
