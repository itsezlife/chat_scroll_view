import 'dart:convert';
import 'dart:io';

import 'package:chat_demo_backend/storage/database.dart';
import 'package:chat_demo_backend/storage/message_repository.dart';

/// Parsed manifest.json from assets/comments.
class SeedManifest {
  SeedManifest({
    required this.title,
    required this.totalMessages,
    required this.chunkSize,
    required this.chunks,
    required this.senders,
  });

  factory SeedManifest.fromJson(Map<String, Object?> json) => SeedManifest(
    title: json['title']! as String,
    totalMessages: json['totalMessages']! as int,
    chunkSize: json['chunkSize']! as int,
    chunks: (json['chunks']! as List<Object?>).cast<String>(),
    senders: (json['senders']! as List<Object?>).cast<String>(),
  );

  final String title;
  final int totalMessages;
  final int chunkSize;
  final List<String> chunks;
  final List<String> senders;
}

/// Resolves [assetsDir] to a directory containing manifest.json.
String resolveAssetsDir(String assetsDir) {
  if (File('$assetsDir/manifest.json').existsSync()) {
    return assetsDir;
  }
  if (File('../$assetsDir/manifest.json').existsSync()) {
    return '../$assetsDir';
  }
  // Walk up from cwd looking for assets/comments/manifest.json
  var dir = Directory.current;
  while (true) {
    final candidate = '${dir.path}/$assetsDir';
    if (File('$candidate/manifest.json').existsSync()) {
      return candidate;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return assetsDir;
}

/// Seeds SQLite from bundled comment asset JSON files.
Future<void> runSeed({
  required String dbPath,
  required String assetsDir,
  bool force = false,
}) async {
  assetsDir = resolveAssetsDir(assetsDir);
  final db = DemoDatabase.open(dbPath);
  try {
    final repo = MessageRepository(db);
    if (!force && repo.isSeeded) {
      final count = db.messageCount();
      final manifestFile = File('$assetsDir/manifest.json');
      if (manifestFile.existsSync()) {
        final manifest = SeedManifest.fromJson(
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>,
        );
        if (count == manifest.totalMessages) {
          stdout.writeln(
            'Already seeded ($count messages). Use --force to re-seed.',
          );
          return;
        }
      }
    }

    final manifestRaw =
        await File('$assetsDir/manifest.json').readAsString();
    final manifest = SeedManifest.fromJson(
      jsonDecode(manifestRaw) as Map<String, Object?>,
    );

    db.raw.execute('DELETE FROM messages');
    db.raw.execute("DELETE FROM conversation_meta WHERE id = 'default'");

    db.raw.execute(
      "INSERT INTO conversation_meta (id, title, total_messages, chunk_size, senders_json) "
      "VALUES ('default', ?, ?, ?, ?)",
      [
        manifest.title,
        manifest.totalMessages,
        manifest.chunkSize,
        jsonEncode(manifest.senders),
      ],
    );

    var inserted = 0;
    for (final chunkFile in manifest.chunks) {
      final raw = await File('$assetsDir/$chunkFile').readAsString();
      final list = (jsonDecode(raw) as List<Object?>).cast<Map<String, Object?>>();
      for (final item in list) {
        db.raw.execute(
          'INSERT OR REPLACE INTO messages (id, sender, content, created_at) '
          'VALUES (?, ?, ?, ?)',
          [
            item['id']! as int,
            item['sender']! as String,
            item['content'] as String? ?? '',
            item['createdAt'] as String? ?? '',
          ],
        );
        inserted++;
      }
    }

    final count = db.messageCount();
    if (count != manifest.totalMessages) {
      stderr.writeln(
        'Warning: inserted $inserted rows but COUNT is $count '
        '(expected ${manifest.totalMessages})',
      );
    }
    stdout.writeln('Seeded $count messages into $dbPath');
  } finally {
    db.close();
  }
}
