import 'dart:io';

import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:test/test.dart';

void main() {
  group('an edited item', () {
    test('reads its derived output in place of the source', () {
      final source = AttachItems.video('v');
      final edited = source.copyWith(
        edits: const ItemEdits(version: 1, recipe: {'trim': 3}),
        derived: const DerivedOutput(
          localKey: 'local:v-edit',
          dimensions: AttachDimensions(848, 478),
          duration: Duration(seconds: 3),
          muted: true,
        ),
      );

      expect(source.isEdited, isFalse);
      expect(source.effectiveDimensions, const AttachDimensions(1920, 1080));
      expect(source.isMuted, isFalse);

      expect(edited.isEdited, isTrue);
      expect(edited.effectiveDimensions, const AttachDimensions(848, 478));
      expect(edited.effectiveDuration, const Duration(seconds: 3));
      expect(edited.isMuted, isTrue);
    });

    test('a derived output that moves makes the item an animation', () {
      final photo = AttachItems.photo('p').copyWith(
        derived: const DerivedOutput(localKey: 'local:p', animated: true),
      );

      expect(photo.kind, AttachKind.photo);
      expect(photo.isAnimated, isTrue);
    });

    test('without a derived output the source facts stand', () {
      final photo = AttachItems.photo(
        'p',
      ).copyWith(edits: const ItemEdits(version: 1, recipe: 'paint'));

      expect(photo.isEdited, isTrue);
      expect(photo.effectiveDimensions, const AttachDimensions(1280, 960));
    });
  });

  test('copyWith clears what it is told to', () {
    final item = AttachItems.photo(
      'p',
      timer: const AttachTimer.after(Duration(seconds: 10)),
    );

    expect(item.copyWith(clearTimer: true).timer, isNull);
    expect(item.copyWith(spoiler: true).timer, item.timer);
  });

  test('media kinds are photo, video and animation', () {
    expect(AttachKind.values.where((k) => k.isMedia), [
      AttachKind.photo,
      AttachKind.video,
      AttachKind.animation,
    ]);
  });

  test('no library file imports Flutter or dart:io', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final line in file.readAsLinesSync()) {
        if (RegExp(
          "^(import|export) '(package:flutter/|package:flutter_test/|dart:io|dart:ui)",
        ).hasMatch(line)) {
          offenders.add('${file.path}: $line');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
