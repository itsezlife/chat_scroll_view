import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';

InlineEmbedMetrics _metrics({
  double fontSize = 16,
  double ascent = 15,
  double descent = 4,
  double devicePixelRatio = 2,
}) => InlineEmbedMetrics(
  fontSize: fontSize,
  ascent: ascent,
  descent: descent,
  devicePixelRatio: devicePixelRatio,
);

void main() {
  group('InlineEmbedMetrics', () {
    test('carries the ascent and descent of the text', () {
      final metrics = _metrics();

      expect(metrics.ascent, 15);
      expect(metrics.descent, 4);
    });

    test('is equal to metrics with the same values', () {
      expect(_metrics(), _metrics());
      expect(_metrics().hashCode, _metrics().hashCode);
    });

    test('differs when the ascent, the descent or the density differs', () {
      expect(_metrics(), isNot(_metrics(ascent: 16)));
      expect(_metrics(), isNot(_metrics(descent: 5)));
      expect(_metrics(), isNot(_metrics(devicePixelRatio: 3)));
      expect(_metrics(), isNot(_metrics(fontSize: 17)));
    });

    test('names the ascent and descent in its description', () {
      expect(_metrics().toString(), contains('ascent: 15'));
      expect(_metrics().toString(), contains('descent: 4'));
    });

    test('refuses a non-positive ascent or descent', () {
      expect(() => _metrics(ascent: 0), throwsAssertionError);
      expect(() => _metrics(descent: -1), throwsAssertionError);
    });
  });
}
