import 'dart:convert';
import 'dart:io';

import 'package:chat_demo_backend/seed_runner.dart';
import 'package:chat_demo_backend/storage/database.dart';
import 'package:chat_demo_backend/storage/message_repository.dart';
import 'package:test/test.dart';

String _repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/assets/comments/manifest.json').existsSync()) {
      return dir.path;
    }
    if (File('${dir.path}/lib/main.dart').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('Could not find repository root');
}

String _assetsDir() => '${_repoRoot()}/assets/comments';

void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chat_demo_seed_');
    dbPath = '${tempDir.path}/test.db';
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('seeds all messages from manifest', () async {
    await runSeed(
      dbPath: dbPath,
      assetsDir: _assetsDir(),
      force: true,
    );

    final db = DemoDatabase.open(dbPath);
    addTearDown(db.close);
    final repo = MessageRepository(db);
    final conv = repo.getConversation()!;

    final manifestRaw =
        await File('${_assetsDir()}/manifest.json').readAsString();
    final manifest =
        jsonDecode(manifestRaw) as Map<String, Object?>;

    expect(conv.totalMessages, manifest['totalMessages']);
    expect(db.messageCount(), manifest['totalMessages']);
  });

  test('idempotent skip when already seeded', () async {
    await runSeed(dbPath: dbPath, assetsDir: _assetsDir(), force: true);
    await runSeed(dbPath: dbPath, assetsDir: _assetsDir(), force: false);

    final db = DemoDatabase.open(dbPath);
    addTearDown(db.close);
    final manifestRaw =
        await File('${_assetsDir()}/manifest.json').readAsString();
    final manifest =
        jsonDecode(manifestRaw) as Map<String, Object?>;
    expect(db.messageCount(), manifest['totalMessages']);
  });

  test('field parity for messages 0, 5000, 10003', () async {
    await runSeed(dbPath: dbPath, assetsDir: _assetsDir(), force: true);

    final db = DemoDatabase.open(dbPath);
    addTearDown(db.close);
    final repo = MessageRepository(db);

    for (final id in [0, 5000, 10003]) {
      final asset = _messageFromAssets(id);
      final result = repo.fetchRange(fromId: id, toId: id);
      expect(result.messages, hasLength(1));
      final msg = result.messages.first;
      expect(msg.id, asset['id']);
      expect(msg.sender, asset['sender']);
      expect(msg.content, asset['content']);
      expect(msg.createdAt, asset['createdAt']);
    }
  });
}

Map<String, Object?> _messageFromAssets(int id) {
  final manifestRaw =
      File('${_assetsDir()}/manifest.json').readAsStringSync();
  final manifest = jsonDecode(manifestRaw) as Map<String, Object?>;
  final chunkSize = manifest['chunkSize']! as int;
  final chunks = (manifest['chunks']! as List<Object?>).cast<String>();
  final chunkIndex = id ~/ chunkSize;
  final chunkRaw =
      File('${_assetsDir()}/${chunks[chunkIndex]}').readAsStringSync();
  final list = (jsonDecode(chunkRaw) as List<Object?>).cast<Map<String, Object?>>();
  return list.firstWhere((m) => m['id'] == id);
}
