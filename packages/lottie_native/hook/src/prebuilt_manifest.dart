/// `native/prebuilts.json`: which prebuilt native libraries exist, where they
/// are hosted and how to verify them.
///
/// The format is documented in the README ("Native library delivery"). The
/// parse is strict about everything the hook acts on (hashes, sizes, the
/// URL) and lenient about everything it does not (unknown keys are ignored,
/// so a newer manifest with extra fields still works).
library;

import 'dart:convert';

/// One prebuilt library: the file name under `baseUrl` and what it must
/// hash and measure to be accepted.
final class PrebuiltArtifact {
  /// Creates the artifact; use [PrebuiltManifest.parse] for a validated one.
  const PrebuiltArtifact({
    required this.file,
    required this.sha256,
    required this.size,
  });

  /// The file name under the manifest's `baseUrl`, a bare name.
  final String file;

  /// The lower-case hex SHA-256 of the file.
  final String sha256;

  /// The file's length in bytes.
  final int size;
}

/// A parsed manifest. An empty one (no `baseUrl`, no artifacts) is valid: it
/// means no prebuilt exists yet, which the hook treats as "compile".
final class PrebuiltManifest {
  const PrebuiltManifest._({
    required this.crateVersion,
    required this.sourceHash,
    required this.baseUrl,
    required this.artifacts,
  });

  /// Parses [source].
  ///
  /// Throws [FormatException] naming the offending field when the document
  /// is not a schema-1 manifest.
  factory PrebuiltManifest.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('prebuilts.json is not JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('prebuilts.json must be a JSON object');
    }
    if (decoded['schema'] != 1) {
      throw FormatException(
        'prebuilts.json "schema" must be 1, found ${decoded['schema']}',
      );
    }
    return PrebuiltManifest._(
      crateVersion: _string(decoded, 'crateVersion'),
      sourceHash: _hex(decoded, 'sourceHash'),
      baseUrl: _baseUrl(_string(decoded, 'baseUrl')),
      artifacts: {
        for (final MapEntry(:key, :value) in _object(
          decoded,
          'artifacts',
        ).entries)
          key: _artifact(key, value),
      },
    );
  }

  /// The `Cargo.toml` package version the artifacts were built from.
  final String crateVersion;

  /// The hash of the crate sources the artifacts were built from (see
  /// `source_hash.dart`). Artifacts apply only while it equals the hash of
  /// the sources in the package.
  final String sourceHash;

  /// Where the files are hosted, absolute https ending with `/`; null when
  /// nothing is published.
  final Uri? baseUrl;

  /// Artifacts by target key (`LottieNativeTarget.key`).
  final Map<String, PrebuiltArtifact> artifacts;

  /// The artifact for the target [key], or null.
  PrebuiltArtifact? artifactFor(String key) => artifacts[key];

  /// Where [artifact] is downloaded from, or null without a [baseUrl].
  Uri? urlOf(PrebuiltArtifact artifact) => baseUrl?.resolve(artifact.file);
}

final _hexDigest = RegExp(r'^[0-9a-f]{64}$');

String _string(Map<String, Object?> from, String key) {
  final value = from[key];
  if (value is! String) {
    throw FormatException('prebuilts.json "$key" must be a string');
  }
  return value;
}

Map<String, Object?> _object(Map<String, Object?> from, String key) {
  final value = from[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('prebuilts.json "$key" must be an object');
  }
  return value;
}

String _hex(Map<String, Object?> from, String key) {
  final value = _string(from, key);
  if (!_hexDigest.hasMatch(value)) {
    throw FormatException(
      'prebuilts.json "$key" must be 64 lower-case hex digits',
    );
  }
  return value;
}

Uri? _baseUrl(String value) {
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      !value.endsWith('/')) {
    throw FormatException(
      'prebuilts.json "baseUrl" must be an absolute https URL ending with '
      '"/" (or empty), found "$value"',
    );
  }
  return uri;
}

PrebuiltArtifact _artifact(String key, Object? value) {
  if (value is! Map<String, Object?>) {
    throw FormatException('prebuilts.json artifact "$key" must be an object');
  }
  final file = _string(value, 'file');
  // The name is joined onto a directory and a URL: only a bare name is safe.
  if (file.isEmpty ||
      file == '.' ||
      file == '..' ||
      file.contains('/') ||
      file.contains(r'\')) {
    throw FormatException(
      'prebuilts.json artifact "$key" "file" must be a bare file name, '
      'found "$file"',
    );
  }
  final size = value['size'];
  if (size is! int || size <= 0) {
    throw FormatException(
      'prebuilts.json artifact "$key" "size" must be a positive integer',
    );
  }
  return PrebuiltArtifact(
    file: file,
    sha256: _hex(value, 'sha256'),
    size: size,
  );
}
