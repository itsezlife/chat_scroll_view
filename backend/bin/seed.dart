import 'dart:io';

import 'package:chat_demo_backend/seed_runner.dart';

Future<void> main(List<String> args) async {
  var assetsDir = 'assets/comments';
  var dbPath = 'backend/data/demo.db';
  var force = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--assets-dir':
        assetsDir = args[++i];
      case '--db':
        dbPath = args[++i];
      case '--force':
        force = true;
      case '--help':
        stdout.writeln(
          'Usage: dart run bin/seed.dart [--assets-dir PATH] [--db PATH] [--force]',
        );
        exit(0);
    }
  }

  // Resolve paths relative to repo root when run from backend/.
  final cwd = Directory.current.path;
  assetsDir = resolveAssetsDir(assetsDir);
  if (dbPath == 'backend/data/demo.db' && cwd.endsWith('backend')) {
    dbPath = 'data/demo.db';
  }

  await runSeed(dbPath: dbPath, assetsDir: assetsDir, force: force);
}
