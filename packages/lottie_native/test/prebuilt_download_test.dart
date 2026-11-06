import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// The hook is not part of lib/: a hook may not import the Flutter package
// that it builds for, so its testable logic is reached by path.
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/prebuilt_download.dart';
// ignore: avoid_relative_lib_imports, always_use_package_imports
import '../hook/src/prebuilt_manifest.dart';

final _payload = utf8.encode('pretend this is a dylib ' * 50);
final _digest = sha256.convert(_payload).toString();

PrebuiltArtifact _artifact({
  String? sha256,
  int? size,
  String file = 'libchat_lottie.dylib',
}) => PrebuiltArtifact(
  file: file,
  sha256: sha256 ?? _digest,
  size: size ?? _payload.length,
);

void main() {
  late Directory cache;
  late HttpServer server;
  late Uri url;
  var requests = 0;
  late Future<void> Function(HttpRequest request) handler;

  setUp(() async {
    cache = Directory.systemTemp.createTempSync('prebuilt_download_test');
    requests = 0;
    handler = (request) async {
      request.response.add(_payload);
      await request.response.close();
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = Uri.parse('http://127.0.0.1:${server.port}/libchat_lottie.dylib');
    server.listen((request) {
      requests++;
      unawaited(handler(request));
    });
  });

  tearDown(() async {
    await server.close(force: true);
    cache.deleteSync(recursive: true);
  });

  Future<PrebuiltFetch> fetch({
    PrebuiltArtifact? artifact,
    Duration timeout = const Duration(seconds: 5),
  }) => fetchPrebuilt(
    artifact: artifact ?? _artifact(),
    url: url,
    cacheDir: cache,
    timeout: timeout,
  );

  /// Every file left anywhere under the cache.
  List<String> leftovers() => [
    for (final e in cache.listSync(recursive: true))
      if (e is File) e.path,
  ];

  group('fetchPrebuilt', () {
    test('downloads, verifies and stores under the sha256', () async {
      final result = await fetch();

      final ready = result as PrebuiltReady;
      expect(ready.file.readAsBytesSync(), _payload);
      expect(ready.file.path, contains(_digest));
      expect(ready.file.path, endsWith('libchat_lottie.dylib'));
      expect(leftovers(), [ready.file.path], reason: 'no temp file remains');
    });

    test('a 404 is unavailable and leaves nothing', () async {
      handler = (request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final result = await fetch();

      expect(
        (result as PrebuiltUnavailable).reason,
        allOf(contains('404'), contains(url.toString())),
      );
      expect(leftovers(), isEmpty);
    });

    test('a truncated body is unavailable and leaves nothing', () async {
      handler = (request) async {
        request.response.contentLength = _payload.length;
        final socket = await request.response.detachSocket();
        socket.add(_payload.sublist(0, 10));
        await socket.flush();
        socket.destroy();
      };

      final result = await fetch();

      expect(result, isA<PrebuiltUnavailable>());
      expect(leftovers(), isEmpty);
    });

    test('a wrong sha256 is refused and the file deleted', () async {
      final result = await fetch(artifact: _artifact(sha256: 'ab' * 32));

      expect(
        (result as PrebuiltUnavailable).reason,
        allOf(contains('sha256'), contains('ab' * 32)),
      );
      expect(leftovers(), isEmpty);
    });

    test('a wrong size is refused and the file deleted', () async {
      final result = await fetch(
        artifact: _artifact(size: _payload.length + 5),
      );

      expect(
        (result as PrebuiltUnavailable).reason,
        contains('${_payload.length + 5}'),
      );
      expect(leftovers(), isEmpty);
    });

    test(
      'a body longer than the declared size is not buffered whole',
      () async {
        final result = await fetch(artifact: _artifact(size: 10));

        expect(result, isA<PrebuiltUnavailable>());
        expect(leftovers(), isEmpty);
      },
    );

    test('a slow server hits the timeout', () async {
      final never = Completer<void>();
      handler = (request) => never.future;

      final watch = Stopwatch()..start();
      final result = await fetch(timeout: const Duration(milliseconds: 300));

      expect((result as PrebuiltUnavailable).reason, contains('timed out'));
      expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
      expect(leftovers(), isEmpty);
    });

    test('an unreachable server is unavailable, not an exception', () async {
      await server.close(force: true);

      final result = await fetch();

      expect(result, isA<PrebuiltUnavailable>());
    });

    test('a verified cached file is reused with no network at all', () async {
      final first = await fetch() as PrebuiltReady;
      await server.close(force: true);
      final before = requests;

      final second = await fetch();

      expect((second as PrebuiltReady).file.path, first.file.path);
      expect(requests, before);
    });

    test('a cached file that no longer verifies is replaced', () async {
      final first = await fetch() as PrebuiltReady;
      first.file.writeAsBytesSync(List.filled(_payload.length, 0));
      final before = requests;

      final second = await fetch() as PrebuiltReady;

      expect(second.file.readAsBytesSync(), _payload);
      expect(requests, before + 1);
    });

    test(
      'a corrupt cached file is deleted when it cannot be replaced',
      () async {
        final first = await fetch() as PrebuiltReady;
        first.file.writeAsBytesSync(List.filled(_payload.length, 0));
        await server.close(force: true);

        final result = await fetch();

        expect(result, isA<PrebuiltUnavailable>());
        expect(first.file.existsSync(), isFalse);
      },
    );

    test('a partial temp file is never taken for the artifact', () async {
      await server.close(force: true);
      final dir = Directory('${cache.path}/$_digest')..createSync();
      File('${dir.path}/libchat_lottie.dylib.part').writeAsBytesSync(_payload);

      final result = await fetch();

      expect(result, isA<PrebuiltUnavailable>());
      expect(File('${dir.path}/libchat_lottie.dylib').existsSync(), isFalse);
    });
  });
}
