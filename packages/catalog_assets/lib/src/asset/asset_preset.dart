import 'dart:math' as math;
import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_profile.dart';
import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:meta/meta.dart';

/// A named recipe a surface attaches with: the logical [size] it shows an
/// asset at, and the [spec] and [profile] that size and use imply.
///
/// A surface does not choose pixels, decode modes or playback flags itself; it
/// picks a preset, so two surfaces that mean the same thing share one decode
/// (the spec is part of the entry identity) and a host changes how a class of
/// surfaces looks in one place. Presets are plain values: a host builds its
/// own with the constructor, and `AssetPresets` has the ones the packages
/// share.
@immutable
final class AssetPreset {
  /// Creates a preset showing assets at [size] (logical pixels), decoded as
  /// [spec] and used as [profile] says.
  const AssetPreset({
    required this.size,
    required this.spec,
    required this.profile,
  });

  /// The logical box the surface shows the asset in. It is the size hint of an
  /// inline embed and the natural size of a `ContentView`.
  final Size size;

  /// What is decoded: the pixels [size] takes at the device density.
  final AssetSpec spec;

  /// How the surface uses the asset.
  final AssetProfile profile;

  @override
  bool operator ==(Object other) =>
      other is AssetPreset &&
      other.size == size &&
      other.spec == spec &&
      other.profile == profile;

  @override
  int get hashCode => Object.hash(size, spec, profile);

  @override
  String toString() => 'AssetPreset($size, $spec, $profile)';
}

/// The presets of the surfaces that draw content: a cell of a content grid,
/// a piece of content set inside message text, and the items of an emoji-only
/// message.
abstract final class AssetPresets {
  /// A cell of a content grid or strip: a square of [extent] logical pixels,
  /// decoded at [devicePixelRatio].
  ///
  /// Plays and loops while visible unless [animate] is false (a grid that
  /// should show stills).
  static AssetPreset keyboardCell({
    required double extent,
    required double devicePixelRatio,
    bool animate = true,
  }) => square(
    extent: extent,
    devicePixelRatio: devicePixelRatio,
    profile: AssetProfile(animate: animate),
  );

  /// Content set inline in text whose line is [ascent] + [descent] tall: a
  /// square of 1.2 times that, rounded to whole device pixels at
  /// [devicePixelRatio].
  ///
  /// This is the reference client's rule for inline custom emoji: the box
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
  /// instead, which is the reference client's rule. Plays and loops while
  /// visible unless [animate] is false.
  static AssetPreset inlineFontSize({
    required double fontSize,
    required double devicePixelRatio,
    AssetDecodeMode decodeMode = AssetDecodeMode.original,
    bool animate = true,
  }) => square(
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
  /// cache entry, as the reference client's cache types are; the same step at the same
  /// density is one. Custom emoji animate and loop; pass [animate] false for
  /// an item that is a still.
  static AssetPreset emojiOnly({
    required double step,
    required double devicePixelRatio,
    bool animate = true,
  }) => square(
    extent: step + emojiOnlyBoxPadding,
    devicePixelRatio: devicePixelRatio,
    profile: AssetProfile(animate: animate),
  );

  /// The single-emoji sticker: a square of [extent] logical pixels, decoded
  /// at that size at [devicePixelRatio].
  ///
  /// It plays once and does not loop, then rests on [restFrame] (the first
  /// frame by default, as Android and Desktop do) until the host replays it
  /// (`AssetBinding.replay`). [autoplay] says whether it starts when it
  /// attaches; the host decides it (a memory of what already played, per
  /// chat), never the cache. With [autoplay] false the sticker holds its
  /// first frame until the host replays it.
  static AssetPreset emojiSticker({
    required double extent,
    required double devicePixelRatio,
    bool autoplay = true,
    AssetRestFrame restFrame = AssetRestFrame.first,
  }) => square(
    extent: extent,
    devicePixelRatio: devicePixelRatio,
    profile: AssetProfile(animate: autoplay, loop: false, restFrame: restFrame),
  );

  /// A square of [extent] logical pixels decoded at [devicePixelRatio], used
  /// as [profile] says.
  ///
  /// The way to a preset no named recipe covers: the pixel size is the extent
  /// at the density, rounded up so the decode is never smaller than the box.
  static AssetPreset square({
    required double extent,
    required double devicePixelRatio,
    required AssetProfile profile,
    AssetDecodeMode decodeMode = AssetDecodeMode.original,
  }) => AssetPreset(
    size: Size.square(extent),
    spec: AssetSpec.atDensity(
      logicalWidth: extent,
      logicalHeight: extent,
      devicePixelRatio: devicePixelRatio,
      decodeMode: decodeMode,
    ),
    profile: profile,
  );

  /// Logical pixels an emoji-only item's box adds to its font size (the
  /// reference client's `font + 4 dp`).
  static const double emojiOnlyBoxPadding = 4;

  static const double _inlineExtentPerLine = 1.2;
}
