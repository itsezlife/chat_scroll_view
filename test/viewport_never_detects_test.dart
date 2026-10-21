import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The viewport paints and activates the entities a body already carries and
/// never detects them (ADR 017): detection is the host's step, so no file under
/// `lib/src/` may reach `EntityDetection`, `DetectionPolicy` or the detection
/// sources of `content_model`. The package itself is a dependency of the root
/// (the emoji-only body reads its `EmojiOnly` and `ContentKey`), so importing
/// it is no offence; reaching for detection is.
void main() {
  test('no file under lib/src names the detection API', () {
    final offenders = <String>[];
    for (final entity in Directory('lib/src').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      if (source.contains('EntityDetection') ||
          source.contains('DetectionPolicy') ||
          source.contains('rich_text/detection')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
