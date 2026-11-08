import 'dart:typed_data';

/// The web hook behind a `FetchedFile` decode: the web has no file system, so
/// a `FetchedFile` there is a host mistake and fails the decode (permanently)
/// instead of waiting on a read that cannot happen.
Future<Uint8List> $readFileBytes(String path) =>
    Future.error(UnsupportedError('There are no files on the web: $path'));
