import 'dart:convert';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/delivery_plan.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/prebuilt_manifest.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/targets.dart';

final _hash = 'ab' * 32;
const _mac = LottieNativeTarget(OS.macOS, Architecture.arm64);
const _linux = LottieNativeTarget(OS.linux, Architecture.x64);

PrebuiltManifest _manifest({
  String? sourceHash,
  String baseUrl = 'https://example.com/p/',
  Map<String, Object?>? artifacts,
}) => PrebuiltManifest.parse(
  jsonEncode({
    'schema': 1,
    'crateVersion': '0.1.0',
    'sourceHash': sourceHash ?? _hash,
    'baseUrl': baseUrl,
    'artifacts':
        artifacts ??
        {
          'macos-arm64': {'file': 'm.dylib', 'sha256': 'cd' * 32, 'size': 5},
          'linux-x64': {'file': 'l.so', 'sha256': 'ef' * 32, 'size': 6},
        },
  }),
);

void main() {
  group('wantsBuildFromSource', () {
    final cases =
        <String, ({Object? define, Map<String, String> env, bool on})>{
          'nothing set': (define: null, env: {}, on: false),
          'user-define true': (define: true, env: {}, on: true),
          'user-define "true"': (define: 'true', env: {}, on: true),
          'user-define false': (define: false, env: {}, on: false),
          'user-define of another type': (define: 3, env: {}, on: false),
          'env 1': (
            define: null,
            env: {'LOTTIE_NATIVE_BUILD_FROM_SOURCE': '1'},
            on: true,
          ),
          'env 0': (
            define: null,
            env: {'LOTTIE_NATIVE_BUILD_FROM_SOURCE': '0'},
            on: false,
          ),
          'env empty': (
            define: null,
            env: {'LOTTIE_NATIVE_BUILD_FROM_SOURCE': ''},
            on: false,
          ),
          'env 0 does not undo the user-define': (
            define: true,
            env: {'LOTTIE_NATIVE_BUILD_FROM_SOURCE': '0'},
            on: true,
          ),
        };
    cases.forEach((name, c) {
      test(name, () {
        expect(
          wantsBuildFromSource(userDefine: c.define, environment: c.env),
          c.on,
        );
      });
    });
  });

  group('matchPrebuilt', () {
    test('finds the artifact and its url when everything agrees', () {
      final match = matchPrebuilt(
        manifest: _manifest(),
        sourceHash: _hash,
        target: _mac,
      );

      match as PrebuiltFound;
      expect(match.artifact.file, 'm.dylib');
      expect(match.url, Uri.parse('https://example.com/p/m.dylib'));
    });

    final missing = <String, PrebuiltMatch>{
      'no manifest': matchPrebuilt(
        manifest: null,
        sourceHash: _hash,
        target: _mac,
      ),
      'a stale sourceHash': matchPrebuilt(
        manifest: _manifest(sourceHash: 'cd' * 32),
        sourceHash: _hash,
        target: _mac,
      ),
      'no artifact for the target': matchPrebuilt(
        manifest: _manifest(artifacts: {}),
        sourceHash: _hash,
        target: _mac,
      ),
      'an empty baseUrl': matchPrebuilt(
        manifest: _manifest(baseUrl: ''),
        sourceHash: _hash,
        target: _mac,
      ),
      'a target without a manifest key': matchPrebuilt(
        manifest: _manifest(),
        sourceHash: _hash,
        target: const LottieNativeTarget(OS.linux, Architecture.ia32),
      ),
    };
    missing.forEach((name, match) {
      test('is missing for $name, with a reason', () {
        expect((match as PrebuiltMissing).reason, isNotEmpty);
      });
    });

    test('a stale sourceHash says so', () {
      final match = matchPrebuilt(
        manifest: _manifest(sourceHash: 'cd' * 32),
        sourceHash: _hash,
        target: _mac,
      );

      expect((match as PrebuiltMissing).reason, contains('sources'));
    });
  });

  group('planDelivery', () {
    final found = matchPrebuilt(
      manifest: _manifest(),
      sourceHash: _hash,
      target: _mac,
    );
    final foundLinux = matchPrebuilt(
      manifest: _manifest(),
      sourceHash: _hash,
      target: _linux,
    );
    const none = PrebuiltMissing('no prebuilt');

    List<String> plan({
      bool flag = false,
      PrebuiltMatch match = none,
      bool cargo = true,
      LottieNativeTarget target = _mac,
      bool host = true,
    }) => [
      for (final step in planDelivery(
        buildFromSource: flag,
        match: match,
        hasCargo: cargo,
        hostBuilds: host,
        target: target,
      ))
        switch (step) {
          CompileFromSource() => 'compile',
          UsePrebuilt() => 'prebuilt',
          NoLibrary() => 'none',
        },
    ];

    test('the flag compiles and never downloads, matching manifest or not', () {
      expect(plan(flag: true, match: found), ['compile']);
    });

    test('the flag compiles even where cargo is missing (it then fails)', () {
      expect(plan(flag: true, cargo: false), ['compile']);
    });

    test('a matching prebuilt is tried first, then the source build', () {
      expect(plan(match: found), ['prebuilt', 'compile']);
    });

    test('a matching prebuilt without cargo ends in no library', () {
      expect(plan(match: found, cargo: false), ['prebuilt', 'none']);
    });

    test('a matching prebuilt for a target this host cannot build', () {
      expect(plan(match: foundLinux, target: _linux, host: false), [
        'prebuilt',
        'none',
      ]);
    });

    test('no prebuilt compiles where the host can', () {
      expect(plan(), ['compile']);
    });

    test('no prebuilt and no cargo is no library', () {
      expect(plan(cargo: false), ['none']);
    });

    test('no prebuilt on an unsupported host is no library', () {
      expect(plan(target: _linux, host: false), ['none']);
    });

    test('the final step is always terminal', () {
      for (final flag in [true, false]) {
        for (final match in [found, none]) {
          for (final cargo in [true, false]) {
            final steps = planDelivery(
              buildFromSource: flag,
              match: match,
              hasCargo: cargo,
              hostBuilds: true,
              target: _mac,
            );
            expect(steps.last, isNot(isA<UsePrebuilt>()));
          }
        }
      }
    });

    test('no library names the target and why', () {
      final steps = planDelivery(
        buildFromSource: false,
        match: const PrebuiltMissing('manifest lists none'),
        hasCargo: true,
        hostBuilds: false,
        target: _linux,
      );

      expect(
        (steps.single as NoLibrary).reason,
        allOf(
          contains('linux'),
          contains('x64'),
          contains('manifest lists none'),
          contains('missingLibrary'),
        ),
      );
    });

    test('no library without cargo says cargo was not found', () {
      final steps = planDelivery(
        buildFromSource: false,
        match: none,
        hasCargo: false,
        hostBuilds: true,
        target: _mac,
      );

      expect((steps.single as NoLibrary).reason, contains('cargo'));
    });

    test(
      'a host that cannot build the target points at the prebuilt route',
      () {
        final steps = planDelivery(
          buildFromSource: false,
          match: none,
          hasCargo: true,
          hostBuilds: false,
          target: _linux,
        );

        expect(
          (steps.single as NoLibrary).reason,
          allOf(contains('cannot build'), contains('prebuilt')),
        );
      },
    );
  });
}
