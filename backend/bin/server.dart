import 'dart:io';

import 'package:chat_demo_backend/api/cors_middleware.dart';
import 'package:chat_demo_backend/api/router.dart';
import 'package:chat_demo_backend/storage/database.dart';
import 'package:chat_demo_backend/storage/message_repository.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  var dbPath = Platform.environment['DB_PATH'] ?? 'backend/data/demo.db';
  if (Directory.current.path.endsWith('backend')) {
    dbPath = dbPath == 'backend/data/demo.db' ? 'data/demo.db' : dbPath;
  }

  final database = DemoDatabase.open(dbPath);
  final repository = MessageRepository(database);

  final handler = Pipeline()
      .addMiddleware(corsMiddleware())
      .addMiddleware(latencyMiddleware())
      .addHandler(createRouter(repository));

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('Demo backend listening on http://127.0.0.1:${server.port}');
}
