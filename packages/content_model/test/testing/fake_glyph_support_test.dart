import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

void main() {
  runGlyphSupportContract(() async {
    final support = FakeGlyphSupport();
    return GlyphSupportHarness(
      support: support,
      learn: ({missing = const {}, artVersion}) async =>
          support.learn(missing: missing, artVersion: artVersion),
    );
  });

  group('FakeGlyphSupport', () {
    const flag = ContentKey$Unicode('\u{1F3F4}\u{200D}\u{2620}\u{FE0F}');

    test('signals nothing for a step that teaches nothing new', () {
      final support = FakeGlyphSupport()
        ..learn(missing: {flag}, artVersion: 'v1');
      var signals = 0;
      support.changes.addListener(() => signals++);

      support.learn(missing: {flag}, artVersion: 'v1');

      expect(signals, 0);
    });

    test('keeps a missing key missing across an art version change', () {
      final support = FakeGlyphSupport()
        ..learn(missing: {flag}, artVersion: 'v1')
        ..learn(artVersion: 'v2');

      expect(support.supports(flag), isFalse);
      expect(support.artVersion, 'v2');
    });
  });
}
