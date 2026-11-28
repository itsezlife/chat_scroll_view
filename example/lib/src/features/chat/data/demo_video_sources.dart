import 'dart:io';

import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:content_assets/content_assets.dart';
import 'package:flutter/services.dart';
import 'package:mpx_core/mpx_core.dart' show MediaKey;
import 'package:mpx_player/mpx_player.dart';

/// Where a native player reads the demo's bundled clips: each clip of the
/// [VideoStickerPack] is copied once from the bundle into [folder] and
/// played from there in place ([PlayerSource.local]); other content has no
/// source here.
///
/// It stands in for the backend a real host streams its videos from: the
/// bundle is no file a platform player can open, so the bytes land in one
/// first. Native platforms only (it writes files).
final class DemoVideoSources {
  /// Sources copied into [folder] (the system's temporary folder by
  /// default), read from [bundle] (the root bundle by default).
  DemoVideoSources({Directory? folder, AssetBundle? bundle})
    : _folder = folder,
      _bundle = bundle ?? rootBundle;

  final Directory? _folder;
  final AssetBundle _bundle;
  final Map<MediaKey, Future<File>> _$copies = {};

  static final Map<MediaKey, VideoPackItem> _clips = {
    for (final clip in VideoStickerPack.clips) clip.key.mediaKey: clip,
  };

  /// The sources of [key]: one local file for a bundled clip, none for any
  /// other key.
  Future<List<PlayerSource>> of(MediaKey key) async {
    final clip = _clips[key];
    if (clip == null) return const [];
    final file = await (_$copies[key] ??= _copy(clip));
    return [PlayerSource.local(file.uri)];
  }

  Future<File> _copy(VideoPackItem clip) async {
    final folder =
        _folder ?? Directory('${Directory.systemTemp.path}/demo-video');
    await folder.create(recursive: true);
    final file = File('${folder.path}/${clip.name}.${clip.extension}');
    final bytes = await _bundle.load(clip.assetPath);
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file;
  }
}
