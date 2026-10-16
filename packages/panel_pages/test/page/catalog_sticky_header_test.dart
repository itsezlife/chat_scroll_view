import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/src/page/catalog_sticky_header.dart';

final class _Metrics implements CatalogScrollMetrics {
  @override
  double offset = 0;

  @override
  double maxScrollExtent = 2000;

  @override
  bool isSectionJumpActive = false;
}

void main() {
  late _Metrics metrics;
  late CatalogStickyHeader header;

  setUp(() {
    metrics = _Metrics();
    header = CatalogStickyHeader(stripExtent: 36, searchExtent: 50)
      ..configure(searchOpen: false, stripShown: true, metrics: metrics);
    addTearDown(header.dispose);
  });

  // Reads on by [delta] the way the catalogue reports it: the offset moves,
  // then the step is announced.
  void read(double delta) {
    metrics.offset += delta;
    header.scrolled(delta, metrics);
  }

  group('at rest on the first screen', () {
    test('the field sits in its band under the strip', () {
      expect(header.searchOffset.value, 36);
      expect(header.stripOffset.value, 0);
      expect(header.stripShadow.value, isFalse);
      expect(header.searchShadow.value, isFalse);
    });
  });

  group('the field scrolls with the content', () {
    test('it follows the offset and stops 50 above the top', () {
      metrics.offset = 20;
      header.sync(metrics);
      expect(header.searchOffset.value, 16);

      metrics.offset = 400;
      header.sync(metrics);
      expect(header.searchOffset.value, -50);
    });

    test('an offset beyond what the layout allows is clamped first', () {
      metrics
        ..maxScrollExtent = 30
        ..offset = 500;
      header.sync(metrics);
      expect(header.searchOffset.value, 6);
    });

    test('during a section jump only the lower bound applies, because a far '
        'jump teleports past what was laid out', () {
      metrics
        ..maxScrollExtent = 30
        ..offset = 500
        ..isSectionJumpActive = true;
      header.sync(metrics);
      expect(header.searchOffset.value, -50);
    });
  });

  group('the strip', () {
    test('stays while the field has not left the top', () {
      read(20);
      read(25);
      expect(metrics.offset, 45);
      expect(header.stripOffset.value, 0);
    });

    test('slides up by what is read once the field has left, and no further '
        'than its own height', () {
      metrics.offset = 200;
      read(10);
      expect(header.stripOffset.value, -10);
      read(100);
      expect(header.stripOffset.value, -36);
    });

    test(
      'comes back at once when the user reads back, by the distance read',
      () {
        metrics.offset = 400;
        read(100);
        expect(header.stripOffset.value, -36);

        read(-10);
        expect(header.stripOffset.value, -26);
        read(-40);
        expect(header.stripOffset.value, 0);
      },
    );

    test('is whole at the very top', () {
      metrics.offset = 400;
      read(100);
      metrics.offset = 0;
      header.scrolled(5, metrics);
      expect(header.stripOffset.value, 0);
    });

    test('does not move during a section jump', () {
      metrics
        ..offset = 400
        ..isSectionJumpActive = true;
      header.scrolled(80, metrics);
      expect(header.stripOffset.value, 0);
    });

    test('does not move while it is not shown', () {
      header.configure(searchOpen: false, stripShown: false, metrics: metrics);
      metrics.offset = 400;
      read(80);
      expect(header.stripOffset.value, 0);
    });

    test('a page without a strip has nothing to slide', () {
      final bare = CatalogStickyHeader(stripExtent: 0, searchExtent: 50)
        ..configure(searchOpen: false, stripShown: false, metrics: metrics);
      addTearDown(bare.dispose);
      metrics.offset = 300;
      bare.scrolled(40, metrics);
      expect(bare.stripOffset.value, 0);
      expect(bare.searchOffset.value, -50);
    });

    test('the page may slide it back itself, for a reveal', () {
      metrics.offset = 400;
      read(100);
      header.setStripOffset(-12, metrics);
      expect(header.stripOffset.value, -12);
      header.setStripOffset(0, metrics);
      expect(header.stripOffset.value, 0);
    });
  });

  group('the strip hairline', () {
    test('is off while the field sits under the strip', () {
      expect(header.stripShadow.value, isFalse);
      metrics.offset = 10;
      header.sync(metrics);
      expect(header.stripShadow.value, isFalse);
    });

    test('shows once the field has left the top', () {
      metrics.offset = 86;
      header.sync(metrics);
      expect(header.stripShadow.value, isTrue);
    });

    test('goes with the strip', () {
      metrics.offset = 400;
      read(100);
      expect(header.stripOffset.value, -36);
      // The strip's lower edge plus the probe is 2 above the top: nothing
      // under it.
      expect(header.stripShadow.value, isFalse);
    });
  });

  group('while search is open', () {
    setUp(() {
      header.configure(searchOpen: true, stripShown: false, metrics: metrics);
    });

    test('the field is pinned and the strip hairline is off', () {
      metrics.offset = 300;
      header.sync(metrics);
      expect(header.searchOffset.value, 0);
      expect(header.stripShadow.value, isFalse);
    });

    test('the field hairline shows exactly while content has scrolled under '
        'it', () {
      expect(header.searchShadow.value, isFalse);
      metrics.offset = 1;
      header.sync(metrics);
      expect(header.searchShadow.value, isTrue);
      metrics.offset = 0.2;
      header.sync(metrics);
      expect(header.searchShadow.value, isFalse);
    });

    test('closing search puts the field back in its band', () {
      header.configure(searchOpen: false, stripShown: true, metrics: metrics);
      expect(header.searchOffset.value, 36);
      expect(header.searchShadow.value, isFalse);
    });
  });
}
