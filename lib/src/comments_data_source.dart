import 'dart:async';
import 'dart:convert';

import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/load_asset.dart'
    if (dart.library.js_interop) 'package:chatscrollview/src/load_asset_web.dart'
    if (dart.library.io) 'package:chatscrollview/src/load_asset_native.dart';

/// Manifest for asset-based chat data.
class CommentsManifest {
  CommentsManifest._({
    required this.title,
    required this.totalMessages,
    required this.chunkSize,
    required this.chunks,
    required this.senders,
  });

  factory CommentsManifest.fromJson(Map<String, Object?> json) => CommentsManifest._(
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

/// Data source that loads pre-chunked JSON assets (e.g. GitHub issues).
///
/// Each chunk file contains up to [ChatScrollChunk.kSize] messages as JSON:
/// ```json
/// [{"id": 0, "sender": "user", "content": "...", "createdAt": "..."}]
/// ```
class CommentsDataSource extends ChatDataSource {
  CommentsDataSource._({
    required this.manifest,
    required this.assetPrefix,
    required this.fetchDelay,
  });

  /// Load manifest and return a ready-to-use data source.
  static Future<CommentsDataSource> load({
    String assetPrefix = 'assets/comments',
    Duration fetchDelay = const Duration(milliseconds: 120),
  }) async {
    final raw = await _loadString('$assetPrefix/manifest.json');
    final json = jsonDecode(raw) as Map<String, Object?>;
    final manifest = CommentsManifest.fromJson(json);
    return CommentsDataSource._(
      manifest: manifest,
      assetPrefix: assetPrefix,
      fetchDelay: fetchDelay,
    );
  }

  /// On native — loads from bundled assets via rootBundle.
  /// On web — fetches on demand via HTTP (assets excluded from service worker).
  static Future<String> _loadString(String assetPath) =>
      loadAsset(assetPath);

  final CommentsManifest manifest;
  final String assetPrefix;
  final Duration fetchDelay;

  final Map<int, List<IChatMessage>> _chunkCache = <int, List<IChatMessage>>{};

  @override
  Future<List<IChatMessage>> fetch({
    int? from,
    int? to,
    DateTime? after,
  }) async {
    // Simulate network delay.
    await Future<void>.delayed(fetchDelay);

    final lo = (from ?? 0).clamp(0, manifest.totalMessages - 1);
    final hi = (to ?? manifest.totalMessages - 1)
        .clamp(0, manifest.totalMessages - 1);

    // Determine which asset chunks we need.
    final firstAssetChunk = lo ~/ manifest.chunkSize;
    final lastAssetChunk = hi ~/ manifest.chunkSize;

    final result = <IChatMessage>[];

    for (var ac = firstAssetChunk; ac <= lastAssetChunk; ac++) {
      final messages = await _loadAssetChunk(ac);
      for (final msg in messages) {
        if (msg.id >= lo && msg.id <= hi) result.add(msg);
      }
    }

    return result;
  }

  Future<List<IChatMessage>> _loadAssetChunk(int assetChunkIndex) async {
    if (_chunkCache.containsKey(assetChunkIndex)) {
      return _chunkCache[assetChunkIndex]!;
    }

    if (assetChunkIndex >= manifest.chunks.length) return const [];

    final fileName = manifest.chunks[assetChunkIndex];
    final raw = await _loadString('$assetPrefix/$fileName');
    final list = (jsonDecode(raw) as List<Object?>).cast<Map<String, Object?>>();

    final baseTime = DateTime.now();
    final messages = <IChatMessage>[
      for (final item in list)
        ChatMessage$User(
          id: item['id']! as int,
          sender: item['sender']! as String,
          createdAt: DateTime.tryParse(item['createdAt'] as String? ?? '') ??
              baseTime,
          updatedAt: DateTime.tryParse(item['createdAt'] as String? ?? '') ??
              baseTime,
          content: item['content'] as String? ?? '',
        ),
    ];

    _chunkCache[assetChunkIndex] = messages;
    return messages;
  }
}
