import 'package:catalog_assets/glyph_atlas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'works the answer out once, however often and however it is read',
    () async {
      var computed = 0;
      final source = ComputedGlyphArtVersion(() async {
        computed++;
        return 'art-1';
      });

      final both = await Future.wait([source.read(), source.read()]);
      final later = await source.read();

      expect([...both, later], ['art-1', 'art-1', 'art-1']);
      expect(computed, 1);
    },
  );

  test('remembers a failure instead of computing again', () async {
    var computed = 0;
    final source = ComputedGlyphArtVersion(() async {
      computed++;
      throw StateError('no font');
    });

    await expectLater(source.read(), throwsStateError);
    await expectLater(source.read(), throwsStateError);
    expect(computed, 1);
  });
}
