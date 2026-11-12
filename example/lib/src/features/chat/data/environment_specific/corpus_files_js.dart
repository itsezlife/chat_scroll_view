import 'dart:typed_data';

/// The web hook: the web has no file system, so a corpus directory there
/// lists no pack.
Future<Map<String, List<String>>> $listCorpusFiles(String directory) async =>
    const {};

/// The web hook: a file read on the web is a host mistake, so it fails
/// (permanently).
Future<Uint8List> $readCorpusFile(String path) =>
    Future.error(UnsupportedError('There are no files on the web: $path'));
