/// The scroll lab's network tape: what it stores while recording and serves
/// while replaying.
///
/// **Seam:** [LabNetClient] over a fake `http.Client`, with a temp directory as
/// the files directory, observed through the responses, the inner calls and
/// the files on disk. No real request is made.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chat_scroll_view_example/src/common/lab_net.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/giphy_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory dir;
  late List<String> logs;
  late List<Uri> inner;
  late LabNet net;

  http.Client origin(Map<String, http.Response> answers) =>
      MockClient((request) async {
        inner.add(request.url);
        return answers[request.url.path] ?? http.Response('nope', 404);
      });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lab_net_test');
    logs = [];
    inner = [];
    net = LabNet(filesDir: () async => dir.path, log: logs.add);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Uri api(String path, {String key = 'SECRETKEY', String extra = ''}) =>
      Uri.parse('https://api.giphy.com$path?api_key=$key$extra');

  String everythingOnDisk() => [
    for (final f in dir.listSync(recursive: true))
      if (f is File) '${f.path}\n${latin1.decode(f.readAsBytesSync())}',
  ].join('\n');

  test('a recorded response is served again, with no network', () async {
    final answers = {
      '/v1/gifs/trending': http.Response(
        '{"data":[]}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    };
    await net.select(LabNetMode.record, 't');
    final recorded = await LabNetClient(
      origin(answers),
      net,
    ).get(api('/v1/gifs/trending'));
    expect(recorded.body, '{"data":[]}');
    expect(inner, hasLength(1));

    await net.select(LabNetMode.replay, 't');
    final replayed = await LabNetClient(
      origin({}),
      net,
    ).get(api('/v1/gifs/trending'));
    expect(replayed.statusCode, 200);
    expect(replayed.body, '{"data":[]}');
    expect(replayed.headers['content-type'], 'application/json');
    expect(inner, hasLength(1), reason: 'the replay asked nobody');
    expect(net.hits, 1);
  });

  test('the key is never on disk, and any key finds the same file', () async {
    await net.select(LabNetMode.record, 't');
    await LabNetClient(
      origin({'/v1/gifs/search': http.Response('a', 200)}),
      net,
    ).get(api('/v1/gifs/search', extra: '&q=cat'));
    expect(everythingOnDisk(), isNot(contains('SECRETKEY')));
    final files = Directory('${dir.path}/t.net').listSync();
    expect(files, hasLength(1));

    await net.select(LabNetMode.replay, 't');
    final other = await LabNetClient(origin({}), net).get(
      // Another key and the parameters in another order.
      Uri.parse('https://api.giphy.com/v1/gifs/search?q=cat&api_key=OTHER'),
    );
    expect(other.body, 'a');
    expect(logs.join(), isNot(contains('SECRETKEY')));
  });

  test('a miss answers an error without the network, and logs once', () async {
    await net.select(LabNetMode.replay, 't');
    final client = LabNetClient(origin({}), net);
    final first = await client.get(api('/v1/gifs/trending'));
    await client.get(api('/v1/gifs/trending'));
    expect(first.statusCode, 504);
    expect(inner, isEmpty);
    expect(net.misses, 2);
    final missLogs = logs.where((l) => l.contains('net miss')).toList();
    expect(missLogs, hasLength(1));
    expect(missLogs.single, contains('/v1/gifs/trending'));
    expect(missLogs.single, isNot(contains('SECRETKEY')));
  });

  test('off passes through and writes nothing', () async {
    final answers = {'/x': http.Response('x', 200)};
    final response = await LabNetClient(origin(answers), net).get(api('/x'));
    expect(response.body, 'x');
    expect(inner, hasLength(1));
    expect(dir.listSync(), isEmpty);
  });

  test('recording again clears the previous recording of that tape', () async {
    await net.select(LabNetMode.record, 't');
    await LabNetClient(
      origin({'/a': http.Response('a', 200)}),
      net,
    ).get(api('/a'));
    await net.select(LabNetMode.off, 't');
    await net.select(LabNetMode.record, 't');
    expect(Directory('${dir.path}/t.net').listSync(), isEmpty);
  });

  test('selecting the mode it is in keeps what was recorded', () async {
    await net.select(LabNetMode.record, 't');
    await LabNetClient(
      origin({'/a': http.Response('a', 200)}),
      net,
    ).get(api('/a'));
    await net.select(LabNetMode.record, 't');
    expect(Directory('${dir.path}/t.net').listSync(), hasLength(1));
  });

  test('a recorded 404 and 500 are replayed as recorded', () async {
    await net.select(LabNetMode.record, 't');
    final client = LabNetClient(
      origin({
        '/gone': http.Response('', 404),
        '/boom': http.Response('oops', 500),
      }),
      net,
    );
    await client.get(api('/gone'));
    await client.get(api('/boom'));
    await net.select(LabNetMode.replay, 't');
    final replay = LabNetClient(origin({}), net);
    expect((await replay.get(api('/gone'))).statusCode, 404);
    final boom = await replay.get(api('/boom'));
    expect(boom.statusCode, 500);
    expect(boom.body, 'oops');
    expect(net.misses, 0);
  });

  test('binary bodies come back byte for byte', () async {
    final bytes = Uint8List.fromList([for (var i = 0; i < 256; i++) i, 10, 10]);
    await net.select(LabNetMode.record, 't');
    await LabNetClient(
      origin({
        '/clip.mp4': http.Response.bytes(
          bytes,
          200,
          headers: {'content-type': 'video/mp4'},
        ),
      }),
      net,
    ).get(Uri.parse('https://media.example/clip.mp4'));
    await net.select(LabNetMode.replay, 't');
    final back = await LabNetClient(
      origin({}),
      net,
    ).get(Uri.parse('https://media.example/clip.mp4'));
    expect(back.bodyBytes, bytes);
    expect(back.headers['content-type'], 'video/mp4');
  });

  test('a download recorded and replayed reports its progress, in one step '
      'when replayed', () async {
    final bytes = Uint8List.fromList(List.filled(300, 7));
    final url = Uri.parse('https://media.example/clip.mp4');
    GiphyClient giphy(http.Client inner) =>
        GiphyClient(apiKey: 'SECRETKEY', client: LabNetClient(inner, net));
    final recorded = <(int, int?)>[];
    final replayed = <(int, int?)>[];

    await net.select(LabNetMode.record, 't');
    await giphy(
      origin({'/clip.mp4': http.Response.bytes(bytes, 200)}),
    ).download(url, onProgress: (r, t) => recorded.add((r, t)));
    await net.select(LabNetMode.replay, 't');
    final back = await giphy(
      origin({}),
    ).download(url, onProgress: (r, t) => replayed.add((r, t)));

    expect(back, bytes);
    expect(recorded.last, (300, 300));
    expect(replayed, [(0, 300), (300, 300)]);
    expect(inner, hasLength(1), reason: 'the replay asked nobody');
  });

  test('logs the replay summary line', () async {
    await net.select(LabNetMode.replay, 't');
    await LabNetClient(origin({}), net).get(api('/miss'));
    net.logSummary();
    expect(logs.last, 'net replay hits=0 misses=1');
  });

  group('net_mode.txt', () {
    test('selects the mode before the first request', () async {
      await net.select(LabNetMode.record, 't');
      await LabNetClient(
        origin({'/a': http.Response('a', 200)}),
        net,
      ).get(api('/a'));
      final fresh = LabNet(filesDir: () async => dir.path, log: logs.add);
      File('${dir.path}/net_mode.txt').writeAsStringSync('replay t\n');
      await fresh.loadPersisted();
      expect(fresh.mode, LabNetMode.replay);
      final r = await LabNetClient(origin({}), fresh).get(api('/a'));
      expect(r.body, 'a');
    });

    test('a request waits for it', () async {
      File('${dir.path}/net_mode.txt').writeAsStringSync('replay t');
      final fresh = LabNet(filesDir: () async => dir.path, log: logs.add);
      final loading = fresh.loadPersisted();
      final pending = LabNetClient(origin({}), fresh).get(api('/a'));
      await loading;
      expect((await pending).statusCode, 504);
      expect(inner, isEmpty);
    });

    test('a missing or odd file leaves the mode off', () async {
      await net.loadPersisted();
      expect(net.mode, LabNetMode.off);
      File('${dir.path}/net_mode.txt').writeAsStringSync('banana');
      await net.loadPersisted();
      expect(net.mode, LabNetMode.off);
    });
  });
}
