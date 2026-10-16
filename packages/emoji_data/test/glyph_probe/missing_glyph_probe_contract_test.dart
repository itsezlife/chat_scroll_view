/// The glyph probe as a `GlyphSupport`: the shared contract suite, driven the
/// way a bake pass drives it.
///
/// **Seam:** `GlyphSupport` (`content_model/testing.dart`). The harness teaches
/// the probe by feeding it cell pixels and by answering its art version
/// producer, exactly the two inputs a host has.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:content_model/testing.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:test/test.dart';

const _reference = 'REF';

Uint8List _cell(int seed) => Uint8List.fromList(List.filled(16, seed));

void main() {
  GlyphSupportContract.run(() async {
    final version = Completer<String>();
    final probe = MissingGlyphProbe(
      glyphs: const [
        '\u{1F44D}',
        '\u{2764}\u{FE0F}',
        '\u{1F3F4}\u{200D}\u{2620}\u{FE0F}',
      ],
      references: const [_reference],
      store: FakeKeyValueStore(),
      artVersion: () => version.future,
    );
    return GlyphSupportHarness(
      support: probe,
      learn: ({missing = const {}, artVersion}) async {
        if (missing.isNotEmpty) {
          probe.observe(_reference, _cell(9));
          for (final key in missing) {
            probe.observe(key.sequence, _cell(9));
          }
        }
        if (artVersion != null) {
          unawaited(probe.start());
          version.complete(artVersion);
        } else if (missing.isNotEmpty) {
          // The probe publishes answers once it knows the art version they
          // were established against.
          unawaited(probe.start());
          version.complete('art-under-test');
        }
        await pumpEventQueue();
      },
    );
  });
}
