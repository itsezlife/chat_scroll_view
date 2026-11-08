import 'dart:io';
import 'dart:typed_data';

/// The VM hook behind a `FetchedFile` decode: the bytes of the file at
/// [path].
Future<Uint8List> $readFileBytes(String path) => File(path).readAsBytes();
