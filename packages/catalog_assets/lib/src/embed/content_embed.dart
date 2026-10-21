import 'dart:ui' hide VoidCallback;

import 'package:catalog_assets/src/asset/asset_binding.dart';
import 'package:catalog_assets/src/asset/asset_cache_scope.dart';
import 'package:catalog_assets/src/asset/asset_playback.dart';
import 'package:catalog_assets/src/asset/asset_preset.dart';
import 'package:catalog_assets/src/embed/inline_embed.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';

/// An [InlineEmbed] that draws cache content: it attaches `(content, spec,
/// profile)` of a preset to an [AssetCacheScope] when created, paints the
/// binding's paintable, and detaches in [dispose].
///
/// The embed is the whole adapter between a body that paints text and the
/// asset cache: stages, budgets, the shared playback clock and the host's
/// pause layers all come from the binding. For a unicode glyph on a platform
/// that bakes it holds the atlas page of its glyph until [dispose] and draws
/// the baked sprite scaled to the rectangle; a platform that draws text
/// plugs a producer that does (`TextGlyphProducer`).
///
/// It is a [PlayableEmbed]: [replay] asks the binding for another pass of a
/// profile that does not loop.
///
/// The embed does not own the scope. Its signal is the binding's: a better
/// stage, a baked page that landed, an animation frame.
final class ContentEmbed implements PlayableEmbed {
  /// Attaches [content] to [scope] as [preset] says.
  ContentEmbed({
    required AssetCacheScope scope,
    required ContentKey content,
    required AssetPreset preset,
  }) : sizeHint = preset.size,
       _binding = scope.attach(content, preset.spec, preset.profile);

  final AssetBinding _binding;
  bool _disposed = false;

  @override
  final Size sizeHint;

  @override
  bool get visible => _binding.visible;

  @override
  set visible(bool value) => _binding.visible = value;

  @override
  AssetPlayback get playback =>
      _disposed ? AssetPlayback.idle : _binding.playback;

  @override
  bool replay() => !_disposed && _binding.replay();

  @override
  void addListener(VoidCallback listener) => _binding.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _binding.removeListener(listener);

  @override
  void paint(Canvas canvas, Rect rect, InlineEmbedPaintContext context) {
    if (_disposed) return;
    _binding.paint(canvas, rect, tint: context.tint, opacity: context.opacity);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _binding.detach();
  }
}
