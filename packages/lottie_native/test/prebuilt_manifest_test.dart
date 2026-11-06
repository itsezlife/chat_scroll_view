import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/prebuilt_manifest.dart';

final _hash = 'ab' * 32;
final _other = 'cd' * 32;

String _manifest({
  Object? schema = 1,
  Object? crateVersion = '0.1.0',
  Object? sourceHash,
  Object? baseUrl = 'https://example.com/lottie/',
  Object? artifacts,
  Map<String, Object?> extra = const {},
}) => jsonEncode({
  'schema': schema,
  'crateVersion': crateVersion,
  'sourceHash': sourceHash ?? _hash,
  'baseUrl': baseUrl,
  'artifacts':
      artifacts ??
      {
        'macos-arm64': {
          'file': 'libchat_lottie.dylib',
          'sha256': _other,
          'size': 12,
        },
      },
  ...extra,
});

void main() {
  group('PrebuiltManifest.parse', () {
    test('reads a valid manifest', () {
      final manifest = PrebuiltManifest.parse(_manifest());

      expect(manifest.crateVersion, '0.1.0');
      expect(manifest.sourceHash, _hash);
      expect(manifest.baseUrl, Uri.parse('https://example.com/lottie/'));
      final artifact = manifest.artifactFor('macos-arm64')!;
      expect(artifact.file, 'libchat_lottie.dylib');
      expect(artifact.sha256, _other);
      expect(artifact.size, 12);
      expect(manifest.artifactFor('linux-x64'), isNull);
    });

    test('an empty manifest is valid and means no prebuilt', () {
      final manifest = PrebuiltManifest.parse(
        _manifest(baseUrl: '', artifacts: <String, Object?>{}),
      );

      expect(manifest.baseUrl, isNull);
      expect(manifest.artifacts, isEmpty);
      expect(manifest.artifactFor('macos-arm64'), isNull);
    });

    test('resolves an artifact against baseUrl', () {
      final manifest = PrebuiltManifest.parse(_manifest());

      expect(
        manifest.urlOf(manifest.artifactFor('macos-arm64')!),
        Uri.parse('https://example.com/lottie/libchat_lottie.dylib'),
      );
    });

    test('has no url when baseUrl is empty', () {
      final manifest = PrebuiltManifest.parse(_manifest(baseUrl: ''));

      expect(manifest.urlOf(manifest.artifactFor('macos-arm64')!), isNull);
    });

    test('ignores keys it does not know, at any level', () {
      final manifest = PrebuiltManifest.parse(
        _manifest(
          extra: {'future': 1},
          artifacts: {
            'macos-arm64': {
              'file': 'a.dylib',
              'sha256': _other,
              'size': 1,
              'signature': 'x',
            },
            'plan9-mips': {'file': 'z', 'sha256': _other, 'size': 1},
          },
        ),
      );

      expect(manifest.artifactFor('macos-arm64')!.file, 'a.dylib');
    });

    final rejected = <String, String>{
      'not json': 'nope',
      'not an object': '[]',
      'wrong schema': _manifest(schema: 2),
      'missing schema': _manifest(schema: null),
      'sourceHash with non-hex': _manifest(sourceHash: 'zz' * 32),
      'sourceHash too short': _manifest(sourceHash: 'ab'),
      'sourceHash in upper case': _manifest(sourceHash: 'AB' * 32),
      'relative baseUrl': _manifest(baseUrl: 'lottie/'),
      'http baseUrl': _manifest(baseUrl: 'http://example.com/lottie/'),
      'baseUrl without trailing slash': _manifest(
        baseUrl: 'https://example.com/lottie',
      ),
      'artifact sha256 with non-hex': _manifest(
        artifacts: {
          'macos-arm64': {'file': 'a', 'sha256': 'g' * 64, 'size': 1},
        },
      ),
      'artifact size zero': _manifest(
        artifacts: {
          'macos-arm64': {'file': 'a', 'sha256': _other, 'size': 0},
        },
      ),
      'artifact size not an int': _manifest(
        artifacts: {
          'macos-arm64': {'file': 'a', 'sha256': _other, 'size': '1'},
        },
      ),
      'artifact file that climbs out': _manifest(
        artifacts: {
          'macos-arm64': {'file': '../a', 'sha256': _other, 'size': 1},
        },
      ),
      'artifact file with a separator': _manifest(
        artifacts: {
          'macos-arm64': {'file': 'x/a', 'sha256': _other, 'size': 1},
        },
      ),
      'artifact missing file': _manifest(
        artifacts: {
          'macos-arm64': {'sha256': _other, 'size': 1},
        },
      ),
    };
    rejected.forEach((name, source) {
      test('rejects $name', () {
        expect(() => PrebuiltManifest.parse(source), throwsFormatException);
      });
    });
  });

  group('the committed native/prebuilts.json', () {
    test('parses, and lists no artifact until one is published', () {
      final source = File('native/prebuilts.json').readAsStringSync();

      final manifest = PrebuiltManifest.parse(source);

      expect(manifest.artifacts, isEmpty);
      expect(manifest.baseUrl, isNull);
    });
  });
}
