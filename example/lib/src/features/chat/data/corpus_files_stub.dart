import 'dart:typed_data';

/// The web has no file system: a corpus directory there lists no pack.
Future<Map<String, List<String>>> listCorpusFiles(String directory) async =>
    const {};

/// A file read on the web is a host mistake, so it fails (permanently).
Future<Uint8List> readCorpusFile(String path) =>
    Future.error(UnsupportedError('There are no files on the web: $path'));
