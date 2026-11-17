import 'dart:math' as math;
import 'dart:ui';

import 'package:mpx_core/mpx_core.dart';

/// The presets of the surfaces that show content in a chat: a panel cell, a
/// glyph or a custom emoji set in message text, an emoji-only message, the
/// single-emoji sticker and a round video message.
///
/// They build on the core's `AssetPresets.square` and `AssetPresets.media`,
/// which stay in `mpx_core`; these name the chat's own surfaces and their
/// rules.
abstract final class ContentAssetPresets {
  /// A cell of a content grid or strip: a square of [extent] logical pixels,
  /// decoded at [devicePixelRatio] as [decodeMode] and filled as [fit].
  ///
  /// Plays and loops while visible unless [animate] is false (a grid that
  /// should show stills).
  ///
  /// A playing cell of at most [smallCellExtent] logical pixels is small: it
  /// plays at half rate (`AssetProfile.halfFrameRate`) and decodes at most
  /// [smallCellPixels] on a side, however dense the screen. This is the
  /// rule for a sticker drawn at up to 90 dp (rendered at
  /// 160 px at most, every second frame): a grid of small playing cells is
  /// what a content panel shows most of, and at full rate and size it costs
  /// a render and a post per cell every frame. A still cell keeps its full
  /// pixels: it is drawn once.
  static AssetPreset keyboardCell({
    required double extent,
    required double devicePixelRatio,
    bool animate = true,
    AssetDecodeMode decodeMode = AssetDecodeMode.original,
    AssetFit fit = AssetFit.contain,
  }) {
    final small = animate && extent <= smallCellExtent;
    final full = AssetSpec.atDensity(
      logicalWidth: extent,
      logicalHeight: extent,
      devicePixelRatio: devicePixelRatio,
      decodeMode: decodeMode,
    );
    final pixels = small
        ? math.min(full.pixelWidth, smallCellPixels)
        : full.pixelWidth;
    return AssetPreset(
      size: Size.square(extent),
      spec: AssetSpec(
        pixelWidth: pixels,
        pixelHeight: pixels,
        decodeMode: decodeMode,
      ),
      profile: AssetProfile(animate: animate, fit: fit, halfFrameRate: small),
    );
  }

  /// The largest extent, in logical pixels, of a [keyboardCell] that plays
  /// as a small one.
  static const double smallCellExtent = 90;

  /// The most pixels on a side a small playing [keyboardCell] decodes at.
  static const int smallCellPixels = 160;

  /// Content set inline in text whose line is [ascent] + [descent] tall: a
  /// square of 1.2 times that, rounded to whole device pixels at
  /// [devicePixelRatio].
  ///
  /// This is the rule for inline custom emoji: the box
  /// follows the font's vertical metrics, not its em, because an emoji is
  /// wider than the em of the font it sits in. Every embed of a paragraph
  /// takes the same metrics, so they share one spec and one cache entry per
  /// key. [ascent] and [descent] are positive logical pixels, as
  /// `InlineEmbedMetrics` carries them.
  ///
  /// The pixel size is rounded, not rounded up like `AssetSpec.atDensity`,
  /// and the logical [AssetPreset.size] is that pixel count over the density,
  /// so the decode is exactly the box the body reserves.
  ///
  /// Plays and loops while visible unless [animate] is false. Pass
  /// [AssetDecodeMode.template] for content the surrounding text colour
  /// tints.
  static AssetPreset inlineMessage({
    required double ascent,
    required double descent,
    required double devicePixelRatio,
    AssetDecodeMode decodeMode = AssetDecodeMode.original,
    bool animate = true,
  }) {
    assert(
      ascent > 0 && descent > 0 && devicePixelRatio > 0,
      'An inline preset needs positive metrics and density.',
    );
    final pixels = math.max(
      1,
      (_inlineExtentPerLine * (ascent + descent) * devicePixelRatio).round(),
    );
    return AssetPreset(
      size: Size.square(pixels / devicePixelRatio),
      spec: AssetSpec(
        pixelWidth: pixels,
        pixelHeight: pixels,
        decodeMode: decodeMode,
      ),
      profile: AssetProfile(animate: animate),
    );
  }

  /// Content set in text that has no font metrics to ask: a square of 1.2
  /// times [fontSize], decoded at [devicePixelRatio].
  ///
  /// For a surface that knows only the font size of its text. A body that
  /// lays text out has the ascent and descent and uses [inlineMessage]
  /// instead, which is this preset's rule. Plays and loops while
  /// visible unless [animate] is false.
  static AssetPreset inlineFontSize({
    required double fontSize,
    required double devicePixelRatio,
    AssetDecodeMode decodeMode = AssetDecodeMode.original,
    bool animate = true,
  }) => AssetPresets.square(
    extent: fontSize * _inlineExtentPerLine,
    devicePixelRatio: devicePixelRatio,
    decodeMode: decodeMode,
    profile: AssetProfile(animate: animate),
  );

  /// One item of an emoji-only message laid out as text, at the font size
  /// [step] its count gives: a square of [step] plus [emojiOnlyBoxPadding],
  /// decoded at [devicePixelRatio].
  ///
  /// A step is a font size in logical pixels, so this package does not know
  /// the viewport's table of steps. Each step is its own size and so its own
  /// cache entry; the same step at the same density is one. Custom emoji animate and loop; pass [animate] false for
  /// an item that is a still.
  static AssetPreset emojiOnly({
    required double step,
    required double devicePixelRatio,
    bool animate = true,
  }) => AssetPresets.square(
    extent: step + emojiOnlyBoxPadding,
    devicePixelRatio: devicePixelRatio,
    profile: AssetProfile(animate: animate),
  );

  /// The single-emoji sticker: a square of [extent] logical pixels, decoded
  /// at that size at [devicePixelRatio].
  ///
  /// It plays once and does not loop, then rests on [restFrame] (the first
  /// frame by default) until the host replays it
  /// (`AssetBinding.replay`). [autoplay] says whether it starts when it
  /// attaches; the host decides it (a memory of what already played, per
  /// chat), never the cache. With [autoplay] false the sticker holds its
  /// first frame until the host replays it.
  static AssetPreset emojiSticker({
    required double extent,
    required double devicePixelRatio,
    bool autoplay = true,
    AssetRestFrame restFrame = AssetRestFrame.first,
  }) => AssetPresets.square(
    extent: extent,
    devicePixelRatio: devicePixelRatio,
    profile: AssetProfile(animate: autoplay, loop: false, restFrame: restFrame),
  );

  /// A round video message: a circle of [diameter] logical pixels, decoded
  /// at that size at [devicePixelRatio], filled (the clip's centre is kept),
  /// playing and looping silently while visible unless [autoplay] is false.
  ///
  /// Round (`AssetPreset.isRound`): its stand-ins are drawn enlarged in the
  /// circle and its status control takes the round size of the platform's
  /// style. A surface passes the bubble's colour as the view's underlay, so
  /// the circle is filled until the clip has faded in.
  static AssetPreset roundVideo({
    required double diameter,
    required double devicePixelRatio,
    bool autoplay = true,
  }) => AssetPresets.round(
    diameter: diameter,
    devicePixelRatio: devicePixelRatio,
    profile: AssetProfile(animate: autoplay, fit: AssetFit.cover),
  );

  /// Logical pixels an emoji-only item's box adds to its font size (the box is
  /// the font size plus 4 dp).
  static const double emojiOnlyBoxPadding = 4;

  static const double _inlineExtentPerLine = 1.2;
}
