import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// What the lab's network tape does with a request.
enum LabNetMode {
  /// Pass through; the tape is not touched.
  off,

  /// Pass through, and store every response under the tape.
  record,

  /// Answer from the tape only; the network is never reached.
  replay,
}

/// The scroll lab's network tape: the mode, which tape, and the folder
/// `<filesDir>/<tape>.net` that holds the recorded responses.
///
/// A perf replay of a recorded pointer tape must see the content the recording
/// saw. Live Giphy gives it neither (trending changes, the free key runs out of
/// calls), so the responses are recorded with the pointer tape and replayed
/// from disk. [LabNetClient] consults [mode] on every request, so a switch
/// takes effect on the next call with nothing to re-wire; the host's client is
/// wrapped once, at startup.
final class LabNet {
  /// Creates a tape under the directory [filesDir] resolves.
  ///
  /// [log] gets the lab's lines, without the `LAB ` prefix.
  LabNet({
    required Future<String> Function() filesDir,
    void Function(String)? log,
  }) : _filesDir = filesDir,
       _log = log ?? ((line) => debugPrint('LAB $line'));

  /// The lab's one tape, over the app's external files directory.
  static LabNet? instance;

  final Future<String> Function() _filesDir;
  final void Function(String) _log;

  static const _modeFile = 'net_mode.txt';

  LabNetMode _mode = LabNetMode.off;
  String? _tape;
  Directory? _folder;
  Future<void> _ready = Future.value();
  final _missed = <String>{};
  int _hits = 0;
  int _misses = 0;

  /// What requests do now.
  LabNetMode get mode => _mode;

  /// Requests answered from the tape since replay began.
  int get hits => _hits;

  /// Requests the tape had no answer for since replay began.
  int get misses => _misses;

  /// Completes when the persisted mode (see [loadPersisted]) is in force. A
  /// request waits for it, so the first one of a cold start does not slip past.
  Future<void> get ready => _ready;

  /// Switches to [mode] on the tape [tape].
  ///
  /// Selecting the mode and tape already in force changes nothing, so a
  /// cold-start request counted before the replay command is kept. Recording
  /// starts from an empty folder.
  Future<void> select(LabNetMode mode, String tape) async {
    if (mode == _mode && tape == _tape) return;
    final folder = Directory('${await _filesDir()}/$tape.net');
    _mode = mode;
    _tape = tape;
    _folder = folder;
    switch (mode) {
      case LabNetMode.record:
        if (folder.existsSync()) folder.deleteSync(recursive: true);
        folder.createSync(recursive: true);
      case LabNetMode.replay:
        _hits = 0;
        _misses = 0;
        _missed.clear();
      case LabNetMode.off:
        break;
    }
    _log('net mode ${mode.name} $tape');
  }

  /// Reads `<filesDir>/net_mode.txt` (`replay <tape>`, `record <tape>`, `off`)
  /// and selects what it says.
  ///
  /// A host starts cold and may ask Giphy before `adb` can send a broadcast;
  /// the file, written before launch, is how the mode is in force by then. A
  /// missing or unreadable file leaves the mode alone.
  Future<void> loadPersisted() => _ready = _loadPersisted();

  Future<void> _loadPersisted() async {
    try {
      final file = File('${await _filesDir()}/$_modeFile');
      if (!file.existsSync()) return;
      final words = (await file.readAsString()).trim().split(RegExp(r'\s+'));
      final mode = LabNetMode.values.asNameMap()[words.first];
      if (mode == null || words.length < 2) return;
      await select(mode, words[1]);
    } on Object catch (error) {
      _log('net mode file unreadable: $error');
    }
  }

  /// Logs `net replay hits=N misses=M`.
  void logSummary() => _log('net replay hits=$_hits misses=$_misses');

  // --- Folder ---------------------------------------------------------------

  /// [url] without its `api_key`, with the other parameters sorted: the same
  /// request under any key and in any order of parameters. Also what is logged
  /// and stored in place of the URL, so the key reaches neither disk nor log.
  static String canonical(Uri url) {
    final params = <String>[
      for (final MapEntry(:key, :value) in url.queryParametersAll.entries)
        if (key != 'api_key')
          for (final v in value)
            '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(v)}',
    ]..sort();
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    return '${url.scheme}://${url.host}${url.path}$query';
  }

  // Two 32-bit FNV-1a runs from different offsets: 64 bits of name without
  // 64-bit ints, which the web build of the example cannot hold.
  static String _hash(String text) {
    final bytes = utf8.encode(text);
    String run(int seed) {
      var h = seed;
      for (final b in bytes) {
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF;
      }
      return h.toRadixString(16).padLeft(8, '0');
    }

    return run(0x811c9dc5) + run(0x1b873593);
  }

  File _fileOf(String canonicalUrl) =>
      File('${_folder!.path}/${_hash(canonicalUrl)}');

  /// Stores [response] for [url]: a JSON line (status, content type, the URL
  /// without its key), then the body bytes.
  Future<void> _store(Uri url, int status, String? type, Uint8List body) async {
    final canon = canonical(url);
    final header = jsonEncode({'s': status, 't': type, 'u': canon});
    await _fileOf(canon).writeAsBytes([...utf8.encode(header), 10, ...body]);
  }

  /// The recorded answer for [url], or null, counting the hit or the miss.
  Future<({int status, String? type, Uint8List body})?> _find(Uri url) async {
    final canon = canonical(url);
    final file = _fileOf(canon);
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      final end = bytes.indexOf(10);
      final header = jsonDecode(utf8.decode(bytes.sublist(0, end)));
      _hits++;
      return (
        status: header['s'] as int,
        type: header['t'] as String?,
        body: Uint8List.sublistView(bytes, end + 1),
      );
    }
    _misses++;
    if (_missed.add(canon)) _log('net miss $canon');
    return null;
  }
}

/// An `http.Client` that sends through [inner] and the lab's [net] tape, by
/// the mode the tape is in at each request.
///
/// Compiled in but wrapped only when the example is built as the scroll lab.
final class LabNetClient extends http.BaseClient {
  /// Wraps [inner].
  LabNetClient(this.inner, this.net);

  /// The real transport, used when the mode is not replay.
  final http.Client inner;

  /// The tape.
  final LabNet net;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await net.ready;
    switch (net.mode) {
      case LabNetMode.off:
        return inner.send(request);
      case LabNetMode.record:
        final live = await http.Response.fromStream(await inner.send(request));
        await net._store(
          request.url,
          live.statusCode,
          live.headers['content-type'],
          live.bodyBytes,
        );
        return _streamed(
          request,
          live.statusCode,
          live.headers['content-type'],
          live.bodyBytes,
        );
      case LabNetMode.replay:
        final found = await net._find(request.url);
        // A miss is a gateway timeout: the callers treat it as a failed
        // request, as they would a dead network, and nothing left the device.
        return found == null
            ? _streamed(request, 504, null, Uint8List(0))
            : _streamed(request, found.status, found.type, found.body);
    }
  }

  static http.StreamedResponse _streamed(
    http.BaseRequest request,
    int status,
    String? type,
    Uint8List body,
  ) => http.StreamedResponse(
    http.ByteStream.fromBytes(body),
    status,
    contentLength: body.length,
    request: request,
    headers: {'content-type': ?type},
  );

  @override
  void close() => inner.close();
}
