import 'dart:ui' hide VoidCallback;

import 'package:catalog_assets/src/asset/asset_binding.dart';
import 'package:catalog_assets/src/asset/asset_cache_scope.dart';
import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/asset/asset_playback.dart';
import 'package:catalog_assets/src/asset/asset_preset.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/asset/asset_texture_layer.dart';
import 'package:catalog_assets/src/embed/inline_embed.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/rendering.dart' show PaintingContext;
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
/// It is a [CompositingEmbed]: [composite] shows a playing asset whose frames
/// go to a platform texture as a texture layer (ADR 043), through the same
/// path as `ContentView`. [paint] stays canvas-only, so a body that has only
/// a canvas draws the asset from its page slots.
///
/// Which placeholder shows until the content has a thumbnail is the scope's
/// (a circle) unless the embed is given its own: the host knows that this
/// content is a sticker, the scope shared by all embeds does not.
///
/// [held] is the host's hold on the surface the embed is shown on: while it
/// is true the binding is held (`AssetBinding.held`), so the embed shows the
/// frame it is on and keeps it, while the scope's other surfaces play. The
/// host feeds one listenable to every embed of that surface; the embed reads
/// it now, follows it, and never disposes it.
///
/// The embed does not own the scope. Its signal is the binding's: a better
/// stage, a baked page that landed, an animation frame.
final class ContentEmbed implements PlayableEmbed, CompositingEmbed {
  /// Attaches [content] to [scope] as [preset] says.
  ContentEmbed({
    required AssetCacheScope scope,
    required ContentKey content,
    required AssetPreset preset,
    AssetPaintable? placeholder,
    ValueListenable<bool>? held,
  }) : sizeHint = preset.size,
       _placeholder = placeholder,
       _held = held,
       _binding = scope.attach(content, preset.spec, preset.profile) {
    held?.addListener(_onHeld);
    _onHeld();
  }

  final AssetBinding _binding;
  final AssetPaintable? _placeholder;
  final ValueListenable<bool>? _held;
  bool _disposed = false;

  void _onHeld() {
    if (_held case final held? when !_disposed) _binding.held = held.value;
  }

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
  bool get needsCompositing => !_disposed && _binding.paintable.isAnimated;

  @override
  void composite(
    PaintingContext context,
    Rect rect,
    InlineEmbedPaintContext paint,
  ) {
    if (_disposed) return;
    if (_binding.readiness.stage != AssetStage.none &&
        AssetTextureLayer.composite(
          context,
          _binding,
          rect,
          opacity: paint.opacity,
        )) {
      return;
    }
    this.paint(context.canvas, rect, paint);
  }

  @override
  void paint(Canvas canvas, Rect rect, InlineEmbedPaintContext context) {
    if (_disposed) return;
    // Before anything exists the embed's own placeholder replaces the scope's
    // (every embed of a scope shares that one, whatever the content): a
    // sticker is not drawn as the circle of an emoji. A thumbnail is the
    // binding's to paint.
    if (_placeholder case final placeholder?
        when _binding.readiness.stage == AssetStage.none) {
      placeholder.paint(
        canvas,
        rect,
        AssetPaintContext(tint: context.tint, opacity: context.opacity),
      );
      return;
    }
    _binding.paint(canvas, rect, tint: context.tint, opacity: context.opacity);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _held?.removeListener(_onHeld);
    _binding.detach();
  }
}
