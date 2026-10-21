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

  test('no component of the panel, pages, presentation or composer spells an '
      'animation duration as a literal', () {
    // Timing that is not motion (debounce, hold-repeat, hover and timeout
    // values) is a policy constant of its package and is left alone: the scan
    // is for a literal handed to an animation, `duration: Duration(...)`.
    final offenders = <String>[];
    for (final package in [
      'panel_shell',
      'panel_pages',
      'panel_presentation',
      'chat_composer',
    ]) {
      final lib = Directory('../$package/lib');
      expect(lib.existsSync(), isTrue, reason: 'the scan reaches $package');
      for (final file in lib.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('//')) continue;
          if (RegExp(r'\bduration:\s*(const\s+)?Duration\(').hasMatch(line)) {
            offenders.add('${file.path}:${i + 1}: $line');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Animations take their duration from a motion role, so that '
          'reduce-motion reaches them.',
    );
  });
}
