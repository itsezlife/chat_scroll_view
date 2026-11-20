/// A bottom sheet's pull owner: the pull it holds and what a release does
/// with it.
///
/// **Seams:** [ChromeSheetPull] on its own (pure Dart).
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChromeSheetPull', () {
    ChromeSheetPull drag() => ChromeSheetPull(
      const ChromeSheetDragSpec(
        dismissDistance: 50,
        dismissVelocity: 3500,
        springBack: Duration(milliseconds: 250),
      ),
    );

    test('takes every pull down and holds it', () {
      final owner = drag();

      expect(owner.take(30), 30);
      expect(owner.take(15), 15);
      expect(owner.translation, 45);
    });

    test('gives back on a push up only what it holds', () {
      final owner = drag()..take(30);

      expect(owner.take(-50), -30);
      expect(owner.take(-10), 0);
      expect(owner.translation, 0);
    });

    test('a release past the distance closes the sheet', () {
      final owner = drag()..take(51);

      expect(owner.release(0), ChromeSheetRelease.dismiss);
    });

    test('a flick down closes it however short the pull', () {
      final owner = drag()..take(5);

      expect(owner.release(3500), ChromeSheetRelease.dismiss);
    });

    test('a short slow pull springs back', () {
      final owner = drag()..take(30);

      expect(owner.release(3499), ChromeSheetRelease.springBack);
    });

    test('with no pull held the release is the content’s, even a flick', () {
      final owner = drag()
        ..take(30)
        ..take(-30);

      expect(owner.release(5000), ChromeSheetRelease.rest);
    });
  });
}
