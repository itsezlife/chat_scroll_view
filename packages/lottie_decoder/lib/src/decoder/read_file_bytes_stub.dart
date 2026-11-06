import 'dart:typed_data';

/// The web has no file system: a `FetchedFile` there is a host mistake, so it
/// fails the decode (permanently) instead of waiting on a read that cannot
/// happen.
Future<Uint8List> readFileBytes(String path) =>
    Future.error(UnsupportedError('There are no files on the web: $path'));
