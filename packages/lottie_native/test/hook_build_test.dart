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

    test('is null for any other target: the library is then absent', () {
      expect(rustTargetFor(OS.linux, Architecture.x64), isNull);
      expect(rustTargetFor(OS.macOS, Architecture.ia32), isNull);
    });
  });

  group('unsupportedTargetWarning', () {
    test(
      'names the target and says the library is unavailable at run time',
      () {
        final warning = unsupportedTargetWarning(OS.linux, Architecture.x64);

        expect(
          warning,
          allOf(contains('linux'), contains('x64'), contains('at run time')),
        );
      },
    );
  });

  group('missingTargetHint', () {
    test(
      'suggests rustup target add when cargo says the target is missing',
      () {
        for (final output in [
          "error[E0463]: can't find crate for `core`",
          'note: the `x86_64-apple-darwin` target may not be installed',
        ]) {
          expect(
            missingTargetHint(output, 'x86_64-apple-darwin'),
            'rustup target add x86_64-apple-darwin',
          );
        }
      },
    );

    test('has nothing to add for any other failure', () {
      expect(missingTargetHint('error: linker failed', 'a-b'), isNull);
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
