/// Prints the `prebuilts.json` entry of a built library:
///
/// ```sh
/// dart native/tool/manifest_entry.dart path/to/libchat_lottie-linux-x64.so
/// ```
///
/// The entry's file name is the file's own name, so name each library the way
/// it is uploaded.
library;

import 'dart:io';

import '../../hook/src/manifest_entry.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart native/tool/manifest_entry.dart <library>');
    exitCode = 64;
    return;
  }
  stdout.writeln(await manifestEntryFor(File(args[0])));
}
