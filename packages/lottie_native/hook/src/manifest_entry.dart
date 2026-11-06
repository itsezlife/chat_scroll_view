/// The manifest entry of a built library, for the maintainer to paste under
/// `artifacts` in `native/prebuilts.json`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// `{"file", "sha256", "size"}` of [file] as indented JSON.
///
/// Throws [FileSystemException] when [file] cannot be read.
Future<String> manifestEntryFor(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return const JsonEncoder.withIndent('  ').convert({
    'file': file.uri.pathSegments.last,
    'sha256': digest.toString(),
    'size': file.lengthSync(),
  });
}
