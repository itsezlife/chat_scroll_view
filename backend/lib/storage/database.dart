import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Opens (or creates) the demo SQLite database and applies schema migrations.
class DemoDatabase {
  DemoDatabase(this._db);

  final Database _db;

  Database get raw => _db;

  static DemoDatabase open(String path) {
    final dir = Directory(path).parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final db = sqlite3.open(path);
    final demo = DemoDatabase(db);
    demo._applySchema();
    return demo;
  }

  void _applySchema() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY,
        sender TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS conversation_meta (
        id TEXT PRIMARY KEY DEFAULT 'default',
        title TEXT NOT NULL,
        total_messages INTEGER NOT NULL,
        chunk_size INTEGER NOT NULL DEFAULT 64,
        senders_json TEXT NOT NULL
      )
    ''');
  }

  void close() => _db.dispose();

  int messageCount() {
    final result = _db.select('SELECT COUNT(*) AS c FROM messages');
    return result.first['c']! as int;
  }
}
