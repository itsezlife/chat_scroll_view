import 'dart:ui';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const _retention = Duration(seconds: 60);

Image _page() {
  final recorder = PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(4, 4);
  picture.dispose();
  return image;
}

void main() {
  late ManualRetentionTimers timers;
  late ManualMemoryPressure pressure;
  late GlyphPageResidency residency;
  late List<int> released;

  setUp(() {
    timers = ManualRetentionTimers();
    pressure = ManualMemoryPressure();
    residency = GlyphPageResidency(
      retention: _retention,
      memoryPressure: pressure,
      startTimer: timers.start,
    );
    released = <int>[];
    residency.addReleaseListener(released.add);
  });
  tearDown(() {
    residency.dispose();
    pressure.dispose();
  });

  void admit(int page) => residency.admit(page, _page());

  test('the default retention is 60 seconds', () {
    final plain = GlyphPageResidency();
    addTearDown(plain.dispose);

    expect(plain.retention, const Duration(seconds: 60));
    expect(GlyphPageResidency.defaultRetention, const Duration(seconds: 60));
  });

  group('resident pages', () {
    test('an admitted page is resident and counted in bytes', () {
      admit(2);

      expect(residency.isResident(2), isTrue);
      expect(residency.imageOf(2), isNotNull);
      expect(residency.residentPages, [2]);
      expect(residency.residentBytes, 4 * 4 * 4);
      expect(residency.imageOf(0), isNull);
    });

    test('admitting a page again replaces and disposes the old image', () {
      admit(0);
      final old = residency.imageOf(0)!;

      admit(0);

      expect(old.debugDisposed, isTrue);
      expect(residency.imageOf(0)!.debugDisposed, isFalse);
      expect(residency.residentPages, [0]);
    });
  });

  group('retention', () {
    test('a page nobody holds is released after the retention', () {
      admit(0);
      final image = residency.imageOf(0)!;

      timers.elapse(_retention - const Duration(seconds: 1));
      expect(residency.isResident(0), isTrue);

      timers.elapse(const Duration(seconds: 1));
      expect(residency.isResident(0), isFalse);
      expect(image.debugDisposed, isTrue);
      expect(released, [0]);
    });

    test('a held page is kept for as long as the hold lasts', () {
      admit(0);
      final hold = residency.hold(0);

      timers.elapse(_retention * 5);
      expect(residency.isResident(0), isTrue);
      expect(timers.pending, 0);

      hold.release();
      timers.elapse(_retention - const Duration(seconds: 1));
      expect(residency.isResident(0), isTrue);
      timers.elapse(const Duration(seconds: 1));
      expect(residency.isResident(0), isFalse);
    });

    test('holding again within the retention keeps the page', () {
      admit(0);
      timers.elapse(const Duration(seconds: 59));

      final hold = residency.hold(0);
      timers.elapse(_retention);

      expect(residency.isResident(0), isTrue);
      hold.release();
    });

    test('a page admitted while the panel is open waits for it to close', () {
      final open = residency.holdAll();
      admit(0);

      timers.elapse(_retention * 3);
      expect(residency.isResident(0), isTrue);

      open.release();
      timers.elapse(_retention);
      expect(residency.isResident(0), isFalse);
    });

    test('closing the panel keeps pages that a binding still holds', () {
      admit(0);
      admit(1);
      final open = residency.holdAll();
      final binding = residency.hold(1);

      open.release();
      timers.elapse(_retention);

      expect(residency.residentPages, [1]);
      binding.release();
    });

    test('reopening within the retention keeps every page, no reload', () {
      admit(0);
      admit(1);
      final first = residency.holdAll()..release();

      timers.elapse(const Duration(seconds: 59));
      final second = residency.holdAll();
      timers.elapse(_retention * 2);

      expect(first.isReleased, isTrue);
      expect(residency.residentPages, [0, 1]);
      expect(released, isEmpty);
      second.release();
    });

    test('a zero retention releases a page once nothing holds it', () {
      final eager = GlyphPageResidency(
        retention: Duration.zero,
        startTimer: timers.start,
      );
      addTearDown(eager.dispose);
      eager.admit(0, _page());

      timers.elapse(Duration.zero);

      expect(eager.isResident(0), isFalse);
    });
  });

  group('hold counts', () {
    test('count per page, and every page for the open panel', () {
      final a = residency.hold(0);
      final b = residency.hold(0);
      final c = residency.hold(1);
      expect(residency.holdCount(0), 2);
      expect(residency.holdCount(1), 1);

      final open = residency.holdAll();
      expect(residency.holdCount(0), 3);
      expect(residency.holdCount(7), 1);

      for (final hold in [a, b, c, open]) {
        hold.release();
      }
      expect(residency.holdCount(0), 0);
      expect(residency.holdCount(1), 0);
      expect(residency.holdCount(7), 0);
    });

    test('releasing a hold twice releases it once', () {
      final a = residency.hold(0);
      final b = residency.hold(0);

      a
        ..release()
        ..release();

      expect(residency.holdCount(0), 1);
      b.release();
      expect(residency.holdCount(0), 0);
    });
  });

  group('memory pressure', () {
    test('releases every page at once, held or not', () {
      admit(0);
      admit(1);
      final held = residency.hold(1);
      final open = residency.holdAll();
      final images = [residency.imageOf(0)!, residency.imageOf(1)!];

      pressure.raise();

      expect(residency.residentPages, isEmpty);
      expect(residency.residentBytes, 0);
      expect(images.every((i) => i.debugDisposed), isTrue);
      expect(released, [0, 1]);
      held.release();
      open.release();
    });

    test('leaves the hold counts exactly as they were', () {
      admit(0);
      final first = residency.hold(0);
      final second = residency.hold(0);

      pressure.raise();
      expect(residency.holdCount(0), 2);

      first.release();
      expect(residency.holdCount(0), 1);
      second.release();
      expect(residency.holdCount(0), 0);
    });

    test('cancels the pending expiry', () {
      admit(0);
      expect(timers.pending, 1);

      pressure.raise();

      expect(timers.pending, 0);
      timers.elapse(_retention);
      expect(released, [0]);
    });

    test('a page admitted afterwards is kept normally', () {
      pressure.raise();
      admit(0);
      final hold = residency.hold(0);

      timers.elapse(_retention * 2);

      expect(residency.isResident(0), isTrue);
      hold.release();
    });
  });

  group('dispose', () {
    test('frees the images, stops the timers and ignores late releases', () {
      admit(0);
      final hold = residency.hold(0);
      final image = residency.imageOf(0)!;

      residency.dispose();

      expect(image.debugDisposed, isTrue);
      expect(residency.residentPages, isEmpty);
      expect(timers.pending, 0);
      expect(hold.release, returnsNormally);
      expect(residency.hold(0).isReleased, isTrue);
    });

    test('no longer listens to memory pressure and drops late pages', () {
      residency.dispose();
      final late = _page();

      residency.admit(0, late);
      pressure.raise();

      expect(late.debugDisposed, isTrue);
      expect(residency.residentPages, isEmpty);
    });
  });
}
