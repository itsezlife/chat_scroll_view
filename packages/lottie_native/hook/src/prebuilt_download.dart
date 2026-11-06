/// Fetches a prebuilt library into the hook's shared cache and refuses
/// anything that is not exactly the manifest's artifact.
///
/// Never fatal: every failure (network, status, timeout, size, hash) is a
/// [PrebuiltUnavailable] with a reason to log, and the hook then compiles
/// from source if it can.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'prebuilt_manifest.dart';

/// The outcome of [fetchPrebuilt].
sealed class PrebuiltFetch {
  const PrebuiltFetch();
}

/// A library on disk whose size and SHA-256 match the manifest.
final class PrebuiltReady extends PrebuiltFetch {
  /// Creates the result for [file].
  const PrebuiltReady(this.file);

  /// The verified library.
  final File file;
}

/// No usable library; [reason] is a line for the build log.
final class PrebuiltUnavailable extends PrebuiltFetch {
  /// Creates the result with its [reason].
  const PrebuiltUnavailable(this.reason);

  /// Why nothing was fetched.
  final String reason;
}

/// Resolves [artifact] to a verified file under [cacheDir], downloading it
/// from [url] when it is not already there.
///
/// The file lives at `<cacheDir>/<sha256>/<file>`: named by its hash so
/// every build of every consumer shares it and a different build of the
/// library is a different path, with the original name kept inside because
/// a dynamic library's file name matters to the loader. A cached file is
/// verified again and reused with no network; one that no longer verifies is
/// deleted and fetched anew.
///
/// The download goes to a temporary `.part` file that is verified and then
/// renamed, so a crash or a concurrent build never leaves the final path
/// holding half a library. [timeout] bounds the whole fetch.
Future<PrebuiltFetch> fetchPrebuilt({
  required PrebuiltArtifact artifact,
  required Uri url,
  required Directory cacheDir,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final dir = Directory('${cacheDir.path}/${artifact.sha256}');
  final target = File('${dir.path}/${artifact.file}');
  if (target.existsSync()) {
    if (await _mismatch(target, artifact) == null) return PrebuiltReady(target);
    target.deleteSync();
  }

  final part = File(
    '${target.path}.$pid-${DateTime.now().microsecondsSinceEpoch}.part',
  );
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    return await _download(
      client,
      url,
      artifact,
      part,
      target,
    ).timeout(timeout);
  } on TimeoutException {
    return PrebuiltUnavailable(
      'downloading $url timed out after ${timeout.inSeconds}s',
    );
  } on Object catch (error) {
    // A prebuilt is an optimisation: whatever went wrong (DNS, TLS, a reset
    // connection, a full disk) the build goes on without it.
    return PrebuiltUnavailable('downloading $url failed: $error');
  } finally {
    client.close(force: true);
    if (part.existsSync()) part.deleteSync();
  }
}

Future<PrebuiltFetch> _download(
  HttpClient client,
  Uri url,
  PrebuiltArtifact artifact,
  File part,
  File target,
) async {
  final request = await client.getUrl(url);
  final response = await request.close();
  if (response.statusCode != HttpStatus.ok) {
    await response.drain<void>();
    return PrebuiltUnavailable(
      '$url answered HTTP ${response.statusCode}, expected 200',
    );
  }

  part.parent.createSync(recursive: true);
  final sink = part.openWrite();
  var received = 0;
  try {
    await for (final chunk in response) {
      received += chunk.length;
      // Stop at the declared size: a wrong or hostile server cannot fill the
      // disk before the check at the end.
      if (received > artifact.size) {
        return PrebuiltUnavailable(
          '$url sent more than the ${artifact.size} bytes the manifest lists',
        );
      }
      sink.add(chunk);
    }
  } finally {
    await sink.close();
  }

  final mismatch = await _mismatch(part, artifact);
  if (mismatch != null) return PrebuiltUnavailable('$url: $mismatch');
  // Same directory, so the rename is atomic.
  part.renameSync(target.path);
  return PrebuiltReady(target);
}

/// Why [file] is not [artifact] (size first, it is cheap), or null when it
/// is.
Future<String?> _mismatch(File file, PrebuiltArtifact artifact) async {
  final length = file.lengthSync();
  if (length != artifact.size) {
    return 'size is $length bytes, the manifest says ${artifact.size}';
  }
  final digest = (await sha256.bind(file.openRead()).first).toString();
  if (digest != artifact.sha256) {
    return 'sha256 is $digest, the manifest says ${artifact.sha256}';
  }
  return null;
}
