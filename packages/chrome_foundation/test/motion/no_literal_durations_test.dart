import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the motion directory spells a literal Duration', () {
    final offenders = <String>[];
    for (final file in Directory('lib/src').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.contains(
        '${Platform.pathSeparator}motion${Platform.pathSeparator}',
      )) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('//')) continue;
        if (RegExp(r'\bDuration\(').hasMatch(line)) {
          offenders.add('${file.path}:${i + 1}: $line');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Components read durations from motion roles, not literals.',
    );
  });
}
