import 'dart:convert';
import 'dart:io';

import 'package:chat_demo_backend/api/cors_middleware.dart';
import 'package:chat_demo_backend/api/router.dart';
import 'package:chat_demo_backend/seed_runner.dart';
import 'package:chat_demo_backend/storage/database.dart';
import 'package:chat_demo_backend/storage/message_repository.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
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

void main() {
  HttpServer? server;
  late Directory tempDir;
  late String dbPath;
  late String baseUrl;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chat_demo_api_');
    dbPath = '${tempDir.path}/test.db';
    await runSeed(
      dbPath: dbPath,
      assetsDir: '${_repoRoot()}/assets/comments',
      force: true,
    );

    final db = DemoDatabase.open(dbPath);
    final repo = MessageRepository(db);
    final handler = Pipeline()
        .addMiddleware(corsMiddleware())
        .addHandler(createRouter(repo));

    server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server!.address.host}:${server!.port}';
  });

  tearDown(() async {
    await server?.close(force: true);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('GET /health', () async {
    final response = await http.get(Uri.parse('$baseUrl/health'));
    expect(response.statusCode, 200);
    expect(jsonDecode(response.body), {'status': 'ok'});
  });

  test('GET /api/conversation matches manifest', () async {
    final response = await http.get(Uri.parse('$baseUrl/api/conversation'));
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map<String, Object?>;
    final manifestRaw = await File(
      '${_repoRoot()}/assets/comments/manifest.json',
    ).readAsString();
    final manifest = jsonDecode(manifestRaw) as Map<String, Object?>;

    expect(body['title'], manifest['title']);
    expect(body['totalMessages'], manifest['totalMessages']);
    expect(body['chunkSize'], manifest['chunkSize']);
    expect(body['senders'], manifest['senders']);
  });

  test('GET /api/messages returns range with meta', () async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/messages?fromId=0&toId=2'),
    );
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map<String, Object?>;
    final messages = body['messages']! as List<Object?>;
    expect(messages, hasLength(3));
    final meta = body['rangeMeta']! as Map<String, Object?>;
    expect(meta['hasOlder'], isFalse);
    expect(meta['hasNewer'], isTrue);
  });

  test('GET /api/messages invalid range returns 400', () async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/messages?fromId=10&toId=5'),
    );
    expect(response.statusCode, 400);
    final body = jsonDecode(response.body) as Map<String, Object?>;
    expect(body['error'], 'invalid_range');
  });

  test('GET /api/conversation 404 when not seeded', () async {
    final emptyDir = await Directory.systemTemp.createTemp('chat_demo_empty_');
    final emptyDb = '${emptyDir.path}/empty.db';
    final db = DemoDatabase.open(emptyDb);
    final handler = createRouter(MessageRepository(db));
    final s = await shelf_io.serve(
      handler,
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async {
      await s.close(force: true);
      db.close();
      emptyDir.deleteSync(recursive: true);
    });

    final response = await http.get(
      Uri.parse('http://${s.address.host}:${s.port}/api/conversation'),
    );
    expect(response.statusCode, 404);
    final body = jsonDecode(response.body) as Map<String, Object?>;
    expect(body['error'], 'not_seeded');
  });
}
