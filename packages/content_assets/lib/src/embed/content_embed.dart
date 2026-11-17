import 'dart:ui' hide VoidCallback;

import 'package:content_assets/src/embed/inline_embed.dart';
import 'package:content_assets/src/scope/content_asset_scope.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/rendering.dart' show PaintingContext;
import 'package:flutter/scheduler.dart';
import 'package:listen/listen.dart';
import 'package:mpx_core/mpx_core.dart';

/// An [InlineEmbed] that draws cache content: it attaches `(content, spec,
/// profile)` of a preset to a [ContentAssetScope] when created, paints the
/// binding's paintable, and detaches in [dispose].
///
/// The embed is the whole adapter between a body that paints text and the
/// asset cache: stages, budgets, the shared playback clock and the host's
/// pause layers all come from the binding. For a unicode glyph on a platform
/// that bakes it holds the atlas page of its glyph until [dispose] and draws
/// the baked sprite scaled to the rectangle, or the glyph as text where
/// nothing is baked.
///
/// It is a [PlayableEmbed]: [replay] asks the binding for another pass of a
/// profile that does not loop.
///
/// It is a [CompositingEmbed]: [composite] shows a playing asset whose frames
/// go to a platform texture as a texture layer, the way `ContentView` does. [paint] stays canvas-only, so a body that has only
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
/// [downloadContext] is the class of the surface the embed is shown in, which
/// the scope's auto-download policy weighs (`ContentAssetScope.attach`). An
/// embed paints no status control: content that does not download by itself
/// keeps its best stand-in, and a failure shows nothing more, unless the host
/// lays one over the embed from its [binding] (`ContentEmbedOverlay`).
///
/// [stages] is how an outline preview is drawn: in its `outlineFill`, or for
/// a template asset in the text colour at its `outlineTintOpacity`, swept by
/// its `outlineShimmer` while the outline shows and the clock runs (the
/// embed then tells its listeners once per frame, so the body repaints). By
/// default the platform's (`MediaLoadingStyle.forPlatform`). A body has no
/// build context, so the host resolves it where it makes the embeds
/// (`MediaLoadingStyleScope.resolve`).
///
/// The embed does not own the scope. Its signal is the binding's: a better
/// stage, a baked page that landed, an animation frame.
final class ContentEmbed implements PlayableEmbed, CompositingEmbed {
  /// Attaches [content] to [scope] as [preset] says.
  ContentEmbed({
    required ContentAssetScope scope,
    required ContentKey content,
    required AssetPreset preset,
    AssetPaintable? placeholder,
    ValueListenable<bool>? held,
    AutoDownloadContext? downloadContext,
    MediaStageStyle? stages,
  }) : sizeHint = preset.size,
       _placeholder = placeholder,
       _held = held,
       _template = preset.spec.decodeMode == AssetDecodeMode.template,
       _stages =
           stages ??
           MediaLoadingStyle.forPlatform(defaultTargetPlatform).stages,
       _clock = scope.clock,
       _binding = scope.attach(
         content,
         preset.spec,
         preset.profile,
         downloadContext: downloadContext,
       ) {
    held?.addListener(_onHeld);
    _onHeld();
  }

  final AssetBinding _binding;
  final AssetPaintable? _placeholder;
  final ValueListenable<bool>? _held;
  final bool _template;
  final MediaStageStyle _stages;
  final PlaybackClock _clock;
  // The listeners told when a shimmer moves: the binding says nothing then.
  final List<VoidCallback> _listeners = [];
  bool _sweepScheduled = false;
  bool _disposed = false;

  /// The attach this embed draws: what a host reads to lay a status control
  /// or a badge over the embed (`ContentEmbedOverlay`). Detached once the
  /// embed is disposed.
  AssetBinding get binding => _binding;

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
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    _binding.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    _binding.removeListener(listener);
  }

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
    _binding.paint(
      canvas,
      rect,
      tint: context.tint,
      opacity: context.opacity,
      outline: _outlineLook(context.tint),
    );
  }

  // How an outline preview is drawn, or null when the content has none: a
  // template asset in the text colour, other content in the style's fill (a
  // sticker is not the colour of the text around it), and the sweep while
  // the outline shows and the clock runs.
  OutlineLook? _outlineLook(Color? tint) {
    if (_binding.descriptor?.preview case MediaPreview$Outline()) {
      final fill = switch (tint) {
        final tint? when _template => tint.withValues(
          alpha: tint.a * _stages.outlineTintOpacity,
        ),
        _ => _stages.outlineFill,
      };
      return switch (_stages.outlineShimmer) {
        final shimmer?
            when !_clock.isPaused &&
                _binding.readiness.stage == AssetStage.preview =>
          OutlineLook(fill: fill, highlight: shimmer.phaseAt(_sweepTime())),
        _ => OutlineLook(fill: fill),
      };
    }
    return null;
  }

  // The frame time the sweep is at, and the next frame asked for: once it
  // starts, the embed's listeners are told so the body paints it again.
  Duration _sweepTime() {
    final scheduler = SchedulerBinding.instance;
    if (!_sweepScheduled) {
      _sweepScheduled = true;
      scheduler.scheduleFrameCallback((_) {
        _sweepScheduled = false;
        if (_disposed) return;
        for (final listener in List.of(_listeners)) {
          listener();
        }
      });
    }
    return scheduler.schedulerPhase == SchedulerPhase.idle
        ? Duration.zero
        : scheduler.currentFrameTimeStamp;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _listeners.clear();
    _held?.removeListener(_onHeld);
    _binding.detach();
  }
}
