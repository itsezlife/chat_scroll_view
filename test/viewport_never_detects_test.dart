import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The viewport paints and activates the entities a body already carries and
/// never detects them (ADR 017): detection is the host's step, so no file under
/// `lib/src/` may reach `EntityDetection`, `DetectionPolicy` or the package
/// that holds them.
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
          source.contains('package:content_model/')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
