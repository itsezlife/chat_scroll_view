import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/cargo_build.dart';

void main() {
  group('rustTargetFor', () {
    test('maps macOS arm64 and x86_64 to their Apple triples', () {
      expect(
        rustTargetFor(OS.macOS, Architecture.arm64),
        'aarch64-apple-darwin',
      );
      expect(rustTargetFor(OS.macOS, Architecture.x64), 'x86_64-apple-darwin');
    });

    test('names the later slice for any other target', () {
      expect(
        () => rustTargetFor(OS.linux, Architecture.x64),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            allOf(contains('linux'), contains('slice 6'), contains('macOS')),
          ),
        ),
      );
      expect(
        () => rustTargetFor(OS.macOS, Architecture.ia32),
        throwsUnsupportedError,
      );
    });
  });

  group('findCargo', () {
    test('prefers a cargo on PATH', () {
      final found = findCargo(
        environment: {'PATH': '/a:/b', 'HOME': '/home/u'},
        fileExists: {'/b/cargo', '/home/u/.cargo/bin/cargo'}.contains,
      );

      expect(found, '/b/cargo');
    });

    test('falls back to the rustup install under CARGO_HOME', () {
      final found = findCargo(
        environment: {'PATH': '/a', 'CARGO_HOME': '/ch'},
        fileExists: {'/ch/bin/cargo'}.contains,
      );

      expect(found, '/ch/bin/cargo');
    });

    test('falls back to ~/.cargo/bin when PATH has none', () {
      final found = findCargo(
        environment: {'PATH': '/a', 'HOME': '/home/u'},
        fileExists: {'/home/u/.cargo/bin/cargo'}.contains,
      );

      expect(found, '/home/u/.cargo/bin/cargo');
    });

    test('fails with how to install Rust when nothing is found', () {
      expect(
        () => findCargo(
          environment: {'PATH': '/a', 'HOME': '/home/u'},
          fileExists: (_) => false,
        ),
        throwsA(
          isA<CargoNotFound>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('rustup.rs'), contains('PATH')),
          ),
        ),
      );
    });
  });
}
