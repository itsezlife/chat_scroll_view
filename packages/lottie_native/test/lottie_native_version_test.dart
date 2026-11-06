import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_native/lottie_native.dart';

void main() {
  final cargo = File('native/Cargo.toml').readAsStringSync();
  String field(RegExp pattern, String what) {
    final match = pattern.firstMatch(cargo);
    if (match == null) fail('native/Cargo.toml has no $what');
    return match.group(1)!;
  }

  group('LottieNativeVersion.engine', () {
    test('names the crate version of native/Cargo.toml', () {
      final version = field(
        RegExp('^version = "([^"]+)"', multiLine: true),
        'package version',
      );

      expect(LottieNativeVersion.engine, contains(version));
    });

    test('names the pinned tlottie revision', () {
      final revision = field(
        RegExp(r'tlottie = \{[^}]*rev = "([0-9a-f]+)"'),
        'tlottie rev',
      );

      expect(LottieNativeVersion.engine, contains(revision));
    });

    test('is a plain, lower-case token a cache file name can carry', () {
      expect(
        LottieNativeVersion.engine,
        matches(RegExp(r'^[a-z0-9][a-z0-9.-]{0,63}$')),
      );
    });
  });
}
