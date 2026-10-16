import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sources = [
    for (final file in Directory('lib').listSync(recursive: true))
      if (file is File && file.path.endsWith('.dart')) file,
  ];

  test('imports only the packages the composer may know', () {
    const allowed = {
      'catalog_assets',
      'chat_composer',
      'chrome_foundation',
      'content_model',
      'characters',
      'flutter',
      'listen',
      'meta',
    };
    final pattern = RegExp('''^(?:import|export) 'package:([a-z_]+)/''');
    final offenders = <String>[];
    for (final file in sources) {
      for (final line in file.readAsLinesSync()) {
        final match = pattern.firstMatch(line);
        if (match != null && !allowed.contains(match.group(1))) {
          offenders.add('${file.path}: ${match.group(1)}');
        }
      }
    }

    expect(offenders, isEmpty);
  });

  test(
    'names no panel, inset or presentation type, no platform channel and no legacy composer type',
    () {
      final forbidden = RegExp(
        'SystemChannels|KeyboardPanel|PanelShell|PanelPresentation|'
        'InsetArbiter|ChatChrome|ChatEnter|ChatComposer|ChatInputMetrics',
      );
      final offenders = [
        for (final file in sources)
          if (forbidden.hasMatch(file.readAsStringSync())) file.path,
      ];

      expect(offenders, isEmpty);
    },
  );

  test('holds no literal duration: motion comes from the role table', () {
    final offenders = [
      for (final file in sources)
        if (RegExp(r'\bDuration\(').hasMatch(file.readAsStringSync()))
          file.path,
    ];

    expect(offenders, isEmpty);
  });
}
