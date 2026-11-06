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

import 'artifact_check.dart';
import 'prebuilt_manifest.dart';
import 'targets.dart';

/// The outcome of [fetchPrebuilt].
sealed class PrebuiltFetch {
  const PrebuiltFetch();
}

/// A library on disk whose size and SHA-256 match the manifest and whose
/// header fits the target.
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
/// trusted only if it is a regular file whose real path lies inside
/// [cacheDir] (a symbolic link there, in the file or in its directory, is
/// removed, never followed), and it is verified again and reused with no
/// network; one that no longer verifies is deleted and fetched anew.
///
/// A hash only proves the file is the one the manifest names, not that the
/// manifest named a library for [target]: every file also passes
/// [artifactProblem] (machine or CPU, and 16 KB segments on Android) before it
/// is registered. One that fails is deleted and unavailable, never retried,
/// because the same bytes would fail again.
///
/// The download goes to a temporary `.part` file that is verified and then
/// renamed, so a crash or a concurrent build never leaves the final path
/// holding half a library. [timeout] bounds the whole fetch and really ends
/// it: the connection is closed and the transfer has stopped before the
/// partial file is touched. A redirect is followed only to an HTTPS URL.
///
/// Cleanup never decides the outcome: a file that cannot be deleted is a
/// note in the reason, not an exception and not a different verdict.
Future<PrebuiltFetch> fetchPrebuilt({
  required PrebuiltArtifact artifact,
  required Uri url,
  required Directory cacheDir,
  required LottieNativeTarget target,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final dir = Directory('${cacheDir.path}/${artifact.sha256}');
  final file = File('${dir.path}/${artifact.file}');

  final cached = await _useCached(cacheDir, dir, file, artifact, target, url);
  if (cached != null) return cached;

  final part = File(
    '${file.path}.$pid-${DateTime.now().microsecondsSinceEpoch}.part',
  );
  final client = HttpClient()..connectionTimeout = timeout;
  var aborted = false;
  final transfer = _download(
    client,
    url,
    artifact,
    target,
    part,
    file,
    isAborted: () => aborted,
  );
  PrebuiltFetch result;
  try {
    result = await transfer.timeout(timeout);
  } on TimeoutException {
    aborted = true;
    client.close(force: true);
    // The transfer fails now that its connection is gone; wait for it to
    // close its sink so nothing writes to the part file while it is deleted.
    await transfer
        .then<void>((_) {}, onError: (Object _) {})
        .timeout(const Duration(seconds: 5), onTimeout: () {});
    result = PrebuiltUnavailable(
      'downloading $url timed out after ${timeout.inSeconds}s',
    );
  } on Object catch (error) {
    // A prebuilt is an optimisation: whatever went wrong (DNS, TLS, a reset
    // connection, a full disk) the build goes on without it.
    result = PrebuiltUnavailable('downloading $url failed: $error');
  } finally {
    client.close(force: true);
  }
  final leftover = _discard(part);
  if (leftover != null && result is PrebuiltUnavailable) {
    return PrebuiltUnavailable('${result.reason} ($leftover)');
  }
  return result;
}

/// The cached file when it is trusted, an unavailable verdict when it is
/// unusable for good, or null when a download should follow.
Future<PrebuiltFetch?> _useCached(
  Directory cacheDir,
  Directory dir,
  File file,
  PrebuiltArtifact artifact,
  LottieNativeTarget target,
  Uri url,
) async {
  // A link planted in the cache is removed itself; what it points at is
  // never followed, written to or deleted.
  for (final path in [dir.path, file.path]) {
    if (!FileSystemEntity.isLinkSync(path)) continue;
    try {
      Link(path).deleteSync();
    } on FileSystemException catch (e) {
      return PrebuiltUnavailable('cannot remove the link $path: ${e.message}');
    }
  }
  if (!file.existsSync()) return null;
  final regular =
      FileSystemEntity.typeSync(file.path, followLinks: false) ==
      FileSystemEntityType.file;
  final root = cacheDir.resolveSymbolicLinksSync();
  final inside = file.resolveSymbolicLinksSync().startsWith(
    '$root${Platform.pathSeparator}',
  );
  if (regular && inside && await _mismatch(file, artifact) == null) {
    final problem = artifactProblem(file.readAsBytesSync(), target);
    if (problem == null) return PrebuiltReady(file);
    final note = _discard(file);
    return PrebuiltUnavailable(
      'the cached $url is unusable: $problem${note == null ? '' : ' ($note)'}',
    );
  }
  final note = _discard(file);
  return note == null ? null : PrebuiltUnavailable(note);
}

/// Deletes [file] if it exists. A failure is returned as a line for the log
/// and never thrown: removing a leftover must not change what the fetch
/// concluded.
String? _discard(File file) {
  try {
    if (file.existsSync()) file.deleteSync();
    return null;
  } on FileSystemException catch (e) {
    return 'could not delete ${file.path}: ${e.message}';
  }
}

/// How many redirects one download follows.
const _maxRedirects = 5;

Future<PrebuiltFetch> _download(
  HttpClient client,
  Uri url,
  PrebuiltArtifact artifact,
  LottieNativeTarget target,
  File part,
  File destination, {
  required bool Function() isAborted,
}) async {
  // Redirects are followed by hand: dart:io would follow one to plain HTTP,
  // which would hand a MITM the choice of bytes (the hash still refuses
  // them, but the transfer should never leave HTTPS).
  var current = url;
  late HttpClientResponse response;
  for (var hops = 0; ; hops++) {
    final request = await client.getUrl(current);
    request.followRedirects = false;
    response = await request.close();
    if (!response.isRedirect) break;
    await response.drain<void>();
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (location == null) {
      return PrebuiltUnavailable('$current redirected without a Location');
    }
    final next = current.resolve(location);
    if (next.scheme != 'https') {
      return PrebuiltUnavailable(
        '$current redirected to $next: a redirect to a URL that is not '
        'HTTPS is not followed',
      );
    }
    if (hops >= _maxRedirects) {
      return PrebuiltUnavailable(
        '$url redirected more than $_maxRedirects times',
      );
    }
    current = next;
  }
  if (response.statusCode != HttpStatus.ok) {
    await response.drain<void>();
    return PrebuiltUnavailable(
      '$current answered HTTP ${response.statusCode}, expected 200',
    );
  }

  part.parent.createSync(recursive: true);
  final sink = part.openWrite();
  var received = 0;
  try {
    await for (final chunk in response) {
      if (isAborted()) {
        return PrebuiltUnavailable('$current: the transfer was aborted');
      }
      received += chunk.length;
      // Stop at the declared size: a wrong or hostile server cannot fill the
      // disk before the check at the end.
      if (received > artifact.size) {
        return PrebuiltUnavailable(
          '$current sent more than the ${artifact.size} bytes the manifest '
          'lists',
        );
      }
      sink.add(chunk);
    }
  } finally {
    await sink.close();
  }

  final mismatch = await _mismatch(part, artifact);
  if (mismatch != null) return PrebuiltUnavailable('$current: $mismatch');
  final problem = artifactProblem(part.readAsBytesSync(), target);
  if (problem != null) return PrebuiltUnavailable('$current: $problem');
  // Same directory, so the rename is atomic.
  part.renameSync(destination.path);
  return PrebuiltReady(destination);
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
